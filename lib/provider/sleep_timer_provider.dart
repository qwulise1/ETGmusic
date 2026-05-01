import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:etgmusic/services/audio_player/audio_player.dart';
import 'package:etgmusic/services/logger/logger.dart';

class SleepTimerNotifier extends StateNotifier<Duration?> {
  SleepTimerNotifier() : super(null);

  Timer? _ticker;
  DateTime? _endsAt;

  void setSleepTimer(Duration duration) {
    if (duration <= Duration.zero) {
      cancelSleepTimer();
      return;
    }

    _ticker?.cancel();
    _endsAt = DateTime.now().add(duration);
    state = duration;

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
      final endsAt = _endsAt;
      if (endsAt == null) return;

      final remaining = endsAt.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        await _finishTimer();
      } else {
        state = remaining;
      }
    });
  }

  void cancelSleepTimer() {
    state = null;
    _endsAt = null;
    _ticker?.cancel();
  }

  Future<void> _finishTimer() async {
    state = null;
    _endsAt = null;
    _ticker?.cancel();

    try {
      await audioPlayer.pause();
    } catch (e, stackTrace) {
      AppLogger.reportError(e, stackTrace);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

final sleepTimerProvider = StateNotifierProvider<SleepTimerNotifier, Duration?>(
  (ref) => SleepTimerNotifier(),
);
