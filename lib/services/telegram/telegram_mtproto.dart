import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:t/t.dart' as t;
import 'package:tg/tg.dart' as tg;
import 'package:etgmusic/services/kv_store/encrypted_kv_store.dart';
import 'package:etgmusic/services/kv_store/kv_store.dart';
import 'package:etgmusic/services/logger/logger.dart';

class TelegramMtprotoService {
  static const appName = "ETGmusic";
  static const _apiIdKey = "telegram_mtproto_api_id";
  static const _apiHashKey = "telegram_mtproto_api_hash";
  static const _phoneKey = "telegram_mtproto_phone";
  static const _phoneCodeHashKey = "telegram_mtproto_code_hash";
  static const _authKeyKey = "telegram_mtproto_auth_key";
  static const _dcIdKey = "telegram_mtproto_dc_id";
  static const _dcIpKey = "telegram_mtproto_dc_ip";
  static const _dcPortKey = "telegram_mtproto_dc_port";

  tg.Client? _client;
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
    final response = await client.auth.sendCode(
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
    final response = await client.auth.signIn(
      phoneNumber: phone,
      phoneCodeHash: phoneCodeHash,
      phoneCode: code.trim(),
    );

    final error = response.error;
    if (error != null) {
      if (error.errorMessage == "SESSION_PASSWORD_NEEDED") {
        final password = await client.account.getPassword();
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
    final accountPasswordResponse = await client.account.getPassword();
    final accountPassword = accountPasswordResponse.result;
    if (accountPassword is! t.AccountPassword) {
      throw const TelegramMtprotoException("Telegram не вернул параметры 2FA");
    }

    final inputPassword = await tg.check2FA(accountPassword, password);
    final response = await client.auth.checkPassword(password: inputPassword);
    final error = response.error;
    if (error != null) {
      throw TelegramMtprotoException(_humanError(error.errorMessage));
    }

    await _persistAuthKey(client.authorizationKey);
  }

  Future<String?> readPhoneNumber() async {
    return KVStoreService.sharedPreferences.getString(_phoneKey);
  }

  Future<void> disconnect() async {
    _client = null;
    final prefs = KVStoreService.sharedPreferences;
    await prefs.remove(_apiIdKey);
    await prefs.remove(_phoneKey);
    await prefs.remove(_phoneCodeHashKey);
    await prefs.remove(_dcIdKey);
    await prefs.remove(_dcIpKey);
    await prefs.remove(_dcPortKey);
    await _deleteSecure(_apiHashKey);
    await _deleteSecure(_authKeyKey);
  }

  Future<tg.Client> _connect({required int apiId}) async {
    final existing = _client;
    if (existing != null) return existing;

    _loadDc();
    final socket = await Socket.connect(_dc.ipAddress, _dc.port);
    final transport = _TelegramTcpSocket(socket);
    final obfuscation = tg.Obfuscation.random(false, _dc.id);
    final messageIdGenerator = tg.MessageIdGenerator();
    await transport.send(obfuscation.preamble);

    final loadedKey = await _readAuthKey();
    final authKey = loadedKey ??
        await tg.Client.authorize(
          transport,
          obfuscation,
          messageIdGenerator,
        );

    final client = tg.Client(
      socket: transport,
      obfuscation: obfuscation,
      authorizationKey: authKey,
      idGenerator: messageIdGenerator,
    );

    client.stream.listen(
      (event) => AppLogger.log.d("Telegram MTProto update: $event"),
      onError: (Object error, StackTrace stackTrace) {
        AppLogger.reportError(error, stackTrace);
      },
    );

    final packageInfo = await PackageInfo.fromPlatform();
    final config = await client.initConnection<t.ConfigBase>(
      apiId: apiId,
      deviceModel: appName,
      systemVersion: Platform.operatingSystem,
      appVersion: "$appName ${packageInfo.version}",
      systemLangCode: Platform.localeName.split("_").first,
      langPack: "",
      langCode: Platform.localeName.split("_").first,
      query: const t.HelpGetConfig(),
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
      await _saveDc(nearestDc);
    }

    _client = client;
    return client;
  }

  Future<bool> _handleMigration(
    t.RpcError error, {
    required int apiId,
  }) async {
    final message = error.errorMessage;
    if (!message.startsWith("PHONE_MIGRATE_") &&
        !message.startsWith("NETWORK_MIGRATE_") &&
        !message.startsWith("USER_MIGRATE_")) {
      return false;
    }

    final dcId = int.tryParse(message.split("_").last);
    if (dcId == null) return false;

    final client = await _connect(apiId: apiId);
    final config = await client.help.getConfig();
    final configResult = config.result;
    t.DcOption? targetDc;
    if (configResult is t.Config) {
      for (final dc in configResult.dcOptions.whereType<t.DcOption>()) {
        if (!dc.ipv6 && dc.port == 443 && dc.id == dcId) {
          targetDc = dc;
          break;
        }
      }
    }
    if (targetDc == null) return false;

    await _saveDc(targetDc);
    _client = null;
    return true;
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

  Future<tg.AuthorizationKey?> _readAuthKey() async {
    final raw = await _readSecure(_authKeyKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      return tg.AuthorizationKey.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistAuthKey(tg.AuthorizationKey key) async {
    await _writeSecure(_authKeyKey, jsonEncode(key.toJson()));
  }

  Future<String?> _readSecure(String key) async {
    try {
      return await EncryptedKvStoreService.storage.read(key: key);
    } catch (_) {
      return KVStoreService.sharedPreferences.getString(key);
    }
  }

  Future<void> _writeSecure(String key, String value) async {
    try {
      await EncryptedKvStoreService.storage.write(key: key, value: value);
    } catch (_) {
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

  _TelegramTcpSocket(this.socket);

  @override
  Stream<Uint8List> get receiver =>
      socket.map((chunk) => Uint8List.fromList(chunk));

  @override
  Future<void> send(List<int> data) async {
    socket.add(data);
    await socket.flush();
  }
}
