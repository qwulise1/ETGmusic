import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:etgmusic/models/metadata/metadata.dart';
import 'package:etgmusic/provider/audio_player/audio_player.dart';
import 'package:etgmusic/provider/server/sourced_track_provider.dart';
import 'package:etgmusic/services/sourced_track/sourced_track.dart';

final activeTrackSourcesProvider = FutureProvider<
    ({
      SourcedTrack? source,
      SourcedTrackNotifier? notifier,
      SpotubeTrackObject track,
    })?>((ref) async {
  final audioPlayerState = ref.watch(audioPlayerProvider);

  if (audioPlayerState.activeTrack == null) {
    return null;
  }

  if (audioPlayerState.activeTrack is SpotubeLocalTrackObject) {
    return (
      source: null,
      notifier: null,
      track: audioPlayerState.activeTrack!,
    );
  }

  final sourcedTrack = await ref.watch(
    sourcedTrackProvider(
      audioPlayerState.activeTrack! as SpotubeFullTrackObject,
    ).future,
  );
  final sourcedTrackNotifier = ref.watch(
    sourcedTrackProvider(
      audioPlayerState.activeTrack! as SpotubeFullTrackObject,
    ).notifier,
  );

  return (
    source: sourcedTrack,
    track: audioPlayerState.activeTrack!,
    notifier: sourcedTrackNotifier,
  );
});
