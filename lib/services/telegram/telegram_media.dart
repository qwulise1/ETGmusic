import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:etgmusic/models/metadata/metadata.dart';
import 'package:etgmusic/provider/telegram/telegram_auth.dart';
import 'package:etgmusic/services/dio/dio.dart';
import 'package:etgmusic/services/kv_store/kv_store.dart';

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

class TelegramMediaService {
  static const _tracksKey = "telegram_media_tracks";
  static const _sourcesKey = "telegram_media_sources";
  static const _updateOffsetKey = "telegram_media_update_offset";

  final Ref ref;

  TelegramMediaService(this.ref);

  Future<List<String>> loadSourceFilters() async {
    final raw = KVStoreService.sharedPreferences.getStringList(_sourcesKey);
    return raw?.where((value) => value.trim().isNotEmpty).toList() ?? const [];
  }

  Future<void> setSourceFiltersFromText(String raw) async {
    final values = raw
        .split(RegExp(r"[\n,;]+"))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();

    await KVStoreService.sharedPreferences.setStringList(_sourcesKey, values);
    ref.read(telegramMediaRevisionProvider.notifier).state++;
  }

  Future<List<SpotubeFullTrackObject>> loadTracks() async {
    return _readStoredTracks().map((track) => track.toMetadata()).toList();
  }

  Future<SpotubeFullTrackObject?> findTrack(String id) async {
    final records = await _readStoredTracks();
    return records
        .where((track) => track.id == id)
        .map((track) => track.toMetadata())
        .firstOrNull;
  }

  Future<TelegramSyncResult> syncBotUpdates() async {
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

    for (final rawUpdate in body["result"] as List) {
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
        mimeType: media.mimeType,
        fileName: media.fileName,
        addedAt: DateTime.now(),
      );

      if (!recordsById.containsKey(record.id)) added++;
      recordsById[record.id] = record;
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
    );
  }

  Future<List<TelegramTrackRecord>> _readStoredTracks() async {
    final raw = KVStoreService.sharedPreferences.getString(_tracksKey);
    if (raw == null || raw.isEmpty) return [];

    final parsed = jsonDecode(raw);
    if (parsed is! List) return [];

    return parsed
        .whereType<Map>()
        .map((item) => TelegramTrackRecord.fromJson(item.cast<String, dynamic>()))
        .toList();
  }

  Future<void> _writeStoredTracks(List<TelegramTrackRecord> tracks) async {
    await KVStoreService.sharedPreferences.setString(
      _tracksKey,
      jsonEncode(tracks.map((track) => track.toJson()).toList()),
    );
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
  final String? mimeType;
  final String? fileName;
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
    this.mimeType,
    this.fileName,
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
      mimeType: _string(json["mime_type"]),
      fileName: _string(json["file_name"]),
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
      "mime_type": mimeType,
      "file_name": fileName,
      "added_at": addedAt.toIso8601String(),
    };
  }

  SpotubeFullTrackObject toMetadata() {
    final artistObject = SpotubeSimpleArtistObject(
      id: "telegram:$chatId:$artist",
      name: artist,
      externalUri: "telegram:$chatId",
    );

    return SpotubeFullTrackObject(
      id: id,
      name: name,
      externalUri: fileUrl,
      artists: [artistObject],
      album: SpotubeSimpleAlbumObject(
        id: "telegram:$chatId",
        name: album,
        externalUri: "telegram:$chatId",
        artists: [artistObject],
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

  const TelegramSyncResult({
    required this.total,
    required this.added,
    required this.scanned,
  });
}

class TelegramMediaException implements Exception {
  final String message;

  const TelegramMediaException(this.message);

  @override
  String toString() => message;
}

class _TelegramMedia {
  final String fileId;
  final String? fileUniqueId;
  final String title;
  final String artist;
  final int durationMs;
  final String? mimeType;
  final String? fileName;

  const _TelegramMedia({
    required this.fileId,
    this.fileUniqueId,
    required this.title,
    required this.artist,
    required this.durationMs,
    this.mimeType,
    this.fileName,
  });

  factory _TelegramMedia.fromAudio(Map<String, dynamic> audio) {
    return _TelegramMedia(
      fileId: audio["file_id"].toString(),
      fileUniqueId: _string(audio["file_unique_id"]),
      title: _string(audio["title"]) ??
          _basename(_string(audio["file_name"])) ??
          "Telegram audio",
      artist: _string(audio["performer"]) ?? "Telegram",
      durationMs: (_asInt(audio["duration"]) ?? 0) * 1000,
      mimeType: _string(audio["mime_type"]),
      fileName: _string(audio["file_name"]),
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

    return _TelegramMedia(
      fileId: document["file_id"].toString(),
      fileUniqueId: _string(document["file_unique_id"]),
      title: _basename(fileName) ?? "Telegram audio",
      artist: "Telegram",
      durationMs: 0,
      mimeType: mimeType.isEmpty ? null : mimeType,
      fileName: fileName,
    );
  }

  factory _TelegramMedia.fromVideo(Map<String, dynamic> video) {
    return _TelegramMedia(
      fileId: video["file_id"].toString(),
      fileUniqueId: _string(video["file_unique_id"]),
      title: _basename(_string(video["file_name"])) ?? "Telegram video",
      artist: "Telegram",
      durationMs: (_asInt(video["duration"]) ?? 0) * 1000,
      mimeType: _string(video["mime_type"]),
      fileName: _string(video["file_name"]),
    );
  }
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? "");
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
