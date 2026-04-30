import 'package:dio/dio.dart';
import 'package:riverpod/riverpod.dart';
import 'package:etgmusic/services/dio/dio.dart';
import 'package:etgmusic/services/kv_store/encrypted_kv_store.dart';
import 'package:etgmusic/services/kv_store/kv_store.dart';

enum TelegramAuthMode {
  none,
  bot,
}

class TelegramAuthState {
  final TelegramAuthMode mode;
  final int? botId;
  final String? botUsername;
  final String? botName;
  final DateTime? connectedAt;

  const TelegramAuthState({
    this.mode = TelegramAuthMode.none,
    this.botId,
    this.botUsername,
    this.botName,
    this.connectedAt,
  });

  bool get isConnected => mode != TelegramAuthMode.none;

  String get title {
    if (!isConnected) return "Telegram не подключен";
    final username = botUsername == null ? "" : " @$botUsername";
    return "Подключен бот$username";
  }

  String get subtitle {
    if (!isConnected) {
      return "Подключи бота из @BotFather, добавь его в нужные каналы/группы и ETGmusic сможет использовать этот источник дальше.";
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
  static const _connectedAtKey = "telegram_connected_at";
  static const _botTokenKey = "telegram_bot_token";

  @override
  Future<TelegramAuthState> build() async {
    return _readState();
  }

  Future<void> connectBot(String rawToken) async {
    final token = rawToken.trim();
    if (token.isEmpty) {
      throw ArgumentError("Вставь Bot API token из @BotFather");
    }

    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() async {
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
      return next;
    });
    state = result;
    if (result.hasError) {
      Error.throwWithStackTrace(
        result.error!,
        result.stackTrace ?? StackTrace.current,
      );
    }
  }

  Future<void> disconnect() async {
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() async {
      await _deleteToken();
      await KVStoreService.sharedPreferences.remove(_modeKey);
      await KVStoreService.sharedPreferences.remove(_botIdKey);
      await KVStoreService.sharedPreferences.remove(_botUsernameKey);
      await KVStoreService.sharedPreferences.remove(_botNameKey);
      await KVStoreService.sharedPreferences.remove(_connectedAtKey);
      return const TelegramAuthState();
    });
    state = result;
    if (result.hasError) {
      Error.throwWithStackTrace(
        result.error!,
        result.stackTrace ?? StackTrace.current,
      );
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
    if (value.botId != null) await prefs.setInt(_botIdKey, value.botId!);
    if (value.botUsername != null) {
      await prefs.setString(_botUsernameKey, value.botUsername!);
    }
    if (value.botName != null) await prefs.setString(_botNameKey, value.botName!);
    if (value.connectedAt != null) {
      await prefs.setString(_connectedAtKey, value.connectedAt!.toIso8601String());
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
