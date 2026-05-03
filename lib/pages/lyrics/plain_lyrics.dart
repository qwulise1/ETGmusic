import 'package:collection/collection.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';
import 'package:etgmusic/collections/spotube_icons.dart';
import 'package:etgmusic/models/metadata/metadata.dart';
import 'package:etgmusic/modules/lyrics/zoom_controls.dart';
import 'package:etgmusic/components/shimmers/shimmer_lyrics.dart';
import 'package:etgmusic/extensions/constrains.dart';
import 'package:etgmusic/extensions/context.dart';

import 'package:etgmusic/provider/audio_player/audio_player.dart';
import 'package:etgmusic/provider/lyrics/synced.dart';

class PlainLyrics extends HookConsumerWidget {
  final PaletteColor palette;
  final bool? isModal;
  final int defaultTextZoom;
  const PlainLyrics({
    required this.palette,
    this.isModal,
    this.defaultTextZoom = 100,
    super.key,
  });

  @override
  Widget build(BuildContext context, ref) {
    final playlist = ref.watch(audioPlayerProvider);
    final lyricsQuery = ref.watch(syncedLyricsProvider(playlist.activeTrack));
    final mediaQuery = MediaQuery.of(context);
    final typography = Theme.of(context).typography;

    final textZoomLevel = useState<int>(defaultTextZoom);

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isModal != true) ...[
              Center(
                child: Text(
                  playlist.activeTrack?.name ?? "",
                  style: mediaQuery.mdAndUp
                      ? typography.h3
                      : typography.h4.copyWith(
                          color: palette.titleTextColor,
                        ),
                ),
              ),
              Center(
                child: Text(
                  playlist.activeTrack?.artists.asString() ?? "",
                  style: (mediaQuery.mdAndUp ? typography.h4 : typography.large)
                      .copyWith(
                    color: palette.bodyTextColor,
                  ),
                ),
              )
            ],
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    mediaQuery.size.width > 720 ? 48 : 18,
                    18,
                    mediaQuery.size.width > 720 ? 48 : 18,
                    120,
                  ),
                  child: Builder(
                    builder: (context) {
                      if (lyricsQuery.isLoading || lyricsQuery.isRefreshing) {
                        return const ShimmerLyrics();
                      } else if (lyricsQuery.hasError) {
                        return Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                context.l10n.no_lyrics_available,
                                style: typography.large.copyWith(
                                  color: palette.bodyTextColor,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const Gap(26),
                              const Icon(SpotubeIcons.noLyrics, size: 60),
                            ],
                          ),
                        );
                      }

                      final lyrics =
                          lyricsQuery.asData?.value.lyrics.mapIndexed((i, e) {
                        final next = lyricsQuery.asData?.value.lyrics
                            .elementAtOrNull(i + 1);
                        if (next != null &&
                            e.time - next.time >
                                const Duration(milliseconds: 700)) {
                          return "${e.text}\n";
                        }

                        return e.text;
                      }).join("\n");

                      return AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: TextStyle(
                          color: isModal == true
                              ? context.theme.colorScheme.foreground
                              : palette.bodyTextColor,
                          fontSize: 23 * textZoomLevel.value / 100,
                          fontWeight: FontWeight.w800,
                          height: textZoomLevel.value < 70
                              ? 1.45
                              : textZoomLevel.value > 150
                                  ? 1.65
                                  : 1.85,
                        ),
                        child: SelectableText(
                          lyrics == null && playlist.activeTrack == null
                              ? context.l10n.no_tracks_playing
                              : lyrics ?? "",
                          textAlign: TextAlign.start,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.bottomRight,
          child: ZoomControls(
            value: textZoomLevel.value,
            onChanged: (value) => textZoomLevel.value = value,
            min: 50,
            max: 200,
          ),
        ),
      ],
    );
  }
}
