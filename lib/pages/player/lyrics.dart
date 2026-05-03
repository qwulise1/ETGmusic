import 'package:auto_route/annotations.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:etgmusic/collections/spotube_icons.dart';
import 'package:etgmusic/components/button/back_button.dart';
import 'package:etgmusic/components/image/universal_image.dart';
import 'package:etgmusic/extensions/context.dart';
import 'package:etgmusic/hooks/utils/use_palette_color.dart';
import 'package:etgmusic/models/metadata/metadata.dart';
import 'package:etgmusic/pages/lyrics/plain_lyrics.dart';
import 'package:etgmusic/pages/lyrics/synced_lyrics.dart';
import 'package:etgmusic/provider/audio_player/audio_player.dart';
import 'package:etgmusic/provider/lyrics/synced.dart';

@RoutePage()
class PlayerLyricsPage extends HookConsumerWidget {
  const PlayerLyricsPage({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final playlist = ref.watch(audioPlayerProvider);
    String albumArt = useMemoized(
      () => (playlist.activeTrack?.album.images).asUrlString(
        index: (playlist.activeTrack?.album.images.length ?? 1) - 1,
        placeholder: ImagePlaceholder.albumArt,
      ),
      [playlist.activeTrack?.album.images],
    );
    final selectedIndex = useState(0);
    final palette = usePaletteColor(albumArt, ref);
    final lyricsMap = ref.watch(syncedLyricsMapProvider(playlist.activeTrack));
    final hasOnlyPlainLyrics = lyricsMap.asData?.value.static == true;
    final theme = Theme.of(context);

    useEffect(() {
      if (hasOnlyPlainLyrics) selectedIndex.value = 1;
      return null;
    }, [playlist.activeTrack?.id, hasOnlyPlainLyrics]);

    final baseColor = palette.color;
    final backgroundColor = Color.lerp(
          baseColor,
          theme.colorScheme.background,
          theme.brightness == Brightness.dark ? 0.58 : 0.22,
        ) ??
        baseColor;
    final overlayColor = theme.colorScheme.background.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.44 : 0.2,
    );

    return Scaffold(
      child: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: UniversalImage.imageProvider(albumArt),
            fit: BoxFit.cover,
            opacity: 0.26,
          ),
        ),
        child: ColoredBox(
          color: backgroundColor.withValues(alpha: 0.88),
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        overlayColor,
                        backgroundColor.withValues(alpha: 0.76),
                        theme.colorScheme.background.withValues(alpha: 0.94),
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  playlist.activeTrack?.name ??
                                      "Текст песни",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.typography.large.copyWith(
                                    color: palette.titleTextColor,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  playlist.activeTrack?.artists.asString() ??
                                      "",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.typography.small.copyWith(
                                    color: palette.bodyTextColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const BackButton(icon: SpotubeIcons.angleDown),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: SurfaceCard(
                        padding: const EdgeInsets.all(4),
                        borderRadius: BorderRadius.circular(999),
                        surfaceOpacity: 0.2,
                        child: TabList(
                          index: selectedIndex.value,
                          onChanged: (index) => selectedIndex.value = index,
                          children: [
                            TabItem(child: Text(context.l10n.synced)),
                            TabItem(child: Text(context.l10n.plain)),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: KeyedSubtree(
                          key: ValueKey(selectedIndex.value),
                          child: selectedIndex.value == 0
                              ? SyncedLyrics(
                                  palette: palette,
                                  isModal: true,
                                  defaultTextZoom: 116,
                                )
                              : PlainLyrics(
                                  palette: palette,
                                  isModal: true,
                                  defaultTextZoom: 118,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
