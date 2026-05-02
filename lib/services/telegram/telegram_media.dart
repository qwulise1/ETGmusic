import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:etgmusic/provider/database/database.dart';
import 'package:etgmusic/models/metadata/metadata.dart';
import 'package:etgmusic/provider/telegram/telegram_auth.dart';
import 'package:etgmusic/services/dio/dio.dart';
import 'package:etgmusic/services/kv_store/kv_store.dart';
import 'package:etgmusic/services/telegram/telegram_mtproto.dart';
import 'package:etgmusic/services/telegram/telegram_sync_notifications.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final telegramMediaRevisionProvider = StateProvider<int>((ref) => 0);

final telegramMediaServiceProvider = Provider<TelegramMediaService>(
  TelegramMediaService.new,
);

final telegramMediaTracksProvider =
    FutureProvider<List<SpotubeFullTrackObject>>((ref) async {
  ref.watch(telegramMediaRevisionProvider);
  return ref.read(telegramMediaServiceProvider).loadTracks();
});

final telegramSourceFiltersProvider = FutureProvider<List<String>>((ref) async {
  ref.watch(telegramMediaRevisionProvider);
  return ref.read(telegramMediaServiceProvider).loadSourceFilters();
});

final telegramTrackCacheStatusProvider =
    FutureProvider.autoDispose.family<TelegramTrackCacheStatus?, String>(
  (ref, trackId) async {
    ref.watch(telegramMediaRevisionProvider);
    return ref.read(telegramMediaServiceProvider).loadCacheStatus(trackId);
  },
);

final telegramSyncProgressProvider = StateProvider<TelegramSyncProgress>(
  (ref) => const TelegramSyncProgress.idle(),
);

class TelegramTrackCacheStatus {
  final bool cached;
  final String? error;

  const TelegramTrackCacheStatus({
    required this.cached,
    this.error,
  });

  bool get failed => !cached;
}

class TelegramSyncProgress {
  final bool running;
  final bool completed;
  final String stage;
  final String message;
  final int progress;
  final int max;
  final int scanned;
  final int found;
  final int cached;
  final int failed;
  final String? error;

  const TelegramSyncProgress({
    required this.running,
    required this.completed,
    required this.stage,
    required this.message,
    this.progress = 0,
    this.max = 0,
    this.scanned = 0,
    this.found = 0,
    this.cached = 0,
    this.failed = 0,
    this.error,
  });

  const TelegramSyncProgress.idle()
      : running = false,
        completed = false,
        stage = "Ожидание",
        message = "Синхронизация не запущена",
        progress = 0,
        max = 0,
        scanned = 0,
        found = 0,
        cached = 0,
        failed = 0,
        error = null;

  bool get indeterminate => max <= 0;
  double? get value => max <= 0 ? null : progress.clamp(0, max) / max;

  String get notificationText {
    final counters = [
      if (scanned > 0) "просмотрено $scanned",
      if (found > 0) "треков $found",
      if (cached > 0) "скачано $cached",
      if (failed > 0) "ошибок $failed",
    ].join(" · ");
    if (counters.isEmpty) return message;
    return "$message · $counters";
  }
}

typedef TelegramSyncProgressHandler = void Function(
  TelegramSyncProgress progress,
);

class TelegramMediaService {
  static const _tracksKey = "telegram_media_tracks";
  static const _sourcesKey = "telegram_media_sources";
  static const _albumOverridesKey = "telegram_album_overrides";
  static const _updateOffsetKey = "telegram_media_update_offset";
  static bool _syncRunning = false;
  final TelegramMtprotoService _mtproto = TelegramMtprotoService();

  final Ref ref;

  TelegramMediaService(this.ref);

  Future<List<String>> loadSourceFilters() async {
    final raw = KVStoreService.sharedPreferences.getStringList(_sourcesKey);
    return raw?.where((value) => value.trim().isNotEmpty).toList() ?? const [];
  }

  Future<List<String>> setSourceFiltersFromText(String raw) async {
    final values = _normalizeSourceFilters(raw);

    await KVStoreService.sharedPreferences.setStringList(_sourcesKey, values);
    ref.read(telegramMediaRevisionProvider.notifier).state++;
    return values;
  }

  List<String> _normalizeSourceFilters(String raw) {
    return raw
        .split(RegExp(r"[\n,;]+"))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
  }

  Future<void> startBackgroundSync() async {
    if (_syncRunning) {
      throw const TelegramMediaException("Синхронизация уже идет");
    }

    final auth = await ref.read(telegramAuthProvider.future);
    if (!auth.isConnected) {
      throw const TelegramMediaException("Сначала подключи Telegram");
    }

    _syncRunning = true;
    await TelegramSyncNotifications.requestPermission().catchError((_) {});
    _publishSyncProgress(
      const TelegramSyncProgress(
        running: true,
        completed: false,
        stage: "Запуск",
        message: "Готовлю Telegram-синхронизацию",
      ),
    );

    unawaited(_runBackgroundSync(auth));
  }

  Future<void> _runBackgroundSync(TelegramAuthState auth) async {
    try {
      final result = auth.isUserSessionConnected
          ? await syncUserSessionHistory(onProgress: _publishSyncProgress)
          : await syncBotUpdates(onProgress: _publishSyncProgress);
      _publishSyncProgress(
        TelegramSyncProgress(
          running: false,
          completed: true,
          stage: "Готово",
          message:
              "Синхронизация завершена: +${result.added}, всего ${result.total}",
          progress: result.cached + result.failed,
          max: result.cached + result.failed,
          scanned: result.scanned,
          found: result.total,
          cached: result.cached,
          failed: result.failed,
        ),
      );
    } catch (error) {
      _publishSyncProgress(
        TelegramSyncProgress(
          running: false,
          completed: false,
          stage: "Ошибка",
          message: "Синхронизация остановлена",
          error: error.toString(),
        ),
      );
    } finally {
      _syncRunning = false;
    }
  }

  void _publishSyncProgress(TelegramSyncProgress progress) {
    ref.read(telegramSyncProgressProvider.notifier).state = progress;
    unawaited(
      TelegramSyncNotifications.show(
        title: "ETGmusic · Telegram",
        text: progress.error ?? progress.notificationText,
        progress: progress.progress,
        max: progress.max,
        indeterminate: progress.indeterminate,
        done: !progress.running,
      ).catchError((_) {}),
    );
  }

  Future<List<SpotubeFullTrackObject>> loadTracks() async {
    final albumOverrides = _readAlbumOverrides();
    return (await _readStoredTracks())
        .map((track) => _applyAlbumOverride(
              track.toMetadata(),
              albumOverrides,
            ))
        .toList();
  }

  Future<SpotubeFullTrackObject?> findTrack(String id) async {
    final records = await _readStoredTracks();
    final albumOverrides = _readAlbumOverrides();
    return records
        .where((track) => track.id == id)
        .map((track) => _applyAlbumOverride(
              track.toMetadata(),
              albumOverrides,
            ))
        .firstOrNull;
  }

  Future<TelegramTrackCacheStatus?> loadCacheStatus(String id) async {
    final record = (await _readStoredTracks()).firstWhereOrNull(
      (track) => track.id == id,
    );
    if (record == null || !record.fileUrl.startsWith("telegram-mtproto://")) {
      return null;
    }

    final cacheFile = await _mtprotoAudioCacheFile(record);
    if (await _isUsableAudioCache(cacheFile, record)) {
      return const TelegramTrackCacheStatus(cached: true);
    }

    if (record.cacheReady == false) {
      return TelegramTrackCacheStatus(
        cached: false,
        error: record.cacheError,
      );
    }

    return null;
  }

  Future<SpotubeFullTrackObject> updateTrackMetadata(
    String id, {
    required String name,
    required String artist,
    required String album,
    String? coverUrl,
  }) async {
    final records = await _readStoredTracks();
    final index = records.indexWhere((track) => track.id == id);
    if (index < 0) {
      throw const TelegramMediaException("Telegram-трек не найден");
    }

    final record = records[index];
    final updatedRecord = record.copyWith(
      manualName: name.trim().isEmpty ? null : name.trim(),
      manualArtist: artist.trim().isEmpty ? null : artist.trim(),
      manualAlbum: album.trim().isEmpty ? null : album.trim(),
      coverUrl: coverUrl?.trim().isEmpty == true ? null : coverUrl?.trim(),
    );
    records[index] = updatedRecord;

    await _writeStoredTracks(records);
    final database = ref.read(databaseProvider);
    await (database.delete(database.lyricsTable)
          ..where((table) => table.trackId.equals(id)))
        .go();
    await (database.delete(database.sourceMatchTable)
          ..where((table) => table.trackId.equals(id)))
        .go();
    ref.invalidate(telegramMediaTracksProvider);
    ref.read(telegramMediaRevisionProvider.notifier).state++;
    return _applyAlbumOverride(
      updatedRecord.toMetadata(),
      _readAlbumOverrides(),
    );
  }

  SpotubeSimpleAlbumObject applyAlbumOverride(
    SpotubeSimpleAlbumObject album,
  ) {
    final override = _readAlbumOverrides()[album.id];
    if (override == null) return album;
    return _applyAlbumOverrideToAlbum(album, override);
  }

  Future<SpotubeSimpleAlbumObject> updateAlbumMetadata(
    SpotubeSimpleAlbumObject album, {
    required String name,
    String? coverUrl,
  }) async {
    if (!album.id.startsWith("telegram:")) {
      throw const TelegramMediaException(
        "Редактирование доступно только для Telegram-альбомов",
      );
    }

    final overrides = _readAlbumOverrides();
    final cleanName = name.trim();
    final cleanCover = coverUrl?.trim() ?? "";

    if (cleanName.isEmpty && cleanCover.isEmpty) {
      overrides.remove(album.id);
    } else {
      overrides[album.id] = TelegramAlbumOverride(
        name: cleanName.isEmpty ? null : cleanName,
        coverUrl: cleanCover.isEmpty ? null : cleanCover,
      );
    }

    await KVStoreService.sharedPreferences.setString(
      _albumOverridesKey,
      jsonEncode(
        overrides.map(
          (key, value) => MapEntry(key, value.toJson()),
        ),
      ),
    );

    final database = ref.read(databaseProvider);
    final affectedTrackIds = (await _readStoredTracks())
        .where((track) => track.toMetadata().album.id == album.id)
        .map((track) => track.id)
        .toList();
    for (final trackId in affectedTrackIds) {
      await (database.delete(database.lyricsTable)
            ..where((table) => table.trackId.equals(trackId)))
          .go();
    }

    ref.invalidate(telegramMediaTracksProvider);
    ref.read(telegramMediaRevisionProvider.notifier).state++;
    return applyAlbumOverride(album);
  }

  Future<TelegramSyncResult> syncBotUpdates({
    TelegramSyncProgressHandler? onProgress,
  }) async {
    final token = await ref.read(telegramAuthProvider.notifier).readBotToken();
    if (token == null || token.trim().isEmpty) {
      throw const TelegramMediaException("Сначала подключи Telegram bot token");
    }

    final sourceFilters = await loadSourceFilters();
    final recordsById = {
      for (final track in await _readStoredTracks()) track.id: track,
    };

    final response = await globalDio.get(
      "https://api.telegram.org/bot$token/getUpdates",
      queryParameters: {
        "timeout": 0,
        "limit": 100,
        "allowed_updates": jsonEncode([
          "message",
          "edited_message",
          "channel_post",
          "edited_channel_post",
        ]),
        if (KVStoreService.sharedPreferences.getInt(_updateOffsetKey) != null)
          "offset": KVStoreService.sharedPreferences.getInt(_updateOffsetKey),
      },
      options: Options(responseType: ResponseType.json),
    );

    final body = response.data;
    if (body is! Map || body["ok"] != true || body["result"] is! List) {
      throw const TelegramMediaException("Telegram не вернул обновления");
    }

    var maxUpdateId = KVStoreService.sharedPreferences.getInt(_updateOffsetKey);
    var added = 0;
    var scanned = 0;

    for (final rawUpdate in body["result"] as List) {
      scanned++;
      if (rawUpdate is! Map) continue;
      final updateId = _asInt(rawUpdate["update_id"]);
      if (updateId != null && (maxUpdateId == null || updateId >= maxUpdateId)) {
        maxUpdateId = updateId + 1;
      }

      final message = _extractMessage(rawUpdate);
      if (message == null) continue;

      final chat = message["chat"];
      if (chat is! Map || !_matchesSource(chat, sourceFilters)) continue;

      final media = _extractAudioMedia(message);
      if (media == null) continue;

      final fileId = media.fileId;
      final filePath = await _getFilePath(token, fileId);
      if (filePath == null) continue;
      final thumbnailFileId = media.thumbnailFileId;
      final coverPath = thumbnailFileId == null
          ? null
          : await _getFilePath(token, thumbnailFileId);

	      final record = TelegramTrackRecord(
	        id: "telegram:${media.fileUniqueId ?? fileId}",
	        name: media.title,
	        artist: media.artist,
	        album: _string(chat["title"]) ?? "Telegram",
	        chatId: _string(chat["id"]) ?? "telegram",
	        chatTitle: _string(chat["title"]) ?? _string(chat["username"]) ?? "Telegram",
	        messageId: _asInt(message["message_id"]) ?? 0,
	        durationMs: media.durationMs,
	        fileUrl: "https://api.telegram.org/file/bot$token/$filePath",
	        coverUrl: coverPath == null
	            ? null
	            : "https://api.telegram.org/file/bot$token/$coverPath",
	        coverWidth: media.thumbnailWidth,
	        coverHeight: media.thumbnailHeight,
	        mimeType: media.mimeType,
	        fileName: media.fileName,
	        addedAt: DateTime.now(),
	      );

	      final previous = recordsById[record.id];
	      if (previous == null) added++;
	      recordsById[record.id] =
	          previous == null ? record : previous.mergeFresh(record);
	      if (added % 10 == 0 || added == 1) {
	        final records = recordsById.values.toList()
	          ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
	        await _writeStoredTracks(records);
	        ref.invalidate(telegramMediaTracksProvider);
	        ref.read(telegramMediaRevisionProvider.notifier).state++;
	      }

	      onProgress?.call(
	        TelegramSyncProgress(
	          running: true,
	          completed: false,
	          stage: "Синхронизация",
	          message: "Читаю обновления Telegram Bot API",
	          progress: scanned,
	          max: (body["result"] as List).length,
	          scanned: scanned,
	          found: recordsById.length,
	        ),
	      );
    }

    if (maxUpdateId != null) {
      await KVStoreService.sharedPreferences.setInt(
        _updateOffsetKey,
        maxUpdateId,
      );
    }

    final records = recordsById.values.toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    await _writeStoredTracks(records);
    ref.read(telegramMediaRevisionProvider.notifier).state++;

	    return TelegramSyncResult(
	      total: records.length,
	      added: added,
	      scanned: (body["result"] as List).length,
	      cached: 0,
	      failed: 0,
	    );
	  }

  Future<TelegramSyncResult> syncUserSessionHistory({
    TelegramSyncProgressHandler? onProgress,
  }) async {
    final auth = await ref.read(telegramAuthProvider.future);
    if (!auth.isUserSessionConnected) {
      throw const TelegramMediaException("Сначала подключи Telegram-сессию");
    }

    final sourceFilters = await loadSourceFilters();
    final recordsById = {
      for (final track in await _readStoredTracks()) track.id: track,
    };
    onProgress?.call(
      const TelegramSyncProgress(
        running: true,
        completed: false,
        stage: "Чтение",
        message: "Читаю историю Telegram",
      ),
    );
    final tracks = await _mtproto.fetchAudioFromSources(
      sourceFilters,
      onProgress: (source, scanned, found) {
        onProgress?.call(
          TelegramSyncProgress(
            running: true,
            completed: false,
            stage: "Чтение",
            message: "Читаю $source",
            scanned: scanned,
            found: found,
          ),
        );
      },
    );
    var added = 0;
    var cached = 0;
    var failed = 0;
    var indexed = 0;

    for (final track in tracks) {
      final id = "telegram:mtproto:${track.documentId}";
      final previous = recordsById[id];
      if (previous == null) added++;

      final record = _recordFromMtprotoTrack(
        track,
        id: id,
        coverUrl: previous?.coverUrl,
      );

      final merged = previous == null ? record : previous.mergeFresh(record);
      recordsById[id] = merged;
      indexed++;

      final records = recordsById.values.toList()
        ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
      await _writeStoredTracks(records);
      ref.invalidate(telegramMediaTracksProvider);
      ref.read(telegramMediaRevisionProvider.notifier).state++;

      onProgress?.call(
        TelegramSyncProgress(
          running: true,
          completed: false,
          stage: "Индексирование",
          message: "Добавляю треки в библиотеку",
          progress: indexed,
          max: tracks.length,
          scanned: indexed,
          found: recordsById.length,
        ),
      );
    }

    final records = recordsById.values.toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    await _writeStoredTracks(records);
    ref.read(telegramMediaRevisionProvider.notifier).state++;

    final mtprotoRecords = records
        .where((record) => record.fileUrl.startsWith("telegram-mtproto://"))
        .toList();
    var cacheIndex = 0;

    for (final record in mtprotoRecords) {
      cacheIndex++;
      final withCover = record.coverUrl == null
          ? await _refreshCoverFromRecord(record).catchError((_) => record)
          : record;
      final prepared = await _prepareMtprotoAudioCache(withCover);
      if (prepared.cacheReady == true) cached++;
      if (prepared.cacheReady == false) failed++;
      recordsById[prepared.id] = prepared;

      final updatedRecords = recordsById.values.toList()
        ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
      await _writeStoredTracks(updatedRecords);
      ref.invalidate(telegramMediaTracksProvider);
      ref.read(telegramMediaRevisionProvider.notifier).state++;

      onProgress?.call(
        TelegramSyncProgress(
          running: true,
          completed: false,
          stage: "Скачивание",
          message: "Кэширую Telegram-аудио",
          progress: cacheIndex,
          max: mtprotoRecords.length,
          scanned: tracks.length,
          found: recordsById.length,
          cached: cached,
          failed: failed,
        ),
      );
    }

    return TelegramSyncResult(
	      total: recordsById.length,
	      added: added,
	      scanned: tracks.length,
	      cached: cached,
	      failed: failed,
	    );
	  }

  Future<String> resolvePlayableUrl(String trackId) async {
    final record = (await _readStoredTracks()).firstWhereOrNull(
      (track) => track.id == trackId,
    );
    if (record == null) {
      throw const TelegramMediaException("Telegram-трек не найден");
    }

    if (!record.fileUrl.startsWith("telegram-mtproto://")) {
      return record.fileUrl;
    }

	    return _resolveMtprotoPlayableUrl(record);
	  }

	  Future<String> _resolveMtprotoPlayableUrl(TelegramTrackRecord record) async {
	    var current = record;
	    var refreshed = false;

	    while (true) {
	      final cacheFile = await _mtprotoAudioCacheFile(current);
	      if (await _isUsableAudioCache(cacheFile, current)) {
	        if (current.cacheReady != true) {
	          await _replaceStoredTrack(current.copyWithCache(cached: true));
	        }
	        return cacheFile.uri.toString();
	      }
	      if (await cacheFile.exists()) {
	        await cacheFile.delete().catchError((_) => cacheFile);
	      }

	      try {
	        final bytes = await _downloadMtprotoBytes(current);
	        if (bytes.isEmpty) {
	          throw const TelegramMediaException(
	            "Telegram вернул пустой файл для этого трека",
	          );
	        }
	        await cacheFile.create(recursive: true);
	        await cacheFile.writeAsBytes(bytes, flush: true);
	        await _replaceStoredTrack(current.copyWithCache(cached: true));
	        return cacheFile.uri.toString();
	      } catch (error, stackTrace) {
	        if (refreshed) {
	          await _replaceStoredTrack(
	            current.copyWithCache(cached: false, cacheError: error.toString()),
	          );
	          Error.throwWithStackTrace(error, stackTrace);
	        }

	        final updated = await _refreshMtprotoRecord(current);
	        if (updated == null) {
	          await _replaceStoredTrack(
	            current.copyWithCache(cached: false, cacheError: error.toString()),
	          );
	          Error.throwWithStackTrace(error, stackTrace);
	        }
	        current = updated;
	        refreshed = true;
	      }
	    }
	  }

	  Future<TelegramTrackRecord> _prepareMtprotoAudioCache(
	    TelegramTrackRecord record,
	  ) async {
	    if (!record.fileUrl.startsWith("telegram-mtproto://")) return record;

	    final cacheFile = await _mtprotoAudioCacheFile(record);
	    if (await _isUsableAudioCache(cacheFile, record)) {
	      return record.copyWithCache(cached: true);
	    }
	    if (await cacheFile.exists()) {
	      await cacheFile.delete().catchError((_) => cacheFile);
	    }

	    try {
	      final bytes = await _downloadMtprotoBytes(record);
	      if (bytes.isEmpty) {
	        throw const TelegramMediaException(
	          "Telegram вернул пустой файл для этого трека",
	        );
	      }
	      await cacheFile.create(recursive: true);
	      await cacheFile.writeAsBytes(bytes, flush: true);
	      return record.copyWithCache(cached: true);
	    } catch (error) {
	      return record.copyWithCache(
	        cached: false,
	        cacheError: error.toString(),
	      );
	    }
	  }

	  Future<bool> _isUsableAudioCache(
	    File cacheFile,
	    TelegramTrackRecord record,
	  ) async {
	    if (!await cacheFile.exists()) return false;

	    final length = await cacheFile.length();
	    if (length <= 0) return false;

	    final expectedSize = record.mtprotoSize;
	    final hasExpectedSize = expectedSize != null && expectedSize > 0;
	    if (hasExpectedSize && length < expectedSize) {
	      return false;
	    }
	    if (!hasExpectedSize &&
	        record.cacheReady != true &&
	        record.durationMs > 0 &&
	        length <= 512 * 1024) {
	      return false;
	    }

	    return true;
	  }

	  Future<List<int>> _downloadMtprotoBytes(TelegramTrackRecord record) async {
	    final documentId = record.mtprotoDocumentId;
	    final accessHash = record.mtprotoAccessHash;
	    final fileReference = record.mtprotoFileReference;
	    final size = record.mtprotoSize;
	    if (documentId == null ||
	        accessHash == null ||
	        fileReference == null) {
      throw const TelegramMediaException(
	        "У MTProto-трека нет данных документа",
	      );
	    }

	    return _mtproto.downloadDocument(
	      documentId: documentId,
	      accessHash: accessHash,
	      fileReferenceBase64: fileReference,
	      dcId: record.mtprotoDcId,
	      size: size ?? 0,
	    );
	  }

	  Future<TelegramTrackRecord?> _refreshMtprotoRecord(
	    TelegramTrackRecord record,
	  ) async {
	    if (record.chatId.trim().isEmpty || record.messageId <= 0) return null;

	    final freshTrack = await _mtproto.refreshTrackByMessage(
	      chatId: record.chatId,
	      messageId: record.messageId,
	    );
	    if (freshTrack == null) return null;

	    final coverUrl = await _cacheMtprotoCover(freshTrack).catchError(
	      (_) => record.coverUrl,
	    );
	    final freshRecord = _recordFromMtprotoTrack(
	      freshTrack,
	      id: record.id,
	      coverUrl: coverUrl ?? record.coverUrl,
	    );
	    final merged = record.mergeFresh(freshRecord);
	    await _replaceStoredTrack(merged);
	    return merged;
	  }

  Future<TelegramTrackRecord> _refreshCoverFromRecord(
    TelegramTrackRecord record,
  ) async {
    if (record.coverUrl != null) return record;
    if (record.chatId.trim().isEmpty || record.messageId <= 0) return record;

    final freshTrack = await _mtproto.refreshTrackByMessage(
      chatId: record.chatId,
      messageId: record.messageId,
    );
    if (freshTrack == null) return record;

    final coverUrl = await _cacheMtprotoCover(freshTrack);
    if (coverUrl == null) return record;

    return record.mergeFresh(
      _recordFromMtprotoTrack(
        freshTrack,
        id: record.id,
        coverUrl: coverUrl,
      ),
    );
  }

	  Future<void> _replaceStoredTrack(TelegramTrackRecord record) async {
	    final records = await _readStoredTracks();
	    final key = _dedupeKey(record);
	    final index = records.indexWhere(
	      (track) => track.id == record.id || _dedupeKey(track) == key,
	    );
	    if (index < 0) {
	      records.add(record);
	    } else {
	      records[index] = records[index].mergeFresh(record);
	    }

	    await _writeStoredTracks(records);
	    ref.invalidate(telegramMediaTracksProvider);
	    ref.read(telegramMediaRevisionProvider.notifier).state++;
	  }

	  TelegramTrackRecord _recordFromMtprotoTrack(
	    TelegramMtprotoTrack track, {
	    String? id,
	    String? coverUrl,
	  }) {
	    return TelegramTrackRecord(
	      id: id ?? "telegram:mtproto:${track.documentId}",
	      name: track.title,
	      artist: track.artist,
	      album: track.album,
	      chatId: track.chatId,
	      chatTitle: track.chatTitle,
	      messageId: track.messageId,
	      durationMs: track.durationMs,
	      fileUrl: "telegram-mtproto://document/${track.documentId}",
	      coverUrl: coverUrl,
	      mimeType: track.mimeType,
	      fileName: track.fileName,
	      mtprotoDocumentId: track.documentId,
	      mtprotoAccessHash: track.accessHash,
	      mtprotoFileReference: track.fileReferenceBase64,
	      mtprotoDcId: track.dcId,
	      mtprotoSize: track.size,
	      mtprotoThumbSize: track.thumbSize,
	      addedAt: track.addedAt,
	    );
	  }

  Future<String?> _cacheMtprotoCover(TelegramMtprotoTrack track) async {
    final thumbSize = track.thumbSize;
    if (thumbSize == null || thumbSize.isEmpty) return null;

    final dir = await _telegramCacheDir("covers");
    final file = File(p.join(dir.path, "${track.documentId}-$thumbSize.jpg"));
    if (await file.exists() && await file.length() > 0) return file.path;

	    final bytes = await _mtproto.downloadDocument(
	      documentId: track.documentId,
	      accessHash: track.accessHash,
	      fileReferenceBase64: track.fileReferenceBase64,
	      dcId: track.dcId,
	      size: 0,
	      thumbSize: thumbSize,
	    );
    if (bytes.isEmpty) return null;
    await file.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<File> _mtprotoAudioCacheFile(TelegramTrackRecord record) async {
    final dir = await _telegramCacheDir("audio");
	    final extension = _extensionFromRecord(record);
	    final basename = _sanitizeFilePart(
	      "${record.mtprotoDocumentId ?? record.id}.$extension",
	    );
	    return File(p.join(dir.path, basename));
	  }

  Future<Directory> _telegramCacheDir(String child) async {
    final base = await getApplicationCacheDirectory();
    final dir = Directory(p.join(base.path, "telegram", child));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Map<String, TelegramAlbumOverride> _readAlbumOverrides() {
    final raw = KVStoreService.sharedPreferences.getString(_albumOverridesKey);
    if (raw == null || raw.isEmpty) return {};

    final parsed = jsonDecode(raw);
    if (parsed is! Map) return {};

    return parsed.map(
      (key, value) {
        if (value is! Map) {
          return MapEntry(key.toString(), const TelegramAlbumOverride());
        }
        return MapEntry(
          key.toString(),
          TelegramAlbumOverride.fromJson(value.cast<String, dynamic>()),
        );
      },
    )..removeWhere((_, value) => value.isEmpty);
  }

  SpotubeFullTrackObject _applyAlbumOverride(
    SpotubeFullTrackObject track,
    Map<String, TelegramAlbumOverride> overrides,
  ) {
    final override = overrides[track.album.id];
    if (override == null) return track;
    return track.copyWith(
      album: _applyAlbumOverrideToAlbum(track.album, override),
    );
  }

  SpotubeSimpleAlbumObject _applyAlbumOverrideToAlbum(
    SpotubeSimpleAlbumObject album,
    TelegramAlbumOverride override,
  ) {
    return album.copyWith(
      name: override.name ?? album.name,
      images: override.coverUrl == null
          ? album.images
          : [
              SpotubeImageObject(
                url: override.coverUrl!,
                width: 600,
                height: 600,
              ),
            ],
    );
  }

  Future<List<TelegramTrackRecord>> _readStoredTracks() async {
    final raw = KVStoreService.sharedPreferences.getString(_tracksKey);
    if (raw == null || raw.isEmpty) return [];

    final parsed = jsonDecode(raw);
    if (parsed is! List) return [];

	    return _dedupeStoredTracks(parsed
	        .whereType<Map>()
	        .map((item) => TelegramTrackRecord.fromJson(item.cast<String, dynamic>()))
	        .toList());
	  }

	  Future<void> _writeStoredTracks(List<TelegramTrackRecord> tracks) async {
	    final deduped = _dedupeStoredTracks(tracks)
	      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
	    await KVStoreService.sharedPreferences.setString(
	      _tracksKey,
	      jsonEncode(deduped.map((track) => track.toJson()).toList()),
	    );
	  }

	  List<TelegramTrackRecord> _dedupeStoredTracks(
	    List<TelegramTrackRecord> tracks,
	  ) {
	    final byKey = <String, TelegramTrackRecord>{};
	    for (final track in tracks) {
	      final key = _dedupeKey(track);
	      final previous = byKey[key];
	      byKey[key] = previous == null ? track : previous.mergeFresh(track);
	    }
	    return byKey.values.toList();
	  }

	  String _dedupeKey(TelegramTrackRecord track) {
	    final documentId = track.mtprotoDocumentId;
	    if (documentId != null) return "mtproto:$documentId";

	    if (track.chatId.trim().isNotEmpty && track.messageId > 0) {
	      return "message:${track.chatId}:${track.messageId}";
	    }

	    return track.id;
	  }

  Future<String?> _getFilePath(String token, String fileId) async {
    final response = await globalDio.get(
      "https://api.telegram.org/bot$token/getFile",
      queryParameters: {"file_id": fileId},
      options: Options(responseType: ResponseType.json),
    );

    final body = response.data;
    if (body is! Map || body["ok"] != true || body["result"] is! Map) {
      return null;
    }
    return _string((body["result"] as Map)["file_path"]);
  }

  Map? _extractMessage(Map update) {
    for (final key in const [
      "message",
      "edited_message",
      "channel_post",
      "edited_channel_post",
    ]) {
      final value = update[key];
      if (value is Map) return value;
    }
    return null;
  }

  bool _matchesSource(Map chat, List<String> filters) {
    if (filters.isEmpty) return true;

    final candidates = {
      _string(chat["id"]),
      _string(chat["title"]),
      _string(chat["username"]),
      if (_string(chat["username"]) != null) "@${_string(chat["username"])}",
    }.whereType<String>().map((value) => value.toLowerCase()).toSet();

    return filters
        .map((value) => value.toLowerCase())
        .any((filter) => candidates.contains(filter));
  }

  _TelegramMedia? _extractAudioMedia(Map message) {
    final audio = message["audio"];
    if (audio is Map) {
      return _TelegramMedia.fromAudio(audio.cast<String, dynamic>());
    }

    final document = message["document"];
    if (document is Map) {
      final parsed = _TelegramMedia.fromDocument(document.cast<String, dynamic>());
      if (parsed != null) return parsed;
    }

    final video = message["video"];
    if (video is Map) {
      return _TelegramMedia.fromVideo(video.cast<String, dynamic>());
    }

    return null;
  }
}

class TelegramTrackRecord {
  final String id;
  final String name;
  final String artist;
  final String album;
  final String chatId;
  final String chatTitle;
  final int messageId;
  final int durationMs;
  final String fileUrl;
  final String? coverUrl;
  final int? coverWidth;
  final int? coverHeight;
  final String? mimeType;
  final String? fileName;
  final String? manualName;
  final String? manualArtist;
  final String? manualAlbum;
  final int? mtprotoDocumentId;
  final int? mtprotoAccessHash;
  final String? mtprotoFileReference;
	  final int? mtprotoDcId;
	  final int? mtprotoSize;
	  final String? mtprotoThumbSize;
	  final bool? cacheReady;
	  final String? cacheError;
	  final DateTime? cacheCheckedAt;
	  final DateTime addedAt;

  const TelegramTrackRecord({
    required this.id,
    required this.name,
    required this.artist,
    required this.album,
    required this.chatId,
    required this.chatTitle,
    required this.messageId,
    required this.durationMs,
    required this.fileUrl,
    this.coverUrl,
    this.coverWidth,
    this.coverHeight,
    this.mimeType,
    this.fileName,
    this.manualName,
    this.manualArtist,
    this.manualAlbum,
    this.mtprotoDocumentId,
    this.mtprotoAccessHash,
    this.mtprotoFileReference,
	    this.mtprotoDcId,
	    this.mtprotoSize,
	    this.mtprotoThumbSize,
	    this.cacheReady,
	    this.cacheError,
	    this.cacheCheckedAt,
	    required this.addedAt,
	  });

  factory TelegramTrackRecord.fromJson(Map<String, dynamic> json) {
    return TelegramTrackRecord(
      id: json["id"].toString(),
      name: json["name"].toString(),
      artist: json["artist"].toString(),
      album: json["album"].toString(),
      chatId: json["chat_id"].toString(),
      chatTitle: json["chat_title"].toString(),
      messageId: _asInt(json["message_id"]) ?? 0,
      durationMs: _asInt(json["duration_ms"]) ?? 0,
      fileUrl: json["file_url"].toString(),
      coverUrl: _string(json["cover_url"]),
      coverWidth: _asInt(json["cover_width"]),
      coverHeight: _asInt(json["cover_height"]),
      mimeType: _string(json["mime_type"]),
      fileName: _string(json["file_name"]),
      manualName: _string(json["manual_name"]),
      manualArtist: _string(json["manual_artist"]),
      manualAlbum: _string(json["manual_album"]),
      mtprotoDocumentId: _asInt(json["mtproto_document_id"]),
      mtprotoAccessHash: _asInt(json["mtproto_access_hash"]),
      mtprotoFileReference: _string(json["mtproto_file_reference"]),
	      mtprotoDcId: _asInt(json["mtproto_dc_id"]),
	      mtprotoSize: _asInt(json["mtproto_size"]),
	      mtprotoThumbSize: _string(json["mtproto_thumb_size"]),
	      cacheReady: _asBool(json["cache_ready"]),
	      cacheError: _string(json["cache_error"]),
	      cacheCheckedAt:
	          DateTime.tryParse(json["cache_checked_at"]?.toString() ?? ""),
	      addedAt: DateTime.tryParse(json["added_at"]?.toString() ?? "") ??
	          DateTime.fromMillisecondsSinceEpoch(0),
	    );
  }

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "name": name,
      "artist": artist,
      "album": album,
      "chat_id": chatId,
      "chat_title": chatTitle,
      "message_id": messageId,
      "duration_ms": durationMs,
      "file_url": fileUrl,
      "cover_url": coverUrl,
      "cover_width": coverWidth,
      "cover_height": coverHeight,
      "mime_type": mimeType,
      "file_name": fileName,
      "manual_name": manualName,
      "manual_artist": manualArtist,
      "manual_album": manualAlbum,
      "mtproto_document_id": mtprotoDocumentId,
      "mtproto_access_hash": mtprotoAccessHash,
      "mtproto_file_reference": mtprotoFileReference,
	      "mtproto_dc_id": mtprotoDcId,
	      "mtproto_size": mtprotoSize,
	      "mtproto_thumb_size": mtprotoThumbSize,
	      "cache_ready": cacheReady,
	      "cache_error": cacheError,
	      "cache_checked_at": cacheCheckedAt?.toIso8601String(),
	      "added_at": addedAt.toIso8601String(),
	    };
	  }

  TelegramTrackRecord copyWith({
    String? manualName,
    String? manualArtist,
    String? manualAlbum,
    String? coverUrl,
  }) {
    return TelegramTrackRecord(
      id: id,
      name: name,
      artist: artist,
      album: album,
      chatId: chatId,
      chatTitle: chatTitle,
      messageId: messageId,
      durationMs: durationMs,
      fileUrl: fileUrl,
      coverUrl: coverUrl ?? this.coverUrl,
      coverWidth: coverWidth,
      coverHeight: coverHeight,
      mimeType: mimeType,
      fileName: fileName,
      manualName: manualName,
      manualArtist: manualArtist,
      manualAlbum: manualAlbum,
      mtprotoDocumentId: mtprotoDocumentId,
      mtprotoAccessHash: mtprotoAccessHash,
      mtprotoFileReference: mtprotoFileReference,
      mtprotoDcId: mtprotoDcId,
      mtprotoSize: mtprotoSize,
      mtprotoThumbSize: mtprotoThumbSize,
      cacheReady: cacheReady,
      cacheError: cacheError,
      cacheCheckedAt: cacheCheckedAt,
      addedAt: addedAt,
    );
  }

  TelegramTrackRecord copyWithCache({
    required bool cached,
    String? cacheError,
  }) {
    return TelegramTrackRecord(
      id: id,
      name: name,
      artist: artist,
      album: album,
      chatId: chatId,
      chatTitle: chatTitle,
      messageId: messageId,
      durationMs: durationMs,
      fileUrl: fileUrl,
      coverUrl: coverUrl,
      coverWidth: coverWidth,
      coverHeight: coverHeight,
      mimeType: mimeType,
      fileName: fileName,
      manualName: manualName,
      manualArtist: manualArtist,
      manualAlbum: manualAlbum,
      mtprotoDocumentId: mtprotoDocumentId,
      mtprotoAccessHash: mtprotoAccessHash,
      mtprotoFileReference: mtprotoFileReference,
      mtprotoDcId: mtprotoDcId,
      mtprotoSize: mtprotoSize,
      mtprotoThumbSize: mtprotoThumbSize,
      cacheReady: cached,
      cacheError: cached ? null : cacheError,
      cacheCheckedAt: DateTime.now(),
      addedAt: addedAt,
    );
  }

	  TelegramTrackRecord mergeFresh(TelegramTrackRecord fresh) {
	    return TelegramTrackRecord(
	      id: id,
	      name: fresh.name,
	      artist: fresh.artist,
	      album: fresh.album,
	      chatId: fresh.chatId,
	      chatTitle: fresh.chatTitle,
	      messageId: fresh.messageId,
	      durationMs: fresh.durationMs,
	      fileUrl: fresh.fileUrl,
	      coverUrl: coverUrl ?? fresh.coverUrl,
	      coverWidth: fresh.coverWidth ?? coverWidth,
	      coverHeight: fresh.coverHeight ?? coverHeight,
	      mimeType: fresh.mimeType ?? mimeType,
	      fileName: fresh.fileName ?? fileName,
	      manualName: manualName ?? fresh.manualName,
	      manualArtist: manualArtist ?? fresh.manualArtist,
	      manualAlbum: manualAlbum ?? fresh.manualAlbum,
	      mtprotoDocumentId: fresh.mtprotoDocumentId ?? mtprotoDocumentId,
	      mtprotoAccessHash: fresh.mtprotoAccessHash ?? mtprotoAccessHash,
	      mtprotoFileReference:
	          fresh.mtprotoFileReference ?? mtprotoFileReference,
	      mtprotoDcId: fresh.mtprotoDcId ?? mtprotoDcId,
	      mtprotoSize: fresh.mtprotoSize ?? mtprotoSize,
	      mtprotoThumbSize: fresh.mtprotoThumbSize ?? mtprotoThumbSize,
	      cacheReady: fresh.cacheReady ?? cacheReady,
	      cacheError: fresh.cacheError ?? cacheError,
	      cacheCheckedAt: fresh.cacheCheckedAt ?? cacheCheckedAt,
	      addedAt: fresh.addedAt,
	    );
	  }

	  SpotubeFullTrackObject toMetadata() {
    final parsed = _isGenericArtist(artist) ? _splitArtistTitle(name) : null;
    final effectiveName = manualName ?? parsed?.title ?? name;
    final effectiveArtist = manualArtist ?? parsed?.artist ?? artist;
    final effectiveAlbum = manualAlbum ?? album;
    final images = coverUrl == null
        ? <SpotubeImageObject>[]
        : [
            SpotubeImageObject(
              url: coverUrl!,
              width: coverWidth,
              height: coverHeight,
            ),
          ];
    final artistObject = SpotubeSimpleArtistObject(
      id: "telegram:$chatId:$effectiveArtist",
      name: effectiveArtist,
      externalUri: "telegram:$chatId",
    );

    return SpotubeFullTrackObject(
      id: id,
      name: effectiveName,
      externalUri: fileUrl,
      artists: [artistObject],
      album: SpotubeSimpleAlbumObject(
        id: "telegram:$chatId",
        name: effectiveAlbum,
        externalUri: "telegram:$chatId",
        artists: [artistObject],
        images: images,
        albumType: SpotubeAlbumType.album,
        releaseDate: addedAt.year.toString(),
      ),
      durationMs: durationMs,
      isrc: "",
      explicit: false,
    );
  }
}

class TelegramSyncResult {
  final int total;
  final int added;
  final int scanned;
  final int cached;
  final int failed;

  const TelegramSyncResult({
    required this.total,
    required this.added,
    required this.scanned,
    required this.cached,
    required this.failed,
  });
}

class TelegramMediaException implements Exception {
  final String message;

  const TelegramMediaException(this.message);

  @override
  String toString() => message;
}

class TelegramAlbumOverride {
  final String? name;
  final String? coverUrl;

  const TelegramAlbumOverride({
    this.name,
    this.coverUrl,
  });

  bool get isEmpty =>
      (name == null || name!.trim().isEmpty) &&
      (coverUrl == null || coverUrl!.trim().isEmpty);

  factory TelegramAlbumOverride.fromJson(Map<String, dynamic> json) {
    return TelegramAlbumOverride(
      name: _string(json["name"]),
      coverUrl: _string(json["cover_url"]),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "name": name,
      "cover_url": coverUrl,
    };
  }
}

class _TelegramMedia {
  final String fileId;
  final String? fileUniqueId;
  final String title;
  final String artist;
  final int durationMs;
  final String? mimeType;
  final String? fileName;
  final String? thumbnailFileId;
  final int? thumbnailWidth;
  final int? thumbnailHeight;

  const _TelegramMedia({
    required this.fileId,
    this.fileUniqueId,
    required this.title,
    required this.artist,
    required this.durationMs,
    this.mimeType,
    this.fileName,
    this.thumbnailFileId,
    this.thumbnailWidth,
    this.thumbnailHeight,
  });

  factory _TelegramMedia.fromAudio(Map<String, dynamic> audio) {
    final fileName = _string(audio["file_name"]);
    final basename = _basename(fileName);
    final rawTitle = _string(audio["title"]) ?? basename ?? "Telegram audio";
    final performer = _string(audio["performer"]);
    final parsedTitle = _splitArtistTitle(rawTitle);
    final parsedBasename =
        basename == rawTitle ? null : _splitArtistTitle(basename);
    final parsed = parsedBasename ?? parsedTitle;
    final title =
        performer == null && parsedTitle != null ? parsedTitle.title : rawTitle;
    final thumbnail = _thumbnail(audio);

    return _TelegramMedia(
      fileId: audio["file_id"].toString(),
      fileUniqueId: _string(audio["file_unique_id"]),
      title: title,
      artist: performer ?? parsed?.artist ?? "Telegram",
      durationMs: (_asInt(audio["duration"]) ?? 0) * 1000,
      mimeType: _string(audio["mime_type"]),
      fileName: fileName,
      thumbnailFileId: thumbnail?.fileId,
      thumbnailWidth: thumbnail?.width,
      thumbnailHeight: thumbnail?.height,
    );
  }

  static _TelegramMedia? fromDocument(Map<String, dynamic> document) {
    final mimeType = _string(document["mime_type"]) ?? "";
    final fileName = _string(document["file_name"]) ?? "";
    final lowerName = fileName.toLowerCase();
    final isAudio = mimeType.startsWith("audio/") ||
        lowerName.endsWith(".mp3") ||
        lowerName.endsWith(".m4a") ||
        lowerName.endsWith(".flac") ||
        lowerName.endsWith(".ogg") ||
        lowerName.endsWith(".opus") ||
        lowerName.endsWith(".wav");

    if (!isAudio || document["file_id"] == null) return null;

    final title = _basename(fileName) ?? "Telegram audio";
    final parsed = _splitArtistTitle(title);
    final thumbnail = _thumbnail(document);

    return _TelegramMedia(
      fileId: document["file_id"].toString(),
      fileUniqueId: _string(document["file_unique_id"]),
      title: parsed?.title ?? title,
      artist: parsed?.artist ?? "Telegram",
      durationMs: 0,
      mimeType: mimeType.isEmpty ? null : mimeType,
      fileName: fileName,
      thumbnailFileId: thumbnail?.fileId,
      thumbnailWidth: thumbnail?.width,
      thumbnailHeight: thumbnail?.height,
    );
  }

  factory _TelegramMedia.fromVideo(Map<String, dynamic> video) {
    final title = _basename(_string(video["file_name"])) ?? "Telegram video";
    final parsed = _splitArtistTitle(title);
    final thumbnail = _thumbnail(video);

    return _TelegramMedia(
      fileId: video["file_id"].toString(),
      fileUniqueId: _string(video["file_unique_id"]),
      title: parsed?.title ?? title,
      artist: parsed?.artist ?? "Telegram",
      durationMs: (_asInt(video["duration"]) ?? 0) * 1000,
      mimeType: _string(video["mime_type"]),
      fileName: _string(video["file_name"]),
      thumbnailFileId: thumbnail?.fileId,
      thumbnailWidth: thumbnail?.width,
      thumbnailHeight: thumbnail?.height,
    );
  }
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? "");
}

bool? _asBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final string = value?.toString().trim().toLowerCase();
  if (string == "true" || string == "1") return true;
  if (string == "false" || string == "0") return false;
  return null;
}

String? _string(Object? value) {
  final string = value?.toString().trim();
  if (string == null || string.isEmpty) return null;
  return string;
}

String? _basename(String? fileName) {
  if (fileName == null || fileName.trim().isEmpty) return null;
  final cleaned = fileName.split("/").last;
  final dot = cleaned.lastIndexOf(".");
  return dot <= 0 ? cleaned : cleaned.substring(0, dot);
}

String _extensionFromRecord(TelegramTrackRecord record) {
  final fileName = record.fileName?.toLowerCase();
  final dot = fileName?.lastIndexOf(".") ?? -1;
  if (fileName != null && dot > 0 && dot < fileName.length - 1) {
    return fileName.substring(dot + 1).replaceAll(RegExp(r"[^a-z0-9]"), "");
  }

  final mimeType = record.mimeType?.toLowerCase() ?? "";
  if (mimeType.contains("mpeg")) return "mp3";
  if (mimeType.contains("mp4")) return "m4a";
  if (mimeType.contains("flac")) return "flac";
  if (mimeType.contains("ogg")) return "ogg";
  if (mimeType.contains("opus")) return "opus";
  if (mimeType.contains("wav")) return "wav";
  return "m4a";
}

String _sanitizeFilePart(String value) {
  return value
      .replaceAll(RegExp(r'[\\/:*?"<>|]+'), "_")
      .replaceAll(RegExp(r"\s+"), " ")
      .trim();
}

_TelegramThumbnail? _thumbnail(Map<String, dynamic> data) {
  final raw = data["thumbnail"] ?? data["thumb"];
  if (raw is! Map) return null;
  final fileId = _string(raw["file_id"]);
  if (fileId == null) return null;

  return _TelegramThumbnail(
    fileId: fileId,
    width: _asInt(raw["width"]),
    height: _asInt(raw["height"]),
  );
}

class _TelegramThumbnail {
  final String fileId;
  final int? width;
  final int? height;

  const _TelegramThumbnail({
    required this.fileId,
    this.width,
    this.height,
  });
}

bool _isGenericArtist(String value) {
  return value.trim().toLowerCase() == "telegram";
}

_ParsedTrackName? _splitArtistTitle(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) return null;

  final match = RegExp(r"^(.+?)\s+(?:-|–|—|:)\s+(.+)$").firstMatch(text);
  if (match == null) return null;

  final artist = match.group(1)?.trim();
  final title = match.group(2)?.trim();
  if (artist == null || title == null || artist.isEmpty || title.isEmpty) {
    return null;
  }

  return _ParsedTrackName(artist: artist, title: title);
}

class _ParsedTrackName {
  final String artist;
  final String title;

  const _ParsedTrackName({
    required this.artist,
    required this.title,
  });
}
