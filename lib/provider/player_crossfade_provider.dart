import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:etgmusic/services/kv_store/kv_store.dart';

class PlayerCrossfadeNotifier extends Notifier<bool> {
  @override
  bool build() => KVStoreService.crossfadePlayback;

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    await KVStoreService.setCrossfadePlayback(enabled);
  }
}

final playerCrossfadeProvider =
    NotifierProvider<PlayerCrossfadeNotifier, bool>(
  PlayerCrossfadeNotifier.new,
);
