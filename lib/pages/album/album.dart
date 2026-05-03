import 'package:flutter/material.dart' as material;
import 'package:auto_route/auto_route.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';
import 'package:etgmusic/collections/spotube_icons.dart';
import 'package:etgmusic/components/track_presentation/presentation_props.dart';
import 'package:etgmusic/components/track_presentation/track_presentation.dart';
import 'package:etgmusic/extensions/context.dart';
import 'package:etgmusic/models/metadata/metadata.dart';
import 'package:etgmusic/provider/audio_player/audio_player.dart';
import 'package:etgmusic/provider/metadata_plugin/library/albums.dart';
import 'package:etgmusic/provider/metadata_plugin/tracks/album.dart';
import 'package:etgmusic/provider/metadata_plugin/utils/common.dart';
import 'package:etgmusic/services/telegram/telegram_media.dart';

@RoutePage()
class AlbumPage extends HookConsumerWidget {
  static const name = "album";

  final SpotubeSimpleAlbumObject album;
  final String id;
  const AlbumPage({
    super.key,
    @PathParam("id") required this.id,
    required this.album,
  });

  @override
  Widget build(BuildContext context, ref) {
    ref.watch(telegramMediaRevisionProvider);
    final telegramMedia = ref.read(telegramMediaServiceProvider);
    final displayAlbum = telegramMedia.applyAlbumOverride(album);
    final albumArtist = displayAlbum.artists.isEmpty
        ? "ETGmusic"
        : displayAlbum.artists.first.name;
    final albumDescription = [
      if (displayAlbum.releaseDate != null) context.l10n.released,
      if (displayAlbum.releaseDate != null) displayAlbum.releaseDate!,
      albumArtist,
    ].join(" • ");
    final tracks =
        ref.watch(metadataPluginAlbumTracksProvider(displayAlbum.id));
    final tracksNotifier =
        ref.watch(metadataPluginAlbumTracksProvider(displayAlbum.id).notifier);
    final favoriteAlbumsNotifier =
        ref.watch(metadataPluginSavedAlbumsProvider.notifier);
    final isSavedAlbum =
        ref.watch(metadataPluginIsSavedAlbumProvider(displayAlbum.id));
    final isTelegramAlbum = displayAlbum.id.startsWith("telegram:");

    return material.RefreshIndicator.adaptive(
      onRefresh: () async {
        ref.invalidate(metadataPluginAlbumTracksProvider(displayAlbum.id));
        ref.invalidate(metadataPluginIsSavedAlbumProvider(displayAlbum.id));
        ref.invalidate(metadataPluginSavedAlbumsProvider);
      },
      child: TrackPresentation(
        options: TrackPresentationOptions(
          collection: displayAlbum,
          image: displayAlbum.images.asUrlString(
            placeholder: ImagePlaceholder.albumArt,
          ),
          title: displayAlbum.name,
          description: albumDescription,
          tracks: tracks.asData?.value.items ?? [],
          error: tracks.error,
          pagination: PaginationProps(
            hasNextPage: tracks.asData?.value.hasMore ?? false,
            isLoading: tracks.isLoading || tracks.isLoadingNextPage,
            onFetchMore: () async {
              await tracksNotifier.fetchMore();
            },
            onFetchAll: () async {
              return tracksNotifier.fetchAll();
            },
            onRefresh: () async {
              ref.invalidate(metadataPluginAlbumTracksProvider(displayAlbum.id));
            },
          ),
          routePath: "/album/${displayAlbum.id}",
          shareUrl: displayAlbum.externalUri,
          isLiked: isSavedAlbum.asData?.value ?? false,
          owner: albumArtist,
          actions: isTelegramAlbum
              ? [
                  Tooltip(
                    tooltip: TooltipContainer(
                      child: const Text("Редактировать альбом"),
                    ).call,
                    child: IconButton.outline(
                      icon: const Icon(SpotubeIcons.edit),
                      size: ButtonSize.small,
                      onPressed: () async {
                        await _showTelegramAlbumEditDialog(
                          context,
                          ref,
                          displayAlbum,
                        );
                      },
                    ),
                  ),
                  Tooltip(
                    tooltip: TooltipContainer(
                      child: const Text("Удалить альбом"),
                    ).call,
                    child: IconButton.outline(
                      icon: const Icon(SpotubeIcons.trash),
                      size: ButtonSize.small,
                      onPressed: () async {
                        final confirmed = await _confirmDeleteAlbum(context);
                        if (confirmed != true) return;
                        await ref
                            .read(telegramMediaServiceProvider)
                            .deleteAlbum(displayAlbum.id);
                        ref.invalidate(metadataPluginSavedAlbumsProvider);
                        ref.invalidate(
                          metadataPluginAlbumTracksProvider(displayAlbum.id),
                        );
                        if (context.mounted) {
                          context.router.maybePop();
                        }
                      },
                    ),
                  ),
                ]
              : const [],
          onHeart: isTelegramAlbum || isSavedAlbum.asData?.value == null
              ? null
              : () async {
                  if (isSavedAlbum.asData!.value) {
                    await favoriteAlbumsNotifier.removeFavorite([displayAlbum]);
                  } else {
                    await favoriteAlbumsNotifier.addFavorite([displayAlbum]);
                  }
                  return null;
                },
        ),
      ),
    );
  }

  Future<void> _showTelegramAlbumEditDialog(
    BuildContext context,
    WidgetRef ref,
    SpotubeSimpleAlbumObject album,
  ) async {
    final nameController = TextEditingController(text: album.name);
    final coverController = TextEditingController(
      text: album.images.isEmpty ? "" : album.images.first.url,
    );

    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text("Редактировать альбом"),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 10,
                children: [
                  TextField(
                    controller: nameController,
                    placeholder: const Text("Название альбома"),
                  ),
                  TextField(
                    controller: coverController,
                    placeholder: const Text("URL или путь к обложке"),
                  ),
                  Button.outline(
                    leading: const Icon(SpotubeIcons.file),
                    child: const Text("Выбрать фото"),
                    onPressed: () async {
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.image,
                        allowMultiple: false,
                      );
                      final path = result?.files.single.path;
                      if (path != null && path.isNotEmpty) {
                        coverController.text = path;
                      }
                    },
                  ),
                  Text(
                    "Обложка и имя сохраняются локально в ETGmusic. Оригинальный канал или чат Telegram не меняется.",
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

      await ref.read(telegramMediaServiceProvider).updateAlbumMetadata(
            album,
            name: nameController.text,
            coverUrl: coverController.text,
          );
      final updatedTracks =
          await ref.read(telegramMediaServiceProvider).loadTracks();
      final player = ref.read(audioPlayerProvider.notifier);
      for (final track in updatedTracks.where((track) {
        return track.album.id == album.id;
      })) {
        await player.replaceTrack(track);
      }
      ref.invalidate(metadataPluginSavedAlbumsProvider);
      ref.invalidate(metadataPluginAlbumTracksProvider(album.id));

      if (!context.mounted) return;
      showToast(
        context: context,
        location: ToastLocation.topRight,
        builder: (context, overlay) {
          return const SurfaceCard(
            child: Text("Альбом сохранен"),
          );
        },
      );
    } finally {
      nameController.dispose();
      coverController.dispose();
    }
  }

  Future<bool?> _confirmDeleteAlbum(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Удалить альбом?"),
          content: const Text(
            "Треки этого Telegram-альбома будут удалены из локальной библиотеки ETGmusic.",
          ),
          actions: [
            Button.outline(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Отмена"),
            ),
            Button.destructive(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Удалить"),
            ),
          ],
        );
      },
    );
  }
}
