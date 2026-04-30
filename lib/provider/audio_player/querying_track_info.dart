import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:etgmusic/models/metadata/metadata.dart';
import 'package:etgmusic/provider/audio_player/audio_player.dart';
import 'package:etgmusic/provider/server/sourced_track_provider.dart';

final queryingTrackInfoProvider = Provider<bool>((ref) {
  final audioPlayer = ref.watch(audioPlayerProvider);

  if (audioPlayer.activeTrack == null) {
    return false;
  }

  if (audioPlayer.activeTrack is! SpotubeFullTrackObject) {
    return false;
  }

  return ref
      .watch(
        sourcedTrackProvider(
            audioPlayer.activeTrack! as SpotubeFullTrackObject),
      )
      .isLoading;
});
