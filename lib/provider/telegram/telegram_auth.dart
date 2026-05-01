import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:etgmusic/services/dio/dio.dart';
import 'package:etgmusic/services/kv_store/encrypted_kv_store.dart';
import 'package:etgmusic/services/kv_store/kv_store.dart';
import 'package:etgmusic/services/telegram/telegram_mtproto.dart';

enum TelegramAuthMode {
  none,
  bot,
  user,
}

enum TelegramSessionStatus {
  none,
  codeSent,
  passwordRequired,
  connected,
}

class TelegramAuthState {
  final TelegramAuthMode mode;
  final TelegramSessionStatus sessionStatus;
  final int? botId;
  final String? botUsername;
  final String? botName;
  final String? phoneNumber;
  final String? passwordHint;
  final DateTime? connectedAt;

  const TelegramAuthState({
    this.mode = TelegramAuthMode.none,
    this.sessionStatus = TelegramSessionStatus.none,
    this.botId,
    this.botUsername,
    this.botName,
    this.phoneNumber,
    this.passwordHint,
    this.connectedAt,
  });

  bool get isConnected => mode != TelegramAuthMode.none;
  bool get isBotConnected => mode == TelegramAuthMode.bot;
  bool get isUserSessionConnected =>
      mode == TelegramAuthMode.user &&
      sessionStatus == TelegramSessionStatus.connected;
  bool get isUserSessionPending =>
      mode == TelegramAuthMode.user &&
      sessionStatus != TelegramSessionStatus.connected;

  String get title {
    if (!isConnected) return "Telegram не подключен";
    if (mode == TelegramAuthMode.user) {
      return isUserSessionConnected
          ? "Подключена Telegram-сессия"
          : "Вход через Telegram-сессию";
    }
    final username = botUsername == null ? "" : " @$botUsername";
    return "Подключен бот$username";
  }

  String get subtitle {
    if (!isConnected) {
      return "Подключи бота из @BotFather, добавь его в нужные каналы/группы и ETGmusic сможет использовать этот источник дальше.";
    }

    if (mode == TelegramAuthMode.user) {
      final phone = phoneNumber == null ? "" : " $phoneNumber";
      final date = connectedAt == null
          ? ""
          : " · ${connectedAt!.day.toString().padLeft(2, '0')}.${connectedAt!.month.toString().padLeft(2, '0')}.${connectedAt!.year}";
      return switch (sessionStatus) {
        TelegramSessionStatus.codeSent => "Код отправлен в Telegram$phone",
        TelegramSessionStatus.passwordRequired =>
          "Нужен пароль 2FA${passwordHint == null ? "" : " · подсказка: $passwordHint"}",
        TelegramSessionStatus.connected => "ETGmusic$phone$date",
        TelegramSessionStatus.none => "Telegram-сессия не завершена",
      };
    }

    final name = botName == null ? "Telegram Bot" : botName!;
    final date = connectedAt == null
        ? ""
        : " · ${connectedAt!.day.toString().padLeft(2, '0')}.${connectedAt!.month.toString().padLeft(2, '0')}.${connectedAt!.year}";
    return "$name$date";
  }
}

class TelegramAuthNotifier extends AsyncNotifier<TelegramAuthState> {
  static const _modeKey = "telegram_auth_mode";
  static const _botIdKey = "telegram_bot_id";
  static const _botUsernameKey = "telegram_bot_username";
  static const _botNameKey = "telegram_bot_name";
  static const _phoneNumberKey = "telegram_phone_number";
  static const _sessionStatusKey = "telegram_session_status";
  static const _passwordHintKey = "telegram_session_password_hint";
  static const _connectedAtKey = "telegram_connected_at";
  static const _botTokenKey = "telegram_bot_token";
  final TelegramMtprotoService _mtproto = TelegramMtprotoService();

  @override
  Future<TelegramAuthState> build() async {
    return _readState();
  }

  Future<void> connectBot(String rawToken) async {
    final token = rawToken.trim();
    if (token.isEmpty) {
      throw ArgumentError("Вставь Bot API token из @BotFather");
    }

    state = const AsyncLoading();
    try {
      final bot = await _verifyBotToken(token);
      final next = TelegramAuthState(
        mode: TelegramAuthMode.bot,
        botId: bot.id,
        botUsername: bot.username,
        botName: bot.name,
        connectedAt: DateTime.now(),
      );

      await _writeToken(token);
      await _writeState(next);

      state = AsyncData(next);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> disconnect() async {
    state = const AsyncLoading();
    try {
      await _deleteToken();
      await _mtproto.disconnect();
      await KVStoreService.sharedPreferences.remove(_modeKey);
      await KVStoreService.sharedPreferences.remove(_botIdKey);
      await KVStoreService.sharedPreferences.remove(_botUsernameKey);
      await KVStoreService.sharedPreferences.remove(_botNameKey);
      await KVStoreService.sharedPreferences.remove(_phoneNumberKey);
      await KVStoreService.sharedPreferences.remove(_sessionStatusKey);
      await KVStoreService.sharedPreferences.remove(_passwordHintKey);
      await KVStoreService.sharedPreferences.remove(_connectedAtKey);

      state = const AsyncData(TelegramAuthState());
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> startUserSession({
    required int apiId,
    required String apiHash,
    required String phoneNumber,
  }) async {
    state = const AsyncLoading();
    try {
      final result = await _mtproto.sendCode(
        apiId: apiId,
        apiHash: apiHash,
        phoneNumber: phoneNumber,
      );
      final next = TelegramAuthState(
        mode: TelegramAuthMode.user,
        sessionStatus: TelegramSessionStatus.codeSent,
        phoneNumber: result.phoneNumber,
      );
      await _writeState(next);
      state = AsyncData(next);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> submitUserSessionCode(String code) async {
    state = const AsyncLoading();
    try {
      final result = await _mtproto.signInWithCode(code);
      final phoneNumber = await _mtproto.readPhoneNumber();
      final next = result.passwordRequired
          ? TelegramAuthState(
              mode: TelegramAuthMode.user,
              sessionStatus: TelegramSessionStatus.passwordRequired,
              phoneNumber: phoneNumber,
              passwordHint: result.hint,
            )
          : TelegramAuthState(
              mode: TelegramAuthMode.user,
              sessionStatus: TelegramSessionStatus.connected,
              phoneNumber: phoneNumber,
              connectedAt: DateTime.now(),
            );

      await _writeState(next);
      state = AsyncData(next);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> submitUserSessionPassword(String password) async {
    state = const AsyncLoading();
    try {
      await _mtproto.checkPassword(password);
      final phoneNumber = await _mtproto.readPhoneNumber();
      final next = TelegramAuthState(
        mode: TelegramAuthMode.user,
        sessionStatus: TelegramSessionStatus.connected,
        phoneNumber: phoneNumber,
        connectedAt: DateTime.now(),
      );
      await _writeState(next);
      state = AsyncData(next);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<String?> readBotToken() async {
    return _readToken();
  }

  Future<_TelegramBot> _verifyBotToken(String token) async {
    try {
      final response = await globalDio.getUri(
        Uri.parse("https://api.telegram.org/bot$token/getMe"),
        options: Options(responseType: ResponseType.json),
      );

      final body = response.data;
      if (body is! Map || body["ok"] != true || body["result"] is! Map) {
        throw const TelegramAuthException("Telegram не принял этот токен");
      }

      final result = body["result"] as Map;
      return _TelegramBot(
        id: result["id"] as int,
        username: result["username"]?.toString(),
        name: result["first_name"]?.toString(),
      );
    } on DioException catch (error) {
      final data = error.response?.data;
      final description = data is Map ? data["description"]?.toString() : null;
      throw TelegramAuthException(
        description ?? "Не удалось проверить токен Telegram",
      );
    }
  }

  TelegramAuthState _readState() {
    final prefs = KVStoreService.sharedPreferences;
    final modeName = prefs.getString(_modeKey);

    if (modeName == TelegramAuthMode.user.name) {
      final connectedAtRaw = prefs.getString(_connectedAtKey);
      final statusName = prefs.getString(_sessionStatusKey);
      return TelegramAuthState(
        mode: TelegramAuthMode.user,
        sessionStatus: TelegramSessionStatus.values.firstWhere(
          (status) => status.name == statusName,
          orElse: () => TelegramSessionStatus.connected,
        ),
        phoneNumber: prefs.getString(_phoneNumberKey),
        passwordHint: prefs.getString(_passwordHintKey),
        connectedAt:
            connectedAtRaw == null ? null : DateTime.tryParse(connectedAtRaw),
      );
    }

    if (modeName != TelegramAuthMode.bot.name) {
      return const TelegramAuthState();
    }

    final connectedAtRaw = prefs.getString(_connectedAtKey);
    return TelegramAuthState(
      mode: TelegramAuthMode.bot,
      botId: prefs.getInt(_botIdKey),
      botUsername: prefs.getString(_botUsernameKey),
      botName: prefs.getString(_botNameKey),
      connectedAt:
          connectedAtRaw == null ? null : DateTime.tryParse(connectedAtRaw),
    );
  }

  Future<void> _writeState(TelegramAuthState value) async {
    final prefs = KVStoreService.sharedPreferences;
    await prefs.setString(_modeKey, value.mode.name);
    await prefs.setString(_sessionStatusKey, value.sessionStatus.name);
    if (value.botId != null) {
      await prefs.setInt(_botIdKey, value.botId!);
    } else {
      await prefs.remove(_botIdKey);
    }
    if (value.botUsername != null) {
      await prefs.setString(_botUsernameKey, value.botUsername!);
    } else {
      await prefs.remove(_botUsernameKey);
    }
    if (value.botName != null) {
      await prefs.setString(_botNameKey, value.botName!);
    } else {
      await prefs.remove(_botNameKey);
    }
    if (value.phoneNumber != null) {
      await prefs.setString(_phoneNumberKey, value.phoneNumber!);
    } else {
      await prefs.remove(_phoneNumberKey);
    }
    if (value.passwordHint != null) {
      await prefs.setString(_passwordHintKey, value.passwordHint!);
    } else {
      await prefs.remove(_passwordHintKey);
    }
    if (value.connectedAt != null) {
      await prefs.setString(
        _connectedAtKey,
        value.connectedAt!.toIso8601String(),
      );
    } else {
      await prefs.remove(_connectedAtKey);
    }
  }

  Future<String?> _readToken() async {
    try {
      return await EncryptedKvStoreService.storage.read(key: _botTokenKey);
    } catch (_) {
      return KVStoreService.sharedPreferences.getString(_botTokenKey);
    }
  }

  Future<void> _writeToken(String token) async {
    try {
      await EncryptedKvStoreService.storage.write(key: _botTokenKey, value: token);
    } catch (_) {
      await KVStoreService.sharedPreferences.setString(_botTokenKey, token);
    }
  }

  Future<void> _deleteToken() async {
    try {
      await EncryptedKvStoreService.storage.delete(key: _botTokenKey);
    } catch (_) {
      // Secure storage may be unavailable on some desktop/Linux builds.
    } finally {
      await KVStoreService.sharedPreferences.remove(_botTokenKey);
    }
  }
}

class TelegramAuthException implements Exception {
  final String message;

  const TelegramAuthException(this.message);

  @override
  String toString() => message;
}

class _TelegramBot {
  final int id;
  final String? username;
  final String? name;

  const _TelegramBot({
    required this.id,
    this.username,
    this.name,
  });
}

final telegramAuthProvider =
    AsyncNotifierProvider<TelegramAuthNotifier, TelegramAuthState>(
  TelegramAuthNotifier.new,
);
