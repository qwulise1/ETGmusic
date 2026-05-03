import 'package:auto_route/auto_route.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';

import 'package:etgmusic/collections/assets.gen.dart';
import 'package:etgmusic/collections/routes.gr.dart';
import 'package:etgmusic/collections/spotube_icons.dart';
import 'package:etgmusic/components/framework/app_pop_scope.dart';
import 'package:etgmusic/models/metadata/metadata.dart';
import 'package:etgmusic/modules/player/player_actions.dart';
import 'package:etgmusic/modules/player/player_controls.dart';
import 'package:etgmusic/modules/player/volume_slider.dart';
import 'package:etgmusic/components/dialogs/track_details_dialog.dart';
import 'package:etgmusic/components/links/artist_link.dart';
import 'package:etgmusic/components/titlebar/titlebar.dart';
import 'package:etgmusic/components/image/universal_image.dart';
import 'package:etgmusic/extensions/constrains.dart';
import 'package:etgmusic/extensions/context.dart';
import 'package:etgmusic/modules/root/spotube_navigation_bar.dart';
import 'package:etgmusic/provider/audio_player/audio_player.dart';
import 'package:etgmusic/provider/metadata_plugin/audio_source/quality_label.dart';
import 'package:etgmusic/provider/player_volume_control_provider.dart';
import 'package:etgmusic/provider/server/active_track_sources.dart';
import 'package:etgmusic/provider/volume_provider.dart';
import 'package:etgmusic/services/audio_player/audio_player.dart';
import 'package:etgmusic/services/kv_store/kv_store.dart';

class PlayerView extends HookConsumerWidget {
  final PanelController panelController;
  final ScrollController scrollController;
  const PlayerView({
    super.key,
    required this.panelController,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context, ref) {
    final theme = Theme.of(context);
    final sourcedCurrentTrack = ref.watch(activeTrackSourcesProvider);
    final currentActiveTrack =
        ref.watch(audioPlayerProvider.select((s) => s.activeTrack));
    final currentActiveTrackSource = sourcedCurrentTrack.asData?.value?.source;
    final isLocalTrack = currentActiveTrack is SpotubeLocalTrackObject;
    final mediaQuery = MediaQuery.sizeOf(context);
    final qualityLabel = ref.watch(audioSourceQualityLabelProvider);
    final showVolumeControl = ref.watch(playerVolumeControlProvider);
    final albumArtSize = (mediaQuery.smAndDown ? mediaQuery.width - 36 : 420)
        .clamp(280, 520)
        .toDouble();

    final shouldHide = useState(true);

    ref.listen(navigationPanelHeight, (_, height) {
      shouldHide.value = height.ceil() == 50;
    });

    if (shouldHide.value) {
      return const SizedBox();
    }

    useEffect(() {
      if (mediaQuery.lgAndUp) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          panelController.close();
        });
      }
      return null;
    }, [mediaQuery.lgAndUp]);

    String albumArt = useMemoized(
      () => (currentActiveTrack?.album.images).asUrlString(
        placeholder: ImagePlaceholder.albumArt,
      ),
      [currentActiveTrack?.album.images],
    );

    useEffect(() {
      for (final renderView in WidgetsBinding.instance.renderViews) {
        renderView.automaticSystemUiAdjustment = false;
      }

      return () {
        for (final renderView in WidgetsBinding.instance.renderViews) {
          renderView.automaticSystemUiAdjustment = true;
        }
      };
    }, [panelController.isAttached && panelController.isPanelOpen]);

    return AppPopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        await panelController.close();
      },
      child: SurfaceCard(
        borderWidth: 0,
        surfaceOpacity: 0.82,
        padding: EdgeInsets.zero,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          headers: const [],
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  theme.colorScheme.primary.withAlpha(34),
                  theme.colorScheme.background,
                ],
              ),
            ),
            child: Column(
              children: [
                SafeArea(
                  bottom: false,
                  child: TitleBar(
                    surfaceOpacity: 0,
                    surfaceBlur: 0,
                    title: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "ИЗ ПЛЕЙЛИСТА",
                          style: theme.typography.xSmall.copyWith(
                            color: theme.colorScheme.mutedForeground,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                        Text(
                          currentActiveTrack?.album.name ?? "ETGmusic",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.typography.xSmall.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    leading: [
                      IconButton.ghost(
                        size: const ButtonSize(1.2),
                        icon: const Icon(SpotubeIcons.angleDown),
                        onPressed: panelController.close,
                      )
                    ],
                    trailing: [
                      if (!isLocalTrack)
                        Tooltip(
                          tooltip: TooltipContainer(
                            child: Text(context.l10n.details),
                          ).call,
                          child: IconButton.ghost(
                            size: const ButtonSize(1.2),
                            icon: const Icon(SpotubeIcons.moreVertical),
                            onPressed: currentActiveTrackSource == null
                                ? null
                                : () {
                                    showDialog(
                                      context: context,
                                      builder: (context) {
                                        return TrackDetailsDialog(
                                          track: currentActiveTrack
                                              as SpotubeFullTrackObject,
                                        );
                                      },
                                    );
                                  },
                          ),
                        )
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        18,
                        mediaQuery.smAndDown ? 28 : 24,
                        18,
                        30,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                    Center(
                      child: GestureDetector(
                        onHorizontalDragEnd: (details) {
                          final velocity =
                              details.primaryVelocity ?? 0;
                          if (velocity.abs() < 180) return;
                          if (velocity < 0) {
                            if (KVStoreService.crossfadePlayback) {
                              audioPlayer.smoothSkipToNext();
                            } else {
                              audioPlayer.skipToNext();
                            }
                          } else {
                            if (KVStoreService.crossfadePlayback) {
                              audioPlayer.smoothSkipToPrevious();
                            } else {
                              audioPlayer.skipToPrevious();
                            }
                          }
                        },
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 460),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) {
                            final curved = CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                            );
                            return FadeTransition(
                              opacity: curved,
                              child: ScaleTransition(
                                scale: Tween<double>(begin: 0.97, end: 1)
                                    .animate(curved),
                                child: child,
                              ),
                            );
                          },
                          child: Container(
                            key: ValueKey(currentActiveTrack?.id ?? albumArt),
                            constraints: BoxConstraints.tightFor(
                              width: albumArtSize,
                              height: albumArtSize,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withAlpha(120),
                                  blurRadius: 34,
                                  offset: const Offset(0, 22),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: UniversalImage(
                                path: albumArt,
                                placeholder:
                                    Assets.images.albumPlaceholder.path,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 54),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AutoSizeText(
                                currentActiveTrack?.name ??
                                    context.l10n.not_playing,
                                style: theme.typography.large.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                                maxFontSize: 22,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              if (isLocalTrack)
                                Text(
                                  (currentActiveTrack
                                          as SpotubeLocalTrackObject)
                                      .artists
                                      .asString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.typography.small.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color:
                                        theme.colorScheme.mutedForeground,
                                  ),
                                )
                              else
                                ArtistLink(
                                  artists: currentActiveTrack?.artists ?? [],
                                  textStyle:
                                      theme.typography.small.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color:
                                        theme.colorScheme.mutedForeground,
                                  ),
                                  onRouteChange: (route) {
                                    panelController.close();
                                    context.router.navigateNamed(route);
                                  },
                                  onOverflowArtistClick: () =>
                                      context.navigateTo(
                                    TrackRoute(
                                      trackId: currentActiveTrack!.id,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const PlayerControls(),
                    const SizedBox(height: 14),
                    const Align(
                      alignment: Alignment.centerRight,
                      child: PlayerActions(
                        mainAxisAlignment: MainAxisAlignment.end,
                        showQueue: false,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlineButton(
                            leading: const Icon(SpotubeIcons.queue),
                            child: Text(context.l10n.queue),
                            onPressed: () {
                              context.pushRoute(const PlayerQueueRoute());
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlineButton(
                            leading: const Icon(SpotubeIcons.music),
                            child: Text(context.l10n.lyrics),
                            onPressed: () {
                              context.pushRoute(const PlayerLyricsRoute());
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (showVolumeControl) ...[
                      Consumer(builder: (context, ref, _) {
                        final volume = ref.watch(volumeProvider);
                        return VolumeSlider(
                          fullWidth: true,
                          value: volume,
                          onChanged: (value) {
                            ref.read(volumeProvider.notifier).setVolume(value);
                          },
                        );
                      }),
                      const Gap(18),
                    ],
                    Center(
                      child: OutlineBadge(
                        style: const ButtonStyle.outline(
                          size: ButtonSize.normal,
                          density: ButtonDensity.dense,
                          shape: ButtonShape.rectangle,
                        ).copyWith(
                          textStyle: (context, states, value) {
                            return value.copyWith(fontWeight: FontWeight.w500);
                          },
                        ),
                        leading:
                            const Icon(SpotubeIcons.lightningOutlined),
                        child: Text(qualityLabel),
                      ),
                    ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
