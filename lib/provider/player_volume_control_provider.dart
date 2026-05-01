import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:etgmusic/services/kv_store/kv_store.dart';

class PlayerVolumeControlNotifier extends Notifier<bool> {
  @override
  bool build() => KVStoreService.showPlayerVolumeControl;

  Future<void> setVisible(bool visible) async {
    state = visible;
    await KVStoreService.setShowPlayerVolumeControl(visible);
  }
}

final playerVolumeControlProvider =
    NotifierProvider<PlayerVolumeControlNotifier, bool>(
  PlayerVolumeControlNotifier.new,
);
