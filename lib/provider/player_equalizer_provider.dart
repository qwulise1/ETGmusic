import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:etgmusic/services/audio_player/audio_player.dart';
import 'package:etgmusic/services/kv_store/kv_store.dart';

class PlayerEqualizerNotifier extends Notifier<List<double>> {
  Timer? _applyDebounce;
  Future<void> _applyQueue = Future.value();
  int _applyVersion = 0;

  @override
  List<double> build() {
    final bands = KVStoreService.equalizerBands;
    unawaited(_applyBands(bands));
    ref.onDispose(() {
      _applyDebounce?.cancel();
    });
    return bands;
  }

  Future<void> setBand(
    int index,
    double gain, {
    bool applyImmediately = false,
  }) async {
    if (index < 0 || index >= state.length) return;
    final updated = [...state];
    updated[index] = gain.clamp(-12, 12).toDouble();
    state = updated;
    unawaited(KVStoreService.setEqualizerBands(updated));
    if (applyImmediately) {
      await applyNow();
    } else {
      _scheduleApply();
    }
  }

  Future<void> applyNow() async {
    _applyDebounce?.cancel();
    await _applyBands(state);
  }

  Future<void> reset() async {
    final updated = List<double>.filled(10, 0);
    state = updated;
    await KVStoreService.setEqualizerBands(updated);
    await _applyBands(updated);
  }

  void _scheduleApply() {
    _applyDebounce?.cancel();
    _applyDebounce = Timer(const Duration(milliseconds: 260), () {
      unawaited(_applyBands(state));
    });
  }

  Future<void> _applyBands(List<double> bands) {
    final version = ++_applyVersion;
    final snapshot = [...bands];
    _applyQueue = _applyQueue.catchError((_) {}).then((_) async {
      if (version != _applyVersion) return;
      await audioPlayer.setEqualizerBands(snapshot);
    });
    return _applyQueue;
  }
}

final playerEqualizerProvider =
    NotifierProvider<PlayerEqualizerNotifier, List<double>>(
  PlayerEqualizerNotifier.new,
);
