import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';

import 'package:etgmusic/collections/routes.gr.dart';
import 'package:etgmusic/collections/spotube_icons.dart';
import 'package:etgmusic/components/heart_button/heart_button.dart';
import 'package:etgmusic/extensions/constrains.dart';
import 'package:etgmusic/extensions/context.dart';
import 'package:etgmusic/extensions/duration.dart';
import 'package:etgmusic/models/metadata/metadata.dart';
import 'package:etgmusic/modules/player/player_queue.dart';
import 'package:etgmusic/modules/player/sibling_tracks_sheet.dart';
import 'package:etgmusic/modules/player/volume_slider.dart';
import 'package:etgmusic/provider/audio_player/audio_player.dart';
import 'package:etgmusic/provider/download_manager_provider.dart';
import 'package:etgmusic/provider/local_tracks/local_tracks_provider.dart';
import 'package:etgmusic/provider/metadata_plugin/core/auth.dart';
import 'package:etgmusic/provider/player_crossfade_provider.dart';
import 'package:etgmusic/provider/player_equalizer_provider.dart';
import 'package:etgmusic/provider/sleep_timer_provider.dart';
import 'package:etgmusic/provider/user_preferences/user_preferences_provider.dart';
import 'package:etgmusic/provider/volume_provider.dart';
import 'package:etgmusic/services/share/track_file_share.dart';

class PlayerActions extends HookConsumerWidget {
  final MainAxisAlignment mainAxisAlignment;
  final bool floatingQueue;
  final bool showQueue;
  final List<Widget>? extraActions;

  const PlayerActions({
    this.mainAxisAlignment = MainAxisAlignment.center,
    this.floatingQueue = true,
    this.showQueue = true,
    this.extraActions,
    super.key,
  });

  @override
  Widget build(BuildContext context, ref) {
    final playlist = ref.watch(audioPlayerProvider);

    return Row(
      mainAxisAlignment: mainAxisAlignment,
      children: [
        if (showQueue)
          Tooltip(
            tooltip: TooltipContainer(child: Text(context.l10n.queue)).call,
            child: IconButton.ghost(
              icon: const Icon(SpotubeIcons.queue),
              enabled: playlist.activeTrack != null,
              onPressed: () => _openQueueDrawer(context),
            ),
          ),
        Tooltip(
          tooltip: TooltipContainer(child: const Text("Настройки плеера")).call,
          child: IconButton.ghost(
            icon: const Icon(SpotubeIcons.settings),
            enabled: playlist.activeTrack != null,
            onPressed: playlist.activeTrack == null
                ? null
                : () => _openPlayerActionsOverlay(
                      context,
                      floatingQueue: floatingQueue,
                    ),
          ),
        ),
        ...(extraActions ?? []),
      ],
    );
  }
}

class _PlayerActionsSheet extends HookConsumerWidget {
  final BuildContext rootContext;
  final VoidCallback close;
  final bool floatingQueue;

  const _PlayerActionsSheet({
    required this.rootContext,
    required this.close,
    required this.floatingQueue,
  });

  @override
  Widget build(BuildContext context, ref) {
    final theme = Theme.of(context);
    final playlist = ref.watch(audioPlayerProvider);
    final activeTrack = playlist.activeTrack;
    final fullTrack = activeTrack is SpotubeFullTrackObject ? activeTrack : null;
    final isLocalTrack = activeTrack is SpotubeLocalTrackObject;
    final downloader = ref.watch(downloadManagerProvider.notifier);
    final localTracks = ref.watch(localTracksProvider).value;
    final authenticated = ref.watch(metadataPluginAuthenticatedProvider);
    final preferences = ref.watch(userPreferencesProvider);
    final preferencesNotifier = ref.watch(userPreferencesProvider.notifier);
    final crossfade = ref.watch(playerCrossfadeProvider);
    final crossfadeNotifier = ref.watch(playerCrossfadeProvider.notifier);
    final volume = ref.watch(volumeProvider);
    final sleepTimer = ref.watch(sleepTimerProvider);
    final sleepTimerNotifier = ref.watch(sleepTimerProvider.notifier);

    final isInDownloadQueue = useMemoized(() {
      if (fullTrack == null) return false;
      final downloadTask = downloader.getTaskByTrackId(fullTrack.id);
      return const [
        DownloadStatus.queued,
        DownloadStatus.downloading,
      ].contains(downloadTask?.status);
    }, [fullTrack, downloader]);

    final isDownloaded = useMemoized(() {
      if (activeTrack == null) return false;
      return localTracks?.values.expand((e) => e).any(
                (element) =>
                    element.name == activeTrack.name &&
                    element.album.name == activeTrack.album.name &&
                    element.artists.asString() == activeTrack.artists.asString(),
              ) ==
          true;
    }, [localTracks, activeTrack]);

    void closeThen(VoidCallback action) {
      close();
      Future.microtask(action);
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: SurfaceCard(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          borderRadius: BorderRadius.circular(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      "Настройки",
                      style: theme.typography.large.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    IconButton.ghost(
                      size: ButtonSize.small,
                      icon: const Icon(SpotubeIcons.close),
                      onPressed: close,
                    ),
                  ],
                ),
                const Gap(10),
                if (!isLocalTrack && fullTrack != null)
                  _ActionTile(
                    icon: SpotubeIcons.alternativeRoute,
                    title: "Альтернативный источник",
                    subtitle: "Похожие аудио без мусорных 00:00-видео",
                    onPressed: () => closeThen(() {
                      _openSiblingTracks(rootContext, floatingQueue);
                    }),
                  ),
                if (!kIsWeb && fullTrack != null)
                  _ActionTile(
                    icon: isDownloaded ? SpotubeIcons.done : SpotubeIcons.download,
                    title: isDownloaded ? "Уже скачано" : "Скачать трек",
                    subtitle: isInDownloadQueue
                        ? "Загрузка уже в очереди"
                        : "Сохранить трек локально",
                    enabled: !isInDownloadQueue && !isDownloaded,
                    onPressed: () {
                      downloader.addToQueue(fullTrack);
                      close();
                    },
                  ),
                if (activeTrack != null)
                  _ActionTile(
                    icon: SpotubeIcons.share,
                    title: "Поделиться",
                    subtitle: "Отправить сам аудиофайл",
                    onPressed: () => closeThen(() {
                      unawaited(_shareTrackFile(rootContext, ref, activeTrack));
                    }),
                  ),
                if (fullTrack != null &&
                    authenticated.asData?.value == true)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        TrackHeartButton(track: fullTrack),
                        const Gap(6),
                        Expanded(
                          child: Text(
                            "В избранное",
                            style: theme.typography.normal.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const Gap(8),
                const _SectionTitle("Звук"),
                _ActionTile(
                  icon: SpotubeIcons.audioQuality,
                  title: "Эквалайзер",
                  subtitle: "10 полос и быстрый сброс в отдельном окне",
                  onPressed: () => closeThen(() {
                    _openEqualizerOverlay(rootContext);
                  }),
                ),
                _SwitchTile(
                  icon: SpotubeIcons.repeat,
                  title: "Плавный переход",
                  subtitle: "Мягкий fade между треками и кнопками next/prev",
                  value: crossfade,
                  onChanged: crossfadeNotifier.setEnabled,
                ),
                _SwitchTile(
                  icon: SpotubeIcons.normalize,
                  title: context.l10n.normalize_audio,
                  subtitle: "Выравнивать громкость треков",
                  value: preferences.normalizeAudio,
                  onChanged: preferencesNotifier.setNormalizeAudio,
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 4, bottom: 10),
                  child: VolumeSlider(
                    fullWidth: true,
                    value: volume,
                    onChanged: ref.read(volumeProvider.notifier).setVolume,
                  ),
                ),
                const _SectionTitle("Таймер сна"),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _TimerButton(
                      label: context.l10n.mins(15),
                      active: sleepTimer == const Duration(minutes: 15),
                      onPressed: () => sleepTimerNotifier.setSleepTimer(
                        const Duration(minutes: 15),
                      ),
                    ),
                    _TimerButton(
                      label: context.l10n.mins(30),
                      active: sleepTimer == const Duration(minutes: 30),
                      onPressed: () => sleepTimerNotifier.setSleepTimer(
                        const Duration(minutes: 30),
                      ),
                    ),
                    _TimerButton(
                      label: context.l10n.hour(1),
                      active: sleepTimer == const Duration(hours: 1),
                      onPressed: () => sleepTimerNotifier.setSleepTimer(
                        const Duration(hours: 1),
                      ),
                    ),
                    _TimerButton(
                      label: sleepTimer == null
                          ? context.l10n.custom_hours
                          : "Осталось ${sleepTimer.format(abbreviated: true)}",
                      active: sleepTimer != null,
                      onPressed: () => _pickCustomSleepTimer(
                        context,
                        sleepTimer,
                        sleepTimerNotifier,
                      ),
                    ),
                    if (sleepTimer != null)
                      _TimerButton(
                        label: context.l10n.cancel,
                        active: false,
                        onPressed: sleepTimerNotifier.cancelSleepTimer,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool enabled;
  final VoidCallback onPressed;

  const _ActionTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.enabled = true,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Button.ghost(
      leading: Icon(icon),
      enabled: enabled,
      onPressed: onPressed,
      child: _TileText(title: title, subtitle: subtitle),
    );
  }
}

class _EqualizerPanel extends HookConsumerWidget {
  const _EqualizerPanel();

  static const _labels = [
    "31",
    "62",
    "125",
    "250",
    "500",
    "1K",
    "2K",
    "4K",
    "8K",
    "16K",
  ];

  @override
  Widget build(BuildContext context, ref) {
    final theme = Theme.of(context);
    final bands = ref.watch(playerEqualizerProvider);
    final notifier = ref.watch(playerEqualizerProvider.notifier);
    final hasCustomPreset = bands.any((gain) => gain.abs() >= 0.05);

    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      borderRadius: BorderRadius.circular(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(SpotubeIcons.audioQuality, size: 18),
              const Gap(8),
              Expanded(
                child: Text(
                  "Эквалайзер",
                  style: theme.typography.normal.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Button(
                style: const ButtonStyle.ghost(
                  size: ButtonSize.small,
                  density: ButtonDensity.dense,
                ),
                enabled: hasCustomPreset,
                onPressed: () {
                  notifier.reset();
                },
                child: const Text("Сброс"),
              ),
            ],
          ),
          const Gap(4),
          Text(
            "10 полос, -12/+12 дБ. Работает внутри ETGmusic, без внешних эффектов прошивки.",
            style: theme.typography.xSmall.copyWith(
              color: theme.colorScheme.mutedForeground,
            ),
          ),
          const Gap(10),
          for (var i = 0; i < _labels.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 34,
                    child: Text(
                      _labels[i],
                      style: theme.typography.xSmall.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      min: -12,
                      max: 12,
                      value: SliderValue.single(bands[i]),
                      onChanged: (value) {
                        notifier.setBand(i, value.value);
                      },
                      onChangeEnd: (value) {
                        notifier.setBand(
                          i,
                          value.value,
                          applyImmediately: true,
                        );
                      },
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text(
                      "${bands[i] >= 0 ? "+" : ""}${bands[i].toStringAsFixed(1)}",
                      textAlign: TextAlign.right,
                      style: theme.typography.xSmall,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _EqualizerSheet extends StatelessWidget {
  final VoidCallback close;

  const _EqualizerSheet({required this.close});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: SurfaceCard(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          borderRadius: BorderRadius.circular(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    "Эквалайзер",
                    style: theme.typography.large.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  IconButton.ghost(
                    size: ButtonSize.small,
                    icon: const Icon(SpotubeIcons.close),
                    onPressed: close,
                  ),
                ],
              ),
              const Gap(10),
              const _EqualizerPanel(),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Button.ghost(
      leading: Icon(icon),
      onPressed: () => onChanged(!value),
      trailing: Switch(value: value, onChanged: onChanged),
      child: _TileText(title: title, subtitle: subtitle),
    );
  }
}

class _TileText extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _TileText({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: theme.typography.normal.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.small.copyWith(
                color: theme.colorScheme.mutedForeground,
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Text(
        text,
        style: Theme.of(context).typography.small.copyWith(
              color: Theme.of(context).colorScheme.mutedForeground,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
      ),
    );
  }
}

class _TimerButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onPressed;

  const _TimerButton({
    required this.label,
    required this.active,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Button(
      style: active ? ButtonVariance.secondary : ButtonVariance.outline,
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

void _openPlayerActionsOverlay(
  BuildContext context, {
  required bool floatingQueue,
}) {
  if (MediaQuery.sizeOf(context).mdAndUp) {
    showDropdown(
      context: context,
      builder: (overlayContext) {
        return _PlayerActionsSheet(
          rootContext: context,
          close: () => closeOverlay(overlayContext),
          floatingQueue: floatingQueue,
        );
      },
    );
    return;
  }

  openDrawer(
    context: context,
    position: OverlayPosition.bottom,
    draggable: true,
    showDragHandle: false,
    transformBackdrop: false,
    surfaceBlur: 0,
    surfaceOpacity: 1,
    borderRadius: BorderRadius.circular(28),
    builder: (sheetContext) {
      return _PlayerActionsSheet(
        rootContext: context,
        close: () => closeDrawer(sheetContext),
        floatingQueue: floatingQueue,
      );
    },
  );
}

void _openQueueDrawer(BuildContext context) {
  openDrawer(
    context: context,
    position: OverlayPosition.right,
    transformBackdrop: false,
    draggable: false,
    surfaceBlur: context.theme.surfaceBlur,
    surfaceOpacity: 0.7,
    builder: (context) {
      return Container(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Consumer(
          builder: (context, ref, _) {
            final playlist = ref.watch(audioPlayerProvider);
            final playlistNotifier = ref.read(audioPlayerProvider.notifier);

            return PlayerQueue.fromAudioPlayerNotifier(
              floating: true,
              playlist: playlist,
              notifier: playlistNotifier,
            );
          },
        ),
      );
    },
  );
}

void _openSiblingTracks(BuildContext context, bool floatingQueue) {
  final screenSize = MediaQuery.sizeOf(context);
  if (screenSize.mdAndUp) {
    showPopover(
      alignment: Alignment.bottomCenter,
      context: context,
      builder: (context) {
        return SurfaceCard(
          padding: EdgeInsets.zero,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxHeight: 600,
              maxWidth: 500,
            ),
            child: SiblingTracksSheet(floating: floatingQueue),
          ),
        );
      },
    );
  } else {
    context.pushRoute(const PlayerTrackSourcesRoute());
  }
}

void _openEqualizerOverlay(BuildContext context) {
  if (MediaQuery.sizeOf(context).mdAndUp) {
    showDropdown(
      context: context,
      builder: (overlayContext) {
        return _EqualizerSheet(
          close: () => closeOverlay(overlayContext),
        );
      },
    );
    return;
  }

  openDrawer(
    context: context,
    position: OverlayPosition.bottom,
    draggable: true,
    showDragHandle: false,
    transformBackdrop: false,
    surfaceBlur: 0,
    surfaceOpacity: 1,
    borderRadius: BorderRadius.circular(28),
    builder: (sheetContext) {
      return _EqualizerSheet(
        close: () => closeDrawer(sheetContext),
      );
    },
  );
}

Future<void> _shareTrackFile(
  BuildContext context,
  WidgetRef ref,
  SpotubeTrackObject track,
) async {
  try {
    _showPlainToast(context, "Готовлю файл трека...");
    final shared = await TrackFileShareService.shareTrack(ref, track);
    if (!context.mounted || !shared) return;
    _showPlainToast(
      context,
      "Файл передан в меню отправки",
    );
  } catch (error) {
    if (!context.mounted) return;
    _showPlainToast(context, "Не удалось подготовить файл: $error");
  }
}

void _showPlainToast(BuildContext context, String text) {
  showToast(
    context: context,
    location: ToastLocation.topRight,
    builder: (context, overlay) => SurfaceCard(child: Text(text)),
  );
}

Future<void> _pickCustomSleepTimer(
  BuildContext context,
  Duration? sleepTimer,
  SleepTimerNotifier sleepTimerNotifier,
) async {
  final now = DateTime.now();
  final time = await showDialog<TimeOfDay?>(
    context: context,
    builder: (context) => HookBuilder(builder: (context) {
      final timeRef = useRef<TimeOfDay?>(null);
      return AlertDialog(
        trailing: IconButton.ghost(
          size: ButtonSize.xSmall,
          icon: const Icon(SpotubeIcons.close),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        title: Text(
          ShadcnLocalizations.of(context).placeholderTimePicker,
        ),
        content: TimePickerDialog(
          use24HourFormat: false,
          initialValue: TimeOfDay.fromDateTime(
            DateTime.now().add(sleepTimer ?? Duration.zero),
          ),
          onChanged: (value) => timeRef.value = value,
        ),
        actions: [
          Button.primary(
            onPressed: () {
              Navigator.of(context).pop(timeRef.value);
            },
            child: Text(context.l10n.save),
          ),
        ],
      );
    }),
  );

  if (time == null) return;
  final selectedToday = DateTime(
    now.year,
    now.month,
    now.day,
    time.hour,
    time.minute,
  );
  final endsAt = selectedToday.isAfter(now)
      ? selectedToday
      : selectedToday.add(const Duration(days: 1));

  sleepTimerNotifier.setSleepTimer(endsAt.difference(now));
}
