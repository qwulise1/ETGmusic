import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:etgmusic/services/audio_player/audio_player.dart';
import 'package:etgmusic/services/kv_store/kv_store.dart';

class PlayerEqualizerNotifier extends Notifier<List<double>> {
  @override
  List<double> build() {
    final bands = KVStoreService.equalizerBands;
    audioPlayer.setEqualizerBands(bands);
    return bands;
  }

  Future<void> setBand(int index, double gain) async {
    if (index < 0 || index >= state.length) return;
    final updated = [...state];
    updated[index] = gain.clamp(-12, 12).toDouble();
    state = updated;
    await KVStoreService.setEqualizerBands(updated);
    await audioPlayer.setEqualizerBands(updated);
  }

  Future<void> reset() async {
    final updated = List<double>.filled(10, 0);
    state = updated;
    await KVStoreService.setEqualizerBands(updated);
    await audioPlayer.setEqualizerBands(updated);
  }
}

final playerEqualizerProvider =
    NotifierProvider<PlayerEqualizerNotifier, List<double>>(
  PlayerEqualizerNotifier.new,
);
