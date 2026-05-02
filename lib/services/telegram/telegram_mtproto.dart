import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:t/t.dart' as t;
import 'package:tg/tg.dart' as tg;
import 'package:etgmusic/services/kv_store/encrypted_kv_store.dart';
import 'package:etgmusic/services/kv_store/kv_store.dart';
import 'package:etgmusic/services/logger/logger.dart';

class TelegramMtprotoService {
  static const appName = "ETGmusic";
  static const _socketTimeout = Duration(seconds: 15);
  static const _authTimeout = Duration(seconds: 40);
  static const _requestTimeout = Duration(seconds: 25);
  static const _apiIdKey = "telegram_mtproto_api_id";
  static const _apiHashKey = "telegram_mtproto_api_hash";
  static const _phoneKey = "telegram_mtproto_phone";
  static const _phoneCodeHashKey = "telegram_mtproto_code_hash";
  static const _authKeyKey = "telegram_mtproto_auth_key";
  static const _dcIdKey = "telegram_mtproto_dc_id";
  static const _dcIpKey = "telegram_mtproto_dc_ip";
  static const _dcPortKey = "telegram_mtproto_dc_port";

  tg.Client? _client;
  Socket? _socket;
  StreamSubscription<t.UpdatesBase>? _updatesSubscription;
  t.DcOption _dc = const t.DcOption(
    ipv6: false,
    mediaOnly: false,
    tcpoOnly: false,
    cdn: false,
    static: false,
    thisPortOnly: false,
    id: 1,
    ipAddress: "149.154.167.50",
    port: 443,
  );

  Future<TelegramSessionSendCodeResult> sendCode({
    required int apiId,
    required String apiHash,
    required String phoneNumber,
    bool retryMigration = true,
  }) async {
    final phone = phoneNumber.trim();
    final hash = apiHash.trim();
    if (apiId <= 0) {
      throw const TelegramMtprotoException("Укажи Telegram API ID");
    }
    if (hash.isEmpty) {
      throw const TelegramMtprotoException("Укажи Telegram API hash");
    }
    if (phone.isEmpty) {
      throw const TelegramMtprotoException("Укажи номер телефона");
    }

    final client = await _connect(apiId: apiId);
    final response = await _telegramCall(
      client.auth.sendCode(
        apiId: apiId,
        apiHash: hash,
        phoneNumber: phone,
        settings: const t.CodeSettings(
          allowFlashcall: false,
          currentNumber: true,
          allowAppHash: false,
          allowMissedCall: false,
          allowFirebase: false,
          unknownNumber: false,
        ),
      ),
      "Telegram не ответил на запрос кода. Проверь сеть/API ID и попробуй еще раз.",
    );

    final error = response.error;
    if (error != null) {
      if (retryMigration && await _handleMigration(error, apiId: apiId)) {
        return sendCode(
          apiId: apiId,
          apiHash: apiHash,
          phoneNumber: phoneNumber,
          retryMigration: false,
        );
      }
      throw TelegramMtprotoException(_humanError(error.errorMessage));
    }

    final sentCode = response.result;
    if (sentCode is! t.AuthSentCode) {
      throw const TelegramMtprotoException("Telegram не вернул phone_code_hash");
    }

    await _writeSecure(_apiHashKey, hash);
    await KVStoreService.sharedPreferences.setInt(_apiIdKey, apiId);
    await KVStoreService.sharedPreferences.setString(_phoneKey, phone);
    await KVStoreService.sharedPreferences.setString(
      _phoneCodeHashKey,
      sentCode.phoneCodeHash,
    );

    return TelegramSessionSendCodeResult(
      phoneNumber: phone,
      phoneCodeHash: sentCode.phoneCodeHash,
    );
  }

  Future<TelegramSessionSignInResult> signInWithCode(String code) async {
    final apiId = KVStoreService.sharedPreferences.getInt(_apiIdKey);
    final phone = KVStoreService.sharedPreferences.getString(_phoneKey);
    final phoneCodeHash =
        KVStoreService.sharedPreferences.getString(_phoneCodeHashKey);

    if (apiId == null || phone == null || phoneCodeHash == null) {
      throw const TelegramMtprotoException("Сначала запроси код Telegram");
    }

    final client = await _connect(apiId: apiId);
    final response = await _telegramCall(
      client.auth.signIn(
        phoneNumber: phone,
        phoneCodeHash: phoneCodeHash,
        phoneCode: code.trim(),
      ),
      "Telegram не ответил на подтверждение кода. Попробуй еще раз.",
    );

    final error = response.error;
    if (error != null) {
      if (error.errorMessage == "SESSION_PASSWORD_NEEDED") {
        final password = await _telegramCall(
          client.account.getPassword(),
          "Telegram не вернул параметры 2FA. Попробуй еще раз.",
        );
        final passwordState = password.result;
        if (passwordState is! t.AccountPassword) {
          throw const TelegramMtprotoException(
            "Telegram запросил 2FA, но не вернул параметры пароля",
          );
        }
        return TelegramSessionSignInResult.passwordRequired(
          hint: passwordState.hint,
        );
      }
      throw TelegramMtprotoException(_humanError(error.errorMessage));
    }

    await _persistAuthKey(client.authorizationKey);
    return const TelegramSessionSignInResult.connected();
  }

  Future<void> checkPassword(String rawPassword) async {
    final password = rawPassword.trim();
    if (password.isEmpty) {
      throw const TelegramMtprotoException("Укажи пароль 2FA");
    }

    final apiId = KVStoreService.sharedPreferences.getInt(_apiIdKey);
    if (apiId == null) {
      throw const TelegramMtprotoException("Сначала запроси код Telegram");
    }

    final client = await _connect(apiId: apiId);
    final accountPasswordResponse = await _telegramCall(
      client.account.getPassword(),
      "Telegram не вернул параметры 2FA. Попробуй еще раз.",
    );
    final accountPassword = accountPasswordResponse.result;
    if (accountPassword is! t.AccountPassword) {
      throw const TelegramMtprotoException("Telegram не вернул параметры 2FA");
    }

    final inputPassword = await tg.check2FA(accountPassword, password);
    final response = await _telegramCall(
      client.auth.checkPassword(password: inputPassword),
      "Telegram не ответил на пароль 2FA. Попробуй еще раз.",
    );
    final error = response.error;
    if (error != null) {
      throw TelegramMtprotoException(_humanError(error.errorMessage));
    }

    await _persistAuthKey(client.authorizationKey);
  }

	  Future<List<TelegramMtprotoTrack>> fetchAudioFromSources(
	    List<String> sourceFilters, {
	    int pageSize = 100,
	    int maxMessagesPerSource = 10000,
	    void Function(String sourceTitle, int scannedMessages, int foundTracks)?
	        onProgress,
  }) async {
    final apiId = _readApiId();
    final client = await _connect(apiId: apiId);
    final peers = await _resolvePeers(client, sourceFilters);
    final tracks = <TelegramMtprotoTrack>[];
    final effectivePageSize = pageSize <= 0
        ? 100
        : pageSize > 100
            ? 100
            : pageSize;
    final effectiveMaxMessages =
        maxMessagesPerSource <= 0 ? 10000 : maxMessagesPerSource;

    for (final peer in peers) {
      var offsetId = 0;
      var scannedMessages = 0;

      while (scannedMessages < effectiveMaxMessages) {
        final remainingMessages = effectiveMaxMessages - scannedMessages;
        final requestLimit = remainingMessages < effectivePageSize
            ? remainingMessages
            : effectivePageSize;
        final response = await _telegramCall(
          client.messages.getHistory(
            peer: peer.peer,
            offsetId: offsetId,
            offsetDate: DateTime.fromMillisecondsSinceEpoch(0),
            addOffset: 0,
            limit: requestLimit,
            maxId: 0,
            minId: 0,
            hash: 0,
          ),
          "Telegram не ответил на чтение истории ${peer.title}",
        );

        final error = response.error;
        if (error != null) {
          AppLogger.log.w(
            "Telegram MTProto history failed for ${peer.title}: "
            "${error.errorMessage}",
          );
          break;
        }

        final messages = _messagesFrom(response.result).toList();
        if (messages.isEmpty) break;

        scannedMessages += messages.length;
        for (final message in messages) {
          final track = _trackFromMessage(message, peer);
          if (track != null) tracks.add(track);
        }
        onProgress?.call(peer.title, scannedMessages, tracks.length);

        final nextOffsetId = messages
            .map((message) => message.id)
            .reduce((left, right) => left < right ? left : right);
        if (nextOffsetId <= 0 || nextOffsetId == offsetId) break;

        offsetId = nextOffsetId;
        if (messages.length < requestLimit) break;
      }
    }

	    return tracks;
	  }

	  Future<TelegramMtprotoTrack?> refreshTrackByMessage({
	    required String chatId,
	    required int messageId,
	  }) async {
	    if (chatId.trim().isEmpty || messageId <= 0) return null;

	    final apiId = _readApiId();
	    final client = await _connect(apiId: apiId);
	    final peers = await _resolvePeers(client, [chatId]);

	    for (final peer in peers) {
	      final track = await _trackAroundMessage(
	        client,
	        peer,
	        messageId,
	      );
	      if (track != null) return track;
	    }

	    return null;
	  }

	  Future<TelegramMtprotoTrack?> _trackAroundMessage(
	    tg.Client client,
	    _ResolvedTelegramPeer peer,
	    int messageId,
	  ) async {
	    for (final window in const [1, 20, 100]) {
	      final response = await _telegramCall(
	        client.messages.getHistory(
	          peer: peer.peer,
	          offsetId: messageId + window,
	          offsetDate: DateTime.fromMillisecondsSinceEpoch(0),
	          addOffset: 0,
	          limit: window == 1 ? 1 : window,
	          maxId: 0,
	          minId: 0,
	          hash: 0,
	        ),
	        "Telegram не ответил на обновление ссылки файла ${peer.title}",
	      );

	      final error = response.error;
	      if (error != null) {
	        AppLogger.log.w(
	          "Telegram MTProto refresh failed for ${peer.title}: "
	          "${error.errorMessage}",
	        );
	        continue;
	      }

	      final message = _messagesFrom(response.result).firstWhereOrNull(
	        (message) => message.id == messageId,
	      );
	      if (message == null) continue;

	      return _trackFromMessage(message, peer);
	    }

	    return null;
	  }

	  Future<Uint8List> downloadDocument({
	    required int documentId,
	    required int accessHash,
	    required String fileReferenceBase64,
	    int? dcId,
	    required int size,
	    String thumbSize = "",
	  }) async {
	    final apiId = _readApiId();
	    final client = await _connect(apiId: apiId);
	    final targetDcId = dcId;
	    if (targetDcId != null && targetDcId > 0 && targetDcId != _dc.id) {
	      return _downloadDocumentFromDc(
	        targetDcId: targetDcId,
	        documentId: documentId,
	        accessHash: accessHash,
	        fileReferenceBase64: fileReferenceBase64,
	        size: size,
	        thumbSize: thumbSize,
	        sourceClient: client,
	      );
	    }

	    return _downloadDocumentOnCurrentDc(
	      documentId: documentId,
	      accessHash: accessHash,
	      fileReferenceBase64: fileReferenceBase64,
	      size: size,
	      thumbSize: thumbSize,
	    );
	  }

	  Future<Uint8List> _downloadDocumentOnCurrentDc({
	    required int documentId,
	    required int accessHash,
	    required String fileReferenceBase64,
	    required int size,
	    String thumbSize = "",
	  }) async {
	    final apiId = _readApiId();
	    final client = await _connect(apiId: apiId);
	    final location = t.InputDocumentFileLocation(
	      id: documentId,
	      accessHash: accessHash,
      fileReference: base64Decode(fileReferenceBase64),
      thumbSize: thumbSize,
	    );
	    final builder = BytesBuilder(copy: false);
	    var offset = 0;
	    const chunkSize = 512 * 1024;
	    final hasKnownSize = size > 0 && thumbSize.isEmpty;

	    while (true) {
	      final response = await _telegramCall(
	        client.upload.getFile(
          precise: false,
          cdnSupported: false,
          location: location,
          offset: offset,
          limit: chunkSize,
        ),
        "Telegram не ответил на загрузку файла",
      );

	      final error = response.error;
	      if (error != null) {
	        final migrateDcId = _migrateDcId(error.errorMessage, "FILE_MIGRATE_");
	        if (migrateDcId != null && migrateDcId != _dc.id) {
	          return _downloadDocumentFromDc(
	            targetDcId: migrateDcId,
	            documentId: documentId,
	            accessHash: accessHash,
	            fileReferenceBase64: fileReferenceBase64,
	            size: size,
	            thumbSize: thumbSize,
	            sourceClient: client,
	          );
	        }
	        throw TelegramMtprotoException(_humanError(error.errorMessage));
	      }

      final result = response.result;
      if (result is! t.UploadFile) {
        throw const TelegramMtprotoException(
          "Telegram не вернул файл через MTProto",
        );
      }

	      final bytes = result.bytes;
	      if (bytes.isEmpty) break;
	      builder.add(bytes);
	      offset += bytes.length;

	      if (thumbSize.isNotEmpty ||
	          bytes.length < chunkSize ||
	          (hasKnownSize && offset >= size)) {
	        break;
	      }
	    }

	    return builder.takeBytes();
	  }

	  Future<Uint8List> _downloadDocumentFromDc({
	    required int targetDcId,
	    required int documentId,
	    required int accessHash,
	    required String fileReferenceBase64,
	    required int size,
	    required String thumbSize,
	    required tg.Client sourceClient,
	  }) async {
	    final originalDc = _dc;
	    final targetDc = await _resolveDcOption(sourceClient, targetDcId);
	    final hasTargetAuth = await _readAuthKey(
	      dcId: targetDcId,
	      allowLegacyFallback: false,
	    ) != null;
	    final exportedAuth =
	        hasTargetAuth ? null : await _exportAuthorization(sourceClient, targetDcId);

	    await _closeConnection();
	    _dc = targetDc;

	    try {
	      final targetClient = await _connect(
	        apiId: _readApiId(),
	        loadPersistedDc: false,
	        allowLegacyAuthFallback: false,
	      );

	      if (exportedAuth != null) {
	        await _importAuthorization(targetClient, exportedAuth);
	        await _persistAuthKey(
	          targetClient.authorizationKey,
	          dcId: targetDcId,
	          updateLegacy: false,
	        );
	      }

	      return await _downloadDocumentOnCurrentDc(
	        documentId: documentId,
	        accessHash: accessHash,
	        fileReferenceBase64: fileReferenceBase64,
	        size: size,
	        thumbSize: thumbSize,
	      );
	    } finally {
	      await _closeConnection();
	      _dc = originalDc;
	    }
	  }

	  Future<t.AuthExportedAuthorization> _exportAuthorization(
	    tg.Client client,
	    int dcId,
	  ) async {
	    final response = await _telegramCall(
	      client.auth.exportAuthorization(dcId: dcId),
	      "Telegram не экспортировал авторизацию для DC $dcId",
	    );
	    final error = response.error;
	    if (error != null) {
	      throw TelegramMtprotoException(_humanError(error.errorMessage));
	    }

	    final result = response.result;
	    if (result is! t.AuthExportedAuthorization) {
	      throw TelegramMtprotoException(
	        "Telegram вернул неверную авторизацию для DC $dcId",
	      );
	    }
	    return result;
	  }

	  Future<void> _importAuthorization(
	    tg.Client client,
	    t.AuthExportedAuthorization authorization,
	  ) async {
	    final response = await _telegramCall(
	      client.auth.importAuthorization(
	        id: authorization.id,
	        bytes: authorization.bytes,
	      ),
	      "Telegram не импортировал авторизацию для файлового DC",
	    );
	    final error = response.error;
	    if (error != null) {
	      throw TelegramMtprotoException(_humanError(error.errorMessage));
	    }
	  }

	  Future<String?> readPhoneNumber() async {
	    return KVStoreService.sharedPreferences.getString(_phoneKey);
	  }

  Future<void> disconnect() async {
    await _closeConnection();
    final prefs = KVStoreService.sharedPreferences;
    await prefs.remove(_apiIdKey);
    await prefs.remove(_phoneKey);
    await prefs.remove(_phoneCodeHashKey);
    await prefs.remove(_dcIdKey);
    await prefs.remove(_dcIpKey);
    await prefs.remove(_dcPortKey);
	    await _deleteSecure(_apiHashKey);
	    await _deleteSecure(_authKeyKey);
	    for (final dcId in const [1, 2, 3, 4, 5]) {
	      await _deleteSecure(_authKeyStorageKey(dcId));
	    }
	  }

	  Future<tg.Client> _connect({
	    required int apiId,
	    bool loadPersistedDc = true,
	    bool allowLegacyAuthFallback = true,
	  }) async {
	    final existing = _client;
	    if (existing != null) return existing;

	    Socket? socket;
	    try {
	      if (loadPersistedDc) _loadDc();
	      socket = await Socket.connect(_dc.ipAddress, _dc.port)
	          .timeout(_socketTimeout);
	      _socket = socket;

      final transport = _TelegramTcpSocket(socket);
      final obfuscation = tg.Obfuscation.random(false, _dc.id);
      final messageIdGenerator = tg.MessageIdGenerator();
      await transport.send(obfuscation.preamble).timeout(_socketTimeout);

	      final loadedKey = await _readAuthKey(
	        dcId: _dc.id,
	        allowLegacyFallback: allowLegacyAuthFallback,
	      );
      final authKey = loadedKey ??
          await tg.Client
              .authorize(
                transport,
                obfuscation,
                messageIdGenerator,
              )
              .timeout(_authTimeout);

      final client = tg.Client(
        socket: transport,
        obfuscation: obfuscation,
        authorizationKey: authKey,
        idGenerator: messageIdGenerator,
      );

      _updatesSubscription = client.stream.listen(
        (event) => AppLogger.log.d("Telegram MTProto update: $event"),
        onError: (Object error, StackTrace stackTrace) {
          AppLogger.reportError(error, stackTrace);
        },
      );

      final packageInfo = await PackageInfo.fromPlatform();
      final config = await _telegramCall(
        client.initConnection<t.ConfigBase>(
          apiId: apiId,
          deviceModel: appName,
          systemVersion: Platform.operatingSystem,
          appVersion: "$appName ${packageInfo.version}",
          systemLangCode: Platform.localeName.split("_").first,
          langPack: "",
          langCode: Platform.localeName.split("_").first,
          query: const t.HelpGetConfig(),
        ),
        "Telegram не ответил на инициализацию сессии. Попробуй еще раз.",
      );

      final result = config.result;
      if (result is t.Config) {
        final nearestDc = result.dcOptions
            .whereType<t.DcOption>()
            .where((dc) => !dc.ipv6 && !dc.mediaOnly && dc.port == 443)
            .firstWhere(
              (dc) => dc.id == _dc.id,
              orElse: () => result.dcOptions
                  .whereType<t.DcOption>()
                  .firstWhere((dc) => !dc.ipv6 && dc.port == 443),
            );
	        if (loadPersistedDc) {
	          await _saveDc(nearestDc);
	        } else {
	          _dc = nearestDc;
	        }
	      }

      _client = client;
      return client;
    } on TelegramMtprotoException {
      await _closeConnection(socket);
      rethrow;
    } on TimeoutException catch (error, stackTrace) {
      AppLogger.reportError(error, stackTrace);
      await _closeConnection(socket);
      throw const TelegramMtprotoException(
        "Telegram не ответил вовремя. Проверь сеть, API ID/API hash и попробуй еще раз.",
      );
    } on SocketException catch (error, stackTrace) {
      AppLogger.reportError(error, stackTrace);
      await _closeConnection(socket);
      throw TelegramMtprotoException(
        "Не удалось подключиться к Telegram DC: ${error.message}",
      );
    } on tg.BadMessageException catch (error, stackTrace) {
      AppLogger.reportError(error, stackTrace);
      await _closeConnection(socket);
      throw TelegramMtprotoException(_humanBadMessage(error));
    } catch (error, stackTrace) {
      AppLogger.reportError(error, stackTrace);
      await _closeConnection(socket);
      throw TelegramMtprotoException("MTProto не смог подключиться: $error");
    }
  }

  int _readApiId() {
    final apiId = KVStoreService.sharedPreferences.getInt(_apiIdKey);
    if (apiId == null || apiId <= 0) {
      throw const TelegramMtprotoException("Сначала подключи Telegram-сессию");
    }
    return apiId;
  }

  Future<List<_ResolvedTelegramPeer>> _resolvePeers(
    tg.Client client,
    List<String> sourceFilters,
  ) async {
    final normalized = sourceFilters
        .map((source) => source.trim())
        .where((source) => source.isNotEmpty)
        .toList();

    final dialogs = await _loadDialogPeers(client);
    if (normalized.isEmpty) return dialogs.take(40).toList();

    final peers = <_ResolvedTelegramPeer>[];
    for (final source in normalized) {
      final direct = _resolveSpecialPeer(source);
      if (direct != null) {
        peers.add(direct);
        continue;
      }

      final fromDialogs = _matchDialogPeer(dialogs, source);
      if (fromDialogs != null) {
        peers.add(fromDialogs);
        continue;
      }

      final username = _usernameFromSource(source);
      if (username == null) continue;

      final resolved = await _telegramCall(
        client.contacts.resolveUsername(username: username),
        "Telegram не ответил на поиск @$username",
      );
      final error = resolved.error;
      if (error != null) {
        AppLogger.log.w(
          "Telegram MTProto resolve @$username failed: ${error.errorMessage}",
        );
        continue;
      }

      final peer = _peerFromResolved(resolved.result);
      if (peer != null) peers.add(peer);
    }

    final seen = <String>{};
    return peers.where((peer) => seen.add(peer.key)).toList();
  }

  Future<List<_ResolvedTelegramPeer>> _loadDialogPeers(
    tg.Client client,
  ) async {
    final response = await _telegramCall(
      client.messages.getDialogs(
        excludePinned: false,
        offsetDate: DateTime.fromMillisecondsSinceEpoch(0),
        offsetId: 0,
        offsetPeer: const t.InputPeerEmpty(),
        limit: 100,
        hash: 0,
      ),
      "Telegram не ответил на список диалогов",
    );

    final error = response.error;
    if (error != null) {
      throw TelegramMtprotoException(_humanError(error.errorMessage));
    }

    return _peersFromDialogs(response.result);
  }

  _ResolvedTelegramPeer? _resolveSpecialPeer(String source) {
    final normalized = source.trim().toLowerCase();
    if (normalized == "me" ||
        normalized == "self" ||
        normalized == "saved" ||
        normalized == "избранное") {
      return const _ResolvedTelegramPeer(
        peer: t.InputPeerSelf(),
        id: "self",
        title: "Избранное",
      );
    }
    return null;
  }

  _ResolvedTelegramPeer? _matchDialogPeer(
    List<_ResolvedTelegramPeer> dialogs,
    String source,
  ) {
    final query = source.trim().toLowerCase();
    return dialogs.firstWhereOrNull(
      (peer) => peer.candidates.any((candidate) => candidate == query),
    );
  }

  String? _usernameFromSource(String source) {
    final value = source.trim();
    if (value.isEmpty || int.tryParse(value) != null) return null;
    final cleaned = value
        .replaceFirst(RegExp(r"^https?://t\.me/", caseSensitive: false), "")
        .replaceFirst(RegExp(r"^tg://resolve\?domain=", caseSensitive: false), "")
        .replaceFirst("@", "")
        .split("/")
        .first
        .trim();
    if (cleaned.isEmpty || cleaned.contains(" ")) return null;
    return cleaned;
  }

  _ResolvedTelegramPeer? _peerFromResolved(t.ContactsResolvedPeerBase? base) {
    if (base is! t.ContactsResolvedPeer) return null;
    final peer = base.peer;

    if (peer is t.PeerChannel) {
      final channel = base.chats.whereType<t.Channel>().firstWhereOrNull(
            (chat) => chat.id == peer.channelId && chat.accessHash != null,
          );
      if (channel == null || channel.accessHash == null) return null;
      return _ResolvedTelegramPeer(
        peer: t.InputPeerChannel(
          channelId: channel.id,
          accessHash: channel.accessHash!,
        ),
        id: channel.id.toString(),
        title: channel.title,
        username: channel.username,
      );
    }

    if (peer is t.PeerChat) {
      final chat = base.chats.whereType<t.Chat>().firstWhereOrNull(
            (chat) => chat.id == peer.chatId,
          );
      return _ResolvedTelegramPeer(
        peer: t.InputPeerChat(chatId: peer.chatId),
        id: peer.chatId.toString(),
        title: chat?.title ?? "Telegram chat",
      );
    }

    if (peer is t.PeerUser) {
      final user = base.users.whereType<t.User>().firstWhereOrNull(
            (user) => user.id == peer.userId,
          );
      if (user == null) return null;
      return _peerFromUser(user);
    }

    return null;
  }

  List<_ResolvedTelegramPeer> _peersFromDialogs(
    t.MessagesDialogsBase? dialogs,
  ) {
    final chats = switch (dialogs) {
      t.MessagesDialogs(:final chats) => chats,
      t.MessagesDialogsSlice(:final chats) => chats,
      _ => const <t.ChatBase>[],
    };
    final users = switch (dialogs) {
      t.MessagesDialogs(:final users) => users,
      t.MessagesDialogsSlice(:final users) => users,
      _ => const <t.UserBase>[],
    };

    return [
      for (final chat in chats) ...?_peerFromChat(chat),
      for (final user in users.whereType<t.User>())
        if (_peerFromUser(user) != null) _peerFromUser(user)!,
    ];
  }

  List<_ResolvedTelegramPeer>? _peerFromChat(t.ChatBase chat) {
    if (chat is t.Channel && chat.accessHash != null) {
      return [
        _ResolvedTelegramPeer(
          peer: t.InputPeerChannel(
            channelId: chat.id,
            accessHash: chat.accessHash!,
          ),
          id: chat.id.toString(),
          title: chat.title,
          username: chat.username,
        ),
      ];
    }

    if (chat is t.Chat) {
      return [
        _ResolvedTelegramPeer(
          peer: t.InputPeerChat(chatId: chat.id),
          id: chat.id.toString(),
          title: chat.title,
        ),
      ];
    }

    return null;
  }

  _ResolvedTelegramPeer? _peerFromUser(t.User user) {
    if (user.self) {
      return const _ResolvedTelegramPeer(
        peer: t.InputPeerSelf(),
        id: "self",
        title: "Избранное",
      );
    }
    final accessHash = user.accessHash;
    if (accessHash == null) return null;
    final name = [
      user.firstName,
      user.lastName,
    ].whereType<String>().where((part) => part.trim().isNotEmpty).join(" ");
    return _ResolvedTelegramPeer(
      peer: t.InputPeerUser(userId: user.id, accessHash: accessHash),
      id: user.id.toString(),
      title: name.isEmpty ? user.username ?? "Telegram user" : name,
      username: user.username,
    );
  }

  Iterable<t.Message> _messagesFrom(t.MessagesMessagesBase? base) {
    final messages = switch (base) {
      t.MessagesMessages(:final messages) => messages,
      t.MessagesMessagesSlice(:final messages) => messages,
      t.MessagesChannelMessages(:final messages) => messages,
      _ => const <t.MessageBase>[],
    };
    return messages.whereType<t.Message>();
  }

  TelegramMtprotoTrack? _trackFromMessage(
    t.Message message,
    _ResolvedTelegramPeer peer,
  ) {
    final media = message.media;
    if (media is! t.MessageMediaDocument) return null;
    final documentBase = media.document;
    if (documentBase is! t.Document) return null;

    final audio = documentBase.attributes.whereType<t.DocumentAttributeAudio>()
        .firstOrNull;
    final fileName = documentBase.attributes
        .whereType<t.DocumentAttributeFilename>()
        .firstOrNull
        ?.fileName;
    final lowerFileName = fileName?.toLowerCase() ?? "";
    final isAudio = audio != null ||
        documentBase.mimeType.startsWith("audio/") ||
        lowerFileName.endsWith(".mp3") ||
        lowerFileName.endsWith(".m4a") ||
        lowerFileName.endsWith(".flac") ||
        lowerFileName.endsWith(".ogg") ||
        lowerFileName.endsWith(".opus") ||
        lowerFileName.endsWith(".wav");

    if (!isAudio) return null;

    final rawTitle = audio?.title ?? _basename(fileName) ?? message.message;
    final parsed = _splitArtistTitle(rawTitle);
    final title = parsed?.title ?? rawTitle.trim();
    final artist = audio?.performer ?? parsed?.artist ?? "Telegram";
    final thumbSize = documentBase.thumbs
        ?.whereType<t.PhotoSize>()
        .lastOrNull
        ?.type;

    return TelegramMtprotoTrack(
      documentId: documentBase.id,
      accessHash: documentBase.accessHash,
      fileReferenceBase64: base64Encode(documentBase.fileReference),
      dcId: documentBase.dcId,
      size: documentBase.size,
      title: title.isEmpty ? "Telegram audio" : title,
      artist: artist.trim().isEmpty ? "Telegram" : artist,
      album: peer.title,
      chatId: peer.id,
      chatTitle: peer.title,
      messageId: message.id,
      durationMs: (audio?.duration ?? 0) * 1000,
      mimeType: documentBase.mimeType,
      fileName: fileName,
      thumbSize: thumbSize,
      addedAt: message.date,
    );
  }

	  Future<bool> _handleMigration(
	    t.RpcError error, {
	    required int apiId,
	  }) async {
	    final message = error.errorMessage;
	    final dcId = _migrateDcId(message, "PHONE_MIGRATE_") ??
	        _migrateDcId(message, "NETWORK_MIGRATE_") ??
	        _migrateDcId(message, "USER_MIGRATE_");
	    if (dcId == null) return false;

	    final client = await _connect(apiId: apiId);
	    final targetDc = await _resolveDcOption(client, dcId);

	    await _saveDc(targetDc);
	    await _closeConnection();
	    return true;
	  }

	  int? _migrateDcId(String message, String prefix) {
	    if (!message.startsWith(prefix)) return null;
	    return int.tryParse(message.split("_").last);
	  }

	  Future<t.DcOption> _resolveDcOption(tg.Client client, int dcId) async {
	    final config = await _telegramCall(
	      client.help.getConfig(),
	      "Telegram не ответил на список дата-центров",
	    );
	    final configResult = config.result;
	    if (configResult is t.Config) {
	      for (final dc in configResult.dcOptions.whereType<t.DcOption>()) {
	        if (!dc.ipv6 && dc.port == 443 && dc.id == dcId) {
	          return dc;
	        }
	      }
	    }

	    throw TelegramMtprotoException(
	      "Telegram не вернул дата-центр $dcId",
	    );
	  }

  void _loadDc() {
    final prefs = KVStoreService.sharedPreferences;
    final id = prefs.getInt(_dcIdKey);
    final ip = prefs.getString(_dcIpKey);
    final port = prefs.getInt(_dcPortKey);
    if (id == null || ip == null || port == null) return;

    _dc = t.DcOption(
      ipv6: false,
      mediaOnly: false,
      tcpoOnly: false,
      cdn: false,
      static: false,
      thisPortOnly: false,
      id: id,
      ipAddress: ip,
      port: port,
    );
  }

  Future<void> _saveDc(t.DcOption dc) async {
    _dc = dc;
    final prefs = KVStoreService.sharedPreferences;
    await prefs.setInt(_dcIdKey, dc.id);
    await prefs.setString(_dcIpKey, dc.ipAddress);
    await prefs.setInt(_dcPortKey, dc.port);
  }

	  String _authKeyStorageKey(int dcId) => "${_authKeyKey}_dc_$dcId";

	  Future<tg.AuthorizationKey?> _readAuthKey({
	    int? dcId,
	    bool allowLegacyFallback = true,
	  }) async {
	    final targetDcId = dcId ?? _dc.id;
	    final raw = await _readSecure(_authKeyStorageKey(targetDcId)) ??
	        (allowLegacyFallback ? await _readSecure(_authKeyKey) : null);
	    return _decodeAuthKey(raw);
	  }

	  tg.AuthorizationKey? _decodeAuthKey(String? raw) {
	    if (raw == null || raw.isEmpty) return null;

	    try {
      return tg.AuthorizationKey.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
	    } catch (_) {
	      return null;
	    }
	  }

	  Future<void> _persistAuthKey(
	    tg.AuthorizationKey key, {
	    int? dcId,
	    bool updateLegacy = true,
	  }) async {
	    final encoded = jsonEncode(key.toJson());
	    await _writeSecure(_authKeyStorageKey(dcId ?? _dc.id), encoded);
	    if (updateLegacy) {
	      await _writeSecure(_authKeyKey, encoded);
	    }
	  }

	  Future<String?> _readSecure(String key) async {
	    try {
	      final value = await EncryptedKvStoreService.storage.read(key: key);
	      if (value != null && value.isNotEmpty) {
	        await KVStoreService.sharedPreferences.setString(key, value);
	      }
	      return value ?? KVStoreService.sharedPreferences.getString(key);
	    } catch (_) {
	      return KVStoreService.sharedPreferences.getString(key);
	    }
	  }

	  Future<void> _writeSecure(String key, String value) async {
	    try {
	      await EncryptedKvStoreService.storage.write(key: key, value: value);
	    } catch (_) {
	      // SharedPreferences below is the stable fallback.
	    } finally {
	      await KVStoreService.sharedPreferences.setString(key, value);
	    }
	  }

  Future<void> _deleteSecure(String key) async {
    try {
      await EncryptedKvStoreService.storage.delete(key: key);
    } catch (_) {
      // Secure storage may be unavailable on some desktop/Linux builds.
    } finally {
      await KVStoreService.sharedPreferences.remove(key);
    }
  }

  Future<T> _telegramCall<T>(
    Future<T> call,
    String timeoutMessage, {
    Duration timeout = _requestTimeout,
  }) async {
    try {
      return await call.timeout(timeout);
    } on TimeoutException catch (error, stackTrace) {
      AppLogger.reportError(error, stackTrace);
      await _closeConnection();
      throw TelegramMtprotoException(timeoutMessage);
    } on SocketException catch (error, stackTrace) {
      AppLogger.reportError(error, stackTrace);
      await _closeConnection();
      throw TelegramMtprotoException(
        "Соединение с Telegram оборвалось: ${error.message}",
      );
    } on tg.BadMessageException catch (error, stackTrace) {
      AppLogger.reportError(error, stackTrace);
      await _closeConnection();
      throw TelegramMtprotoException(_humanBadMessage(error));
    }
  }

  Future<void> _closeConnection([Socket? socket]) async {
    final socketToClose = socket ?? _socket;
    _client = null;
    _socket = null;
    await _updatesSubscription?.cancel();
    _updatesSubscription = null;
    socketToClose?.destroy();
  }

  String _humanError(String error) {
    return switch (error) {
      "PHONE_CODE_INVALID" => "Неверный код Telegram",
      "PHONE_CODE_EXPIRED" => "Код Telegram истек, запроси новый",
      "PASSWORD_HASH_INVALID" => "Неверный пароль 2FA",
      "PHONE_NUMBER_INVALID" => "Telegram не принял номер телефона",
      "API_ID_INVALID" => "Неверный Telegram API ID/API hash",
      _ => error,
    };
  }

  String _humanBadMessage(tg.BadMessageException error) {
    final code = error.result.errorCode;
    return switch (code) {
      32 || 33 =>
        "Telegram отклонил старый MTProto session/seqno. Я пересоздал соединение, нажми синхронизацию еще раз.",
      16 || 17 =>
        "Telegram отклонил msg_id. Проверь дату и время на устройстве и попробуй снова.",
      48 =>
        "Telegram вернул новый server salt. Нажми синхронизацию еще раз.",
      _ => "Telegram MTProto bad message $code: ${error.errorMessage}",
    };
  }
}

class TelegramMtprotoTrack {
  final int documentId;
  final int accessHash;
  final String fileReferenceBase64;
  final int dcId;
  final int size;
  final String title;
  final String artist;
  final String album;
  final String chatId;
  final String chatTitle;
  final int messageId;
  final int durationMs;
  final String mimeType;
  final String? fileName;
  final String? thumbSize;
  final DateTime addedAt;

  const TelegramMtprotoTrack({
    required this.documentId,
    required this.accessHash,
    required this.fileReferenceBase64,
    required this.dcId,
    required this.size,
    required this.title,
    required this.artist,
    required this.album,
    required this.chatId,
    required this.chatTitle,
    required this.messageId,
    required this.durationMs,
    required this.mimeType,
    this.fileName,
    this.thumbSize,
    required this.addedAt,
  });
}

class _ResolvedTelegramPeer {
  final t.InputPeerBase peer;
  final String id;
  final String title;
  final String? username;

  const _ResolvedTelegramPeer({
    required this.peer,
    required this.id,
    required this.title,
    this.username,
  });

  String get key => "${peer.runtimeType}:$id";

  Set<String> get candidates {
    final cleanUsername = username?.toLowerCase();
    final cleanTitle = title.toLowerCase();
    final rawId = id.toLowerCase();
    return {
      rawId,
      cleanTitle,
      if (cleanUsername != null) cleanUsername,
      if (cleanUsername != null) "@$cleanUsername",
      if (int.tryParse(id) != null) "-$id",
      if (int.tryParse(id) != null) "-100$id",
    };
  }
}

class TelegramSessionSendCodeResult {
  final String phoneNumber;
  final String phoneCodeHash;

  const TelegramSessionSendCodeResult({
    required this.phoneNumber,
    required this.phoneCodeHash,
  });
}

class TelegramSessionSignInResult {
  final bool connected;
  final bool passwordRequired;
  final String? hint;

  const TelegramSessionSignInResult.connected()
      : connected = true,
        passwordRequired = false,
        hint = null;

  const TelegramSessionSignInResult.passwordRequired({this.hint})
      : connected = false,
        passwordRequired = true;
}

class TelegramMtprotoException implements Exception {
  final String message;

  const TelegramMtprotoException(this.message);

  @override
  String toString() => message;
}

class _TelegramTcpSocket extends tg.SocketAbstraction {
  final Socket socket;
  late final Stream<Uint8List> _receiver = socket
      .map((chunk) => Uint8List.fromList(chunk))
      .asBroadcastStream(
        onListen: (subscription) {
          if (subscription.isPaused) subscription.resume();
        },
        onCancel: (subscription) => subscription.pause(),
      );

  _TelegramTcpSocket(this.socket);

  @override
  Stream<Uint8List> get receiver => _receiver;

  @override
  Future<void> send(List<int> data) async {
    socket.add(data);
    await socket.flush();
  }
}

String? _basename(String? fileName) {
  if (fileName == null || fileName.trim().isEmpty) return null;
  final cleaned = fileName.split("/").last;
  final dot = cleaned.lastIndexOf(".");
  return dot <= 0 ? cleaned : cleaned.substring(0, dot);
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
