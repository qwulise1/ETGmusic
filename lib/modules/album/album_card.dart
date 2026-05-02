import 'package:auto_route/auto_route.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:etgmusic/collections/routes.gr.dart';
import 'package:etgmusic/components/dialogs/select_device_dialog.dart';
import 'package:etgmusic/components/playbutton_view/playbutton_card.dart';
import 'package:etgmusic/components/playbutton_view/playbutton_tile.dart';
import 'package:etgmusic/extensions/context.dart';
import 'package:etgmusic/models/connect/connect.dart';
import 'package:etgmusic/models/metadata/metadata.dart';
import 'package:etgmusic/provider/audio_player/querying_track_info.dart';
import 'package:etgmusic/provider/connect/connect.dart';
import 'package:etgmusic/provider/history/history.dart';
import 'package:etgmusic/provider/audio_player/audio_player.dart';
import 'package:etgmusic/provider/metadata_plugin/tracks/album.dart';
import 'package:etgmusic/services/audio_player/audio_player.dart';
import 'package:etgmusic/services/telegram/telegram_media.dart';

extension FormattedAlbumType on SpotubeAlbumType {
  String get formatted => name.replaceFirst(name[0], name[0].toUpperCase());
}

class AlbumCard extends HookConsumerWidget {
  final SpotubeSimpleAlbumObject album;
  final bool _isTile;
  const AlbumCard(
    this.album, {
    super.key,
  }) : _isTile = false;

  const AlbumCard.tile(
    this.album, {
    super.key,
  }) : _isTile = true;

  @override
  Widget build(BuildContext context, ref) {
    ref.watch(telegramMediaRevisionProvider);
    final displayAlbum =
        ref.read(telegramMediaServiceProvider).applyAlbumOverride(album);
    final playlist = ref.watch(audioPlayerProvider);
    final playing =
        useStream(audioPlayer.playingStream).data ?? audioPlayer.isPlaying;
    final playlistNotifier = ref.watch(audioPlayerProvider.notifier);
    final historyNotifier = ref.read(playbackHistoryActionsProvider);
    final isFetchingActiveTrack = ref.watch(queryingTrackInfoProvider);

    final isPlaylistPlaying = useMemoized<bool>(
      () => playlist.containsCollection(displayAlbum.id),
      [playlist, displayAlbum.id],
    );

    final updating = useState(false);

    final fetchAllTrack = useCallback(() async {
      await ref.read(metadataPluginAlbumTracksProvider(displayAlbum.id).future);
      return ref
          .read(metadataPluginAlbumTracksProvider(displayAlbum.id).notifier)
          .fetchAll();
    }, [displayAlbum.id, ref]);

    final imageUrl = useMemoized(
      () => displayAlbum.images.from200PxTo300PxOrSmallestImage(
        ImagePlaceholder.collection,
      ),
      [displayAlbum.images],
    );

    final isLoading =
        (isPlaylistPlaying && isFetchingActiveTrack) || updating.value;
    final description =
        "${displayAlbum.albumType.name} • ${displayAlbum.artists.asString()}";

    final onTap = useCallback(() {
      context.navigateTo(AlbumRoute(id: displayAlbum.id, album: displayAlbum));
    }, [context, displayAlbum]);

    final onPlaybuttonPressed = useCallback(() async {
      updating.value = true;
      try {
        if (isPlaylistPlaying) {
          return playing ? audioPlayer.pause() : audioPlayer.resume();
        }

        final fetchedTracks = await fetchAllTrack();

        if (fetchedTracks.isEmpty || !context.mounted) return;

        final isRemoteDevice = await showSelectDeviceDialog(context, ref);
        if (isRemoteDevice == null) return;
        if (isRemoteDevice) {
          final remotePlayback = ref.read(connectProvider.notifier);
          await remotePlayback.load(
            WebSocketLoadEventData.album(
              tracks: fetchedTracks,
              collection: displayAlbum,
            ),
          );
        } else {
          await playlistNotifier.load(fetchedTracks, autoPlay: true);
          playlistNotifier.addCollection(displayAlbum.id);
          historyNotifier.addAlbums([displayAlbum]);
        }
      } finally {
        updating.value = false;
      }
    }, [
      isPlaylistPlaying,
      playing,
      audioPlayer,
      fetchAllTrack,
      context,
      ref,
      playlistNotifier,
      displayAlbum,
      historyNotifier,
      updating
    ]);

    final onAddToQueuePressed = useCallback(() async {
      if (isPlaylistPlaying) {
        return;
      }

      updating.value = true;
      try {
        final fetchedTracks = await fetchAllTrack();

        if (fetchedTracks.isEmpty) return;
        playlistNotifier.addTracks(fetchedTracks);
        playlistNotifier.addCollection(displayAlbum.id);
        historyNotifier.addAlbums([displayAlbum]);
        if (context.mounted) {
          showToast(
            context: context,
            builder: (context, overlay) {
              return SurfaceCard(
                child: Basic(
                  content: Text(
                    context.l10n.added_to_queue(fetchedTracks.length),
                  ),
                  trailing: Button.outline(
                    child: Text(context.l10n.undo),
                    onPressed: () {
                      playlistNotifier
                          .removeTracks(fetchedTracks.map((e) => e.id));
                    },
                  ),
                ),
              );
            },
          );
        }
      } finally {
        updating.value = false;
      }
    }, [
      isPlaylistPlaying,
      updating.value,
      fetchAllTrack,
      playlistNotifier,
      displayAlbum.id,
      historyNotifier,
      displayAlbum,
      context
    ]);

    if (_isTile) {
      return PlaybuttonTile(
        imageUrl: imageUrl,
        isPlaying: isPlaylistPlaying,
        isLoading: isLoading,
        title: displayAlbum.name,
        description: description,
        onTap: onTap,
        onPlaybuttonPressed: onPlaybuttonPressed,
        onAddToQueuePressed: onAddToQueuePressed,
      );
    }

    return PlaybuttonCard(
      imageUrl: imageUrl,
      isPlaying: isPlaylistPlaying,
      isLoading: isLoading,
      title: displayAlbum.name,
      description: description,
      onTap: onTap,
      onPlaybuttonPressed: onPlaybuttonPressed,
      onAddToQueuePressed: onAddToQueuePressed,
    );
  }
}
