import 'package:flutter/services.dart';
import 'package:etgmusic/utils/platform.dart';

class TelegramSyncNotifications {
  static const _channel =
      MethodChannel("io.qwulise1.etgmusic/telegram_sync");

  static Future<void> requestPermission() async {
    if (!kIsAndroid) return;
    await _channel.invokeMethod<bool>("requestNotificationPermission");
  }

  static Future<void> show({
    required String title,
    required String text,
    int progress = 0,
    int max = 0,
    bool indeterminate = false,
    bool done = false,
  }) async {
    if (!kIsAndroid) return;
    await _channel.invokeMethod<void>("show", {
      "title": title,
      "text": text,
      "progress": progress,
      "max": max,
      "indeterminate": indeterminate,
      "done": done,
    });
  }

  static Future<void> cancel() async {
    if (!kIsAndroid) return;
    await _channel.invokeMethod<void>("cancel");
  }
}
