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
    final albumArtSize = (mediaQuery.smAndDown ? mediaQuery.width - 48 : 360)
        .clamp(240, 380)
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
          headers: [
            SafeArea(
              bottom: false,
              child: TitleBar(
                surfaceOpacity: 0,
                surfaceBlur: 0,
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
                        icon: const Icon(SpotubeIcons.info),
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
                                    });
                              },
                      ),
                    )
                ],
              ),
            ),
          ],
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
            child: SingleChildScrollView(
              controller: scrollController,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 14, 16, 22),
                    padding: const EdgeInsets.all(10),
                    constraints: BoxConstraints(
                      maxHeight: albumArtSize,
                      maxWidth: albumArtSize,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(34),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          theme.colorScheme.primary.withAlpha(70),
                          theme.colorScheme.secondary.withAlpha(34),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(90),
                          spreadRadius: 1,
                          blurRadius: 28,
                          offset: Offset.zero,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(26),
                      child: UniversalImage(
                        path: albumArt,
                        placeholder: Assets.images.albumPlaceholder.path,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(18),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.card.withAlpha(210),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: theme.colorScheme.border.withAlpha(140),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AutoSizeText(
                          currentActiveTrack?.name ?? context.l10n.not_playing,
                          style: const TextStyle(fontSize: 22),
                          maxFontSize: 22,
                          maxLines: 1,
                          textAlign: TextAlign.start,
                        ),
                        if (isLocalTrack)
                          Text(
                            currentActiveTrack.artists.asString(),
                            style: theme.typography.normal
                                .copyWith(fontWeight: FontWeight.bold),
                          )
                        else
                          ArtistLink(
                            artists: currentActiveTrack?.artists ?? [],
                            textStyle: theme.typography.normal
                                .copyWith(fontWeight: FontWeight.bold),
                            onRouteChange: (route) {
                              panelController.close();
                              context.router.navigateNamed(route);
                            },
                            onOverflowArtistClick: () => context.navigateTo(
                              TrackRoute(
                                trackId: currentActiveTrack!.id,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  const PlayerControls(),
                  const SizedBox(height: 25),
                  const PlayerActions(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    showQueue: false,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      const SizedBox(width: 10),
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
                      const SizedBox(width: 10),
                    ],
                  ),
                  const SizedBox(height: 25),
                  if (showVolumeControl) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Consumer(builder: (context, ref, _) {
                        final volume = ref.watch(volumeProvider);
                        return VolumeSlider(
                          fullWidth: true,
                          value: volume,
                          onChanged: (value) {
                            ref.read(volumeProvider.notifier).setVolume(value);
                          },
                        );
                      }),
                    ),
                    const Gap(25),
                  ],
                  OutlineBadge(
                    style: const ButtonStyle.outline(
                      size: ButtonSize.normal,
                      density: ButtonDensity.dense,
                      shape: ButtonShape.rectangle,
                    ).copyWith(
                      textStyle: (context, states, value) {
                        return value.copyWith(fontWeight: FontWeight.w500);
                      },
                    ),
                    leading: const Icon(SpotubeIcons.lightningOutlined),
                    child: Text(qualityLabel),
                  )
                ],
              ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
