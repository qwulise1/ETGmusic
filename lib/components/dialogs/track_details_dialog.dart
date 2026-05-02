import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:etgmusic/collections/spotube_icons.dart';
import 'package:etgmusic/components/links/artist_link.dart';
import 'package:etgmusic/components/links/hyper_link.dart';
import 'package:etgmusic/extensions/constrains.dart';
import 'package:etgmusic/extensions/context.dart';
import 'package:etgmusic/extensions/duration.dart';
import 'package:etgmusic/models/metadata/metadata.dart';
import 'package:etgmusic/provider/server/sourced_track_provider.dart';

class TrackDetailsDialog extends HookConsumerWidget {
  final SpotubeFullTrackObject track;
  const TrackDetailsDialog({
    super.key,
    required this.track,
  });

  @override
  Widget build(BuildContext context, ref) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final sourcedTrack = ref.read(sourcedTrackProvider(track));

    final detailsMap = {
      context.l10n.title: track.name,
      context.l10n.artist: ArtistLink(
        artists: track.artists,
        mainAxisAlignment: WrapAlignment.start,
        textStyle: const TextStyle(color: Colors.blue),
        hideOverflowArtist: false,
      ),
      // context.l10n.album: LinkText(
      //   track.album!.name!,
      //   AlbumRoute(album: track.album!, id: track.album!.id!),
      //   overflow: TextOverflow.ellipsis,
      //   style: const TextStyle(color: Colors.blue),
      // ),
      context.l10n.duration: sourcedTrack.asData != null
          ? sourcedTrack.asData!.value.info.duration.toHumanReadableString()
          : Duration(milliseconds: track.durationMs).toHumanReadableString(),
      if (track.album.releaseDate != null)
        context.l10n.released: track.album.releaseDate,
    };

    final sourceInfo = sourcedTrack.asData?.value.info;

    final ytTracksDetailsMap = sourceInfo == null
        ? {}
        : {
            context.l10n.youtube: Hyperlink(
              "https://piped.video/watch?v=${sourceInfo.id}",
              "https://piped.video/watch?v=${sourceInfo.id}",
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            context.l10n.channel: Text(sourceInfo.artists.join(", ")),
            if (sourcedTrack.asData?.value.url != null)
              context.l10n.streamUrl: Hyperlink(
                sourcedTrack.asData!.value.url ?? "",
                sourcedTrack.asData!.value.url ?? "",
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
          };

    return AlertDialog(
      surfaceBlur: 0,
      surfaceOpacity: 1,
      title: Row(
        spacing: 8,
        children: [
          const Icon(SpotubeIcons.info),
          Text(
            context.l10n.details,
            style: theme.typography.h4,
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: mediaQuery.mdAndUp ? 560 : 340,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            for (final entry in detailsMap.entries)
              _TrackDetailsRow(label: entry.key, value: entry.value),
            if (ytTracksDetailsMap.isNotEmpty) ...[
              const Gap(4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Источник",
                  style: theme.typography.small.copyWith(
                    color: theme.colorScheme.mutedForeground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              for (final entry in ytTracksDetailsMap.entries)
                _TrackDetailsRow(label: entry.key, value: entry.value),
            ],
          ],
        ),
      ),
    );
  }
}

class _TrackDetailsRow extends StatelessWidget {
  final String label;
  final Object? value;

  const _TrackDetailsRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueWidget = value is Widget
        ? value as Widget
        : Text(
            value?.toString() ?? "",
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.typography.normal,
          );

    return OutlinedContainer(
      borderRadius: BorderRadius.circular(12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.small.copyWith(
                color: theme.colorScheme.mutedForeground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(child: valueWidget),
        ],
      ),
    );
  }
}
