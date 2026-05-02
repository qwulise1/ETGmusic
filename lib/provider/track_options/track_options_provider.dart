import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Navigator, TextEditingController;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';
import 'package:etgmusic/collections/routes.dart';
import 'package:etgmusic/collections/routes.gr.dart';
import 'package:etgmusic/components/dialogs/playlist_add_track_dialog.dart';
import 'package:etgmusic/components/dialogs/prompt_dialog.dart';
import 'package:etgmusic/components/dialogs/track_details_dialog.dart';
import 'package:etgmusic/extensions/context.dart';
import 'package:etgmusic/models/database/database.dart';
import 'package:etgmusic/models/metadata/metadata.dart';
import 'package:etgmusic/provider/audio_player/audio_player.dart';
import 'package:etgmusic/provider/blacklist_provider.dart';
import 'package:etgmusic/provider/download_manager_provider.dart';
import 'package:etgmusic/provider/local_tracks/local_tracks_provider.dart';
import 'package:etgmusic/provider/metadata_plugin/core/auth.dart';
import 'package:etgmusic/provider/metadata_plugin/library/playlists.dart';
import 'package:etgmusic/provider/metadata_plugin/library/tracks.dart';
import 'package:etgmusic/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:etgmusic/provider/metadata_plugin/tracks/playlist.dart';
import 'package:etgmusic/services/metadata/errors/exceptions.dart';
import 'package:etgmusic/services/telegram/telegram_media.dart';

enum TrackOptionValue {
  album,
  share,
  addToPlaylist,
  addToQueue,
  removeFromPlaylist,
  removeFromQueue,
  blacklist,
  delete,
  playNext,
  favorite,
  details,
  download,
  startRadio,
  editMetadata,
}

class TrackOptionsActions {
  final Ref ref;
  final SpotubeTrackObject track;

  TrackOptionsActions(this.ref, this.track);

  AudioPlayerNotifier get playback => ref.read(audioPlayerProvider.notifier);
  MetadataPluginSavedTracksNotifier get favoriteTracks =>
      ref.read(metadataPluginSavedTracksProvider.notifier);
  MetadataPluginSavedPlaylistsNotifier get favoritePlaylistsNotifier =>
      ref.read(metadataPluginSavedPlaylistsProvider.notifier);
  DownloadManagerNotifier get downloadManager =>
      ref.read(downloadManagerProvider.notifier);
  BlackListNotifier get blacklist => ref.read(blacklistProvider.notifier);

  bool get isTelegramTrack => track.id.startsWith("telegram:");

  void actionShare(BuildContext context) {
    Clipboard.setData(ClipboardData(text: track.externalUri)).then((_) {
      if (context.mounted) {
        showToast(
          context: rootNavigatorKey.currentContext!,
          location: ToastLocation.topRight,
          builder: (context, overlay) {
            return SurfaceCard(
              child: Text(
                context.l10n.copied_to_clipboard(track.externalUri),
                textAlign: TextAlign.center,
              ),
            );
          },
        );
      }
    });
  }

  Future<void> actionAddToPlaylist(
    BuildContext context,
    String? playlistId,
  ) async {
    /// showDialog doesn't work for some reason. So we have to
    /// manually push a Dialog Route in the Navigator to get it working
    await showDialog(
      context: context,
      builder: (context) {
        return PlaylistAddTrackDialog(
          tracks: [track],
          openFromPlaylist: playlistId,
        );
      },
    );
  }

  Future<void> actionStartRadio(BuildContext context) async {
    final playback = ref.read(audioPlayerProvider.notifier);
    final playlist = ref.read(audioPlayerProvider);
    final metadataPlugin = await ref.read(metadataPluginProvider.future);

    if (metadataPlugin == null) {
      throw MetadataPluginException.noDefaultMetadataPlugin();
    }

    final tracks = await metadataPlugin.track.radio(track.id);

    bool replaceQueue = false;

    if (context.mounted && playlist.tracks.isNotEmpty) {
      replaceQueue = await showPromptDialog(
        context: context,
        title: context.l10n.how_to_start_radio,
        message: context.l10n.replace_queue_question,
        okText: context.l10n.replace,
        cancelText: context.l10n.add_to_queue,
      );
    }

    if (replaceQueue || playlist.tracks.isEmpty) {
      await playback.stop();
      await playback.load([track], autoPlay: true);

      // we don't have to add those tracks as useEndlessPlayback will do it for us
      return;
    } else {
      await playback.addTrack(track);
    }

    await playback.addTracks(
      tracks.toList()
        ..removeWhere((e) {
          final isDuplicate = playlist.tracks.any((t) => t.id == e.id);
          return e.id == track.id || isDuplicate;
        }),
    );
  }

  Future<void> actionEditMetadata(BuildContext context) async {
    if (!isTelegramTrack) return;

    final nameController = TextEditingController(text: track.name);
    final artistController = TextEditingController(
      text: track.artists.map((artist) => artist.name).join(", "),
    );
    final albumController = TextEditingController(text: track.album.name);
    final coverController = TextEditingController(
      text: track.album.images.firstOrNull?.url ?? "",
    );

    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text("Редактировать трек"),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 10,
                children: [
                  TextField(
                    controller: nameController,
                    placeholder: const Text("Точное название трека"),
                  ),
                  TextField(
                    controller: artistController,
                    placeholder: const Text("Исполнитель"),
                  ),
                  TextField(
                    controller: albumController,
                    placeholder: const Text("Альбом / источник"),
                  ),
                  TextField(
                    controller: coverController,
                    placeholder: const Text("URL обложки, если нужна вручную"),
                  ),
                  Text(
                    "Эти данные используются для поиска текста на LRCLib/Genius и отображения в ETGmusic. Оригинал Telegram не меняется.",
                    style: context.theme.typography.xSmall.copyWith(
                      color: context.theme.colorScheme.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              Button.outline(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Отмена"),
              ),
              Button.primary(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Сохранить"),
              ),
            ],
          );
        },
      );

      if (saved != true) return;

      final updatedTrack =
          await ref.read(telegramMediaServiceProvider).updateTrackMetadata(
                track.id,
                name: nameController.text,
                artist: artistController.text,
                album: albumController.text,
                coverUrl: coverController.text,
              );
      await ref.read(audioPlayerProvider.notifier).replaceTrack(updatedTrack);
      ref.invalidate(metadataPluginSavedTracksProvider);
      ref.invalidate(metadataPluginPlaylistTracksProvider("telegram-library"));

      if (!context.mounted) return;
      showToast(
        context: context,
        location: ToastLocation.topRight,
        builder: (context, overlay) {
          return const SurfaceCard(
            child: Text("Метаданные Telegram-трека сохранены"),
          );
        },
      );
    } finally {
      nameController.dispose();
      artistController.dispose();
      albumController.dispose();
      coverController.dispose();
    }
  }

  Future<void> action(
    BuildContext context,
    TrackOptionValue value,
    String? playlistId,
  ) async {
    switch (value) {
      case TrackOptionValue.album:
        await context.navigateTo(
          AlbumRoute(id: track.album.id, album: track.album),
        );
        break;
      case TrackOptionValue.delete:
        await File((track as SpotubeLocalTrackObject).path).delete();
        ref.invalidate(localTracksProvider);
        break;
      case TrackOptionValue.addToQueue:
        await playback.addTrack(track);
        if (context.mounted) {
          showToast(
            context: context,
            location: ToastLocation.topRight,
            builder: (context, overlay) {
              return SurfaceCard(
                child: Text(
                  context.l10n.added_track_to_queue(track.name),
                  textAlign: TextAlign.center,
                ),
              );
            },
          );
        }
        break;
      case TrackOptionValue.playNext:
        await playback.addTracksAtFirst([track]);

        if (context.mounted) {
          showToast(
            context: context,
            location: ToastLocation.topRight,
            builder: (context, overlay) {
              return SurfaceCard(
                child: Text(
                  context.l10n.track_will_play_next(track.name),
                  textAlign: TextAlign.center,
                ),
              );
            },
          );
        }
        break;
      case TrackOptionValue.removeFromQueue:
        playback.removeTrack(track.id);

        if (context.mounted) {
          showToast(
            context: context,
            location: ToastLocation.topRight,
            builder: (context, overlay) {
              return SurfaceCard(
                child: Text(
                  context.l10n.removed_track_from_queue(
                    track.name,
                  ),
                  textAlign: TextAlign.center,
                ),
              );
            },
          );
        }
        break;
      case TrackOptionValue.favorite:
        final isLikedTrack = await ref.read(
          metadataPluginIsSavedTrackProvider(track.id).future,
        );

        if (isLikedTrack) {
          await favoriteTracks.removeFavorite([track]);
        } else {
          await favoriteTracks.addFavorite([track]);
        }
        break;
      case TrackOptionValue.addToPlaylist:
        actionAddToPlaylist(context, playlistId);
        break;
      case TrackOptionValue.removeFromPlaylist:
        favoritePlaylistsNotifier.removeTracks(playlistId ?? "", [track.id]);
        break;
      case TrackOptionValue.blacklist:
        final isBlacklisted = blacklist.contains(track);
        if (isBlacklisted == true) {
          await ref.read(blacklistProvider.notifier).remove(track.id);
        } else {
          await ref.read(blacklistProvider.notifier).add(
                BlacklistTableCompanion.insert(
                  name: track.name,
                  elementId: track.id,
                  elementType: BlacklistedType.track,
                ),
              );
        }
        break;
      case TrackOptionValue.share:
        actionShare(context);
        break;
      case TrackOptionValue.details:
        if (track is! SpotubeFullTrackObject) break;
        showDialog(
          context: context,
          builder: (context) => ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: TrackDetailsDialog(track: track as SpotubeFullTrackObject),
          ),
        );
        break;
      case TrackOptionValue.download:
        if (track is SpotubeLocalTrackObject) break;
        downloadManager.addToQueue(track as SpotubeFullTrackObject);
        break;
      case TrackOptionValue.startRadio:
        actionStartRadio(context);
        break;
      case TrackOptionValue.editMetadata:
        await actionEditMetadata(context);
        break;
    }
  }
}

typedef TrackOptionFlags = ({
  bool isInQueue,
  bool isBlacklisted,
  bool isInDownloadQueue,
  bool isActiveTrack,
  bool isAuthenticated,
  bool isLiked,
  DownloadTask? downloadTask,
});

final trackOptionActionsProvider =
    Provider.family<TrackOptionsActions, SpotubeTrackObject>(
  (ref, track) => TrackOptionsActions(ref, track),
);

final trackOptionsStateProvider =
    Provider.family<TrackOptionFlags, SpotubeTrackObject>((ref, track) {
  ref.watch(downloadManagerProvider);
  ref.watch(blacklistProvider);

  final playlist = ref.watch(audioPlayerProvider);
  final authenticated = ref.watch(metadataPluginAuthenticatedProvider);
  final downloadManager = ref.watch(downloadManagerProvider.notifier);
  final blacklist = ref.watch(blacklistProvider.notifier);
  final isBlacklisted = blacklist.contains(track);
  final isSavedTrack = ref.watch(metadataPluginIsSavedTrackProvider(track.id));

  final downloadTask = playlist.activeTrack?.id == null
      ? null
      : downloadManager.getTaskByTrackId(playlist.activeTrack!.id);
  final isInDownloadQueue = playlist.activeTrack == null ||
          playlist.activeTrack! is SpotubeLocalTrackObject
      ? false
      : const [
          DownloadStatus.queued,
          DownloadStatus.downloading,
        ].contains(downloadTask?.status);

  return (
    isInQueue: playlist.containsTrack(track),
    isBlacklisted: isBlacklisted,
    isInDownloadQueue: isInDownloadQueue,
    isActiveTrack: playlist.activeTrack?.id == track.id,
    isAuthenticated: authenticated.asData?.value ?? false,
    isLiked: isSavedTrack.asData?.value ?? false,
    downloadTask: downloadTask,
  );
});
