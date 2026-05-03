import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:etgmusic/models/database/database.dart';
import 'package:etgmusic/models/metadata/metadata.dart';
import 'package:etgmusic/models/playback/track_sources.dart';
import 'package:etgmusic/provider/database/database.dart';
import 'package:etgmusic/provider/metadata_plugin/audio_source/quality_presets.dart';
import 'package:etgmusic/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:etgmusic/services/dio/dio.dart';
import 'package:etgmusic/services/logger/logger.dart';
import 'package:etgmusic/services/metadata/errors/exceptions.dart';
import 'package:etgmusic/services/telegram/telegram_media.dart';

import 'package:etgmusic/services/sourced_track/exceptions.dart';

final officialMusicRegex = RegExp(
  r"official\s(video|audio|music\svideo|lyric\svideo|visualizer)",
  caseSensitive: false,
);

class SourcedTrack extends BasicSourcedTrack {
  final Ref ref;

  SourcedTrack({
    required this.ref,
    required super.info,
    required super.query,
    required super.source,
    required super.siblings,
    required super.sources,
  });

  factory SourcedTrack._fromTelegramDirect({
    required Ref ref,
    required SpotubeFullTrackObject query,
    required String streamUrl,
  }) {
    final info = SpotubeAudioSourceMatchObject(
      id: query.id,
      title: query.name,
      artists: query.artists.map((artist) => artist.name).toList(),
      duration: Duration(milliseconds: query.durationMs),
      externalUri: query.externalUri,
    );

    return SourcedTrack(
      ref: ref,
      info: info,
      query: query,
      source: "telegram",
      siblings: const [],
      sources: [
        SpotubeAudioSourceStreamObject(
          url: streamUrl,
          container: _containerFromTelegramUrl(streamUrl),
          type: SpotubeMediaCompressionType.lossy,
          bitrate: 192000.0,
        ),
      ],
    );
  }

  static Future<SourcedTrack> fetchFromTrack({
    required SpotubeFullTrackObject query,
    required Ref ref,
  }) async {
    if (_isTelegramDirectTrack(query)) {
      final streamUrl = await ref
          .read(telegramMediaServiceProvider)
          .resolvePlayableUrl(query.id);
      return SourcedTrack._fromTelegramDirect(
        ref: ref,
        query: query,
        streamUrl: streamUrl,
      );
    }

    final audioSource = await ref.read(audioSourcePluginProvider.future);
    final audioSourceConfig = await ref.read(metadataPluginsProvider
        .selectAsync((data) => data.defaultAudioSourcePluginConfig));
    if (audioSource == null || audioSourceConfig == null) {
      throw MetadataPluginException.noDefaultAudioSourcePlugin();
    }

    final database = ref.read(databaseProvider);
    final cachedSource = await (database.select(database.sourceMatchTable)
          ..where((s) =>
              s.trackId.equals(query.id) &
              s.sourceType.equals(audioSourceConfig.slug))
          ..limit(1)
          ..orderBy([
            (s) =>
                OrderingTerm(expression: s.createdAt, mode: OrderingMode.desc),
          ]))
        .get()
        .then((s) => s.firstOrNull);

    if (cachedSource == null) {
      final siblings = await fetchSiblings(ref: ref, query: query);
      if (siblings.isEmpty) {
        throw TrackNotFoundError(query);
      }

      await database.into(database.sourceMatchTable).insert(
            SourceMatchTableCompanion.insert(
              trackId: query.id,
              sourceInfo: Value(jsonEncode(siblings.first)),
              sourceType: audioSourceConfig.slug,
            ),
          );

      final manifest = await audioSource.audioSource.streams(siblings.first);

      return SourcedTrack(
        ref: ref,
        siblings: siblings.skip(1).toList(),
        info: siblings.first,
        source: audioSourceConfig.slug,
        sources: manifest,
        query: query,
      );
    }
    final item = SpotubeAudioSourceMatchObject.fromJson(
      jsonDecode(cachedSource.sourceInfo),
    );
    if (!isUsefulSibling(item, query)) {
      await (database.sourceMatchTable.delete()
            ..where(
              (table) =>
                  table.trackId.equals(query.id) &
                  table.sourceType.equals(audioSourceConfig.slug),
            ))
          .go();
      return fetchFromTrack(query: query, ref: ref);
    }

    final manifest = await audioSource.audioSource.streams(item);

    final sourcedTrack = SourcedTrack(
      ref: ref,
      siblings: [],
      sources: manifest,
      info: item,
      query: query,
      source: audioSourceConfig.slug,
    );

    AppLogger.log.i("${query.name}: ${sourcedTrack.url}");

    return sourcedTrack;
  }

  static List<SpotubeAudioSourceMatchObject> rankResults(
    List<SpotubeAudioSourceMatchObject> results,
    SpotubeFullTrackObject track,
  ) {
    return results
        .map((sibling) => (
              sibling: sibling,
              score: sourceMatchScore(sibling, track),
            ))
        .sorted((a, b) => b.score.compareTo(a.score))
        .map((e) => e.sibling)
        .toList();
  }

  static int sourceMatchScore(
    SpotubeAudioSourceMatchObject sibling,
    SpotubeFullTrackObject track,
  ) {
    int score = 0;
    final title = sibling.title.toLowerCase();
    final trackName = track.name.toLowerCase();

    for (final artist in track.artists) {
      final artistName = artist.name.toLowerCase();
      final isSameChannelArtist =
          sibling.artists.any((a) => a.toLowerCase() == artistName);

      if (isSameChannelArtist) {
        score += 2;
      }

      if (title.contains(artistName)) {
        score += 2;
      }
    }

    final titleContainsTrackName = title.contains(trackName);
    final hasOfficialFlag = officialMusicRegex.hasMatch(title);

    if (titleContainsTrackName) {
      score += 5;
    }

    if (hasOfficialFlag) {
      score += 1;
    }

    if (hasOfficialFlag && titleContainsTrackName) {
      score += 2;
    }

    return score;
  }

  static bool isUsefulSibling(
    SpotubeAudioSourceMatchObject sibling,
    SpotubeFullTrackObject track,
  ) {
    if (sibling.duration <= Duration.zero) return false;
    if (sibling.duration > const Duration(minutes: 18)) return false;

    final expected = Duration(milliseconds: track.durationMs);
    if (expected > const Duration(seconds: 30)) {
      final minMs = (expected.inMilliseconds * 0.55).round();
      final maxMs = (expected.inMilliseconds * 1.75).round();
      if (sibling.duration.inMilliseconds < minMs ||
          sibling.duration.inMilliseconds > maxMs) {
        return false;
      }
    }

    return sourceMatchScore(sibling, track) >= 2;
  }

  static Future<List<SpotubeAudioSourceMatchObject>> fetchSiblings({
    required SpotubeFullTrackObject query,
    required Ref ref,
  }) async {
    final audioSource = await ref.read(audioSourcePluginProvider.future);

    if (audioSource == null) {
      throw MetadataPluginException.noDefaultAudioSourcePlugin();
    }

    final searchResults = await audioSource.audioSource.matches(query);
    final usefulResults = searchResults
        .where((source) => isUsefulSibling(source, query))
        .toList();
    final rankedResults = rankResults(
      usefulResults.isEmpty ? searchResults : usefulResults,
      query,
    )
        .where(
          (source) =>
              source.duration > Duration.zero &&
              sourceMatchScore(source, query) >= 2,
        )
        .toList();

    return rankedResults.take(12).toSet().toList();
  }

  Future<SourcedTrack> copyWithSibling() async {
    if (siblings.isNotEmpty) {
      return this;
    }
    final fetchedSiblings = await fetchSiblings(ref: ref, query: query);

    return SourcedTrack(
      ref: ref,
      siblings: fetchedSiblings.where((s) => s.id != info.id).toList(),
      source: source,
      sources: sources,
      info: info,
      query: query,
    );
  }

  Future<SourcedTrack?> swapWithSibling(
    SpotubeAudioSourceMatchObject sibling,
  ) async {
    if (sibling.id == info.id) {
      return null;
    }

    final audioSource = await ref.read(audioSourcePluginProvider.future);
    final audioSourceConfig = await ref.read(metadataPluginsProvider
        .selectAsync((data) => data.defaultAudioSourcePluginConfig));
    if (audioSource == null || audioSourceConfig == null) {
      throw MetadataPluginException.noDefaultAudioSourcePlugin();
    }

    // a sibling source that was fetched from the search results
    final isStepSibling = siblings.none((s) => s.id == sibling.id);

    final newSourceInfo = isStepSibling
        ? sibling
        : siblings.firstWhere((s) => s.id == sibling.id);

    final newSiblings = siblings.where((s) => s.id != sibling.id).toList()
      ..insert(0, info);

    final manifest = await audioSource.audioSource.streams(newSourceInfo);

    final database = ref.read(databaseProvider);

    // Delete the old Entry
    await (database.sourceMatchTable.delete()
          ..where(
            (table) =>
                table.trackId.equals(query.id) &
                table.sourceType.equals(audioSourceConfig.slug),
          ))
        .go();

    await database.into(database.sourceMatchTable).insert(
          SourceMatchTableCompanion.insert(
            trackId: query.id,
            sourceInfo: Value(jsonEncode(sibling)),
            sourceType: audioSourceConfig.slug,
            createdAt: Value(DateTime.now()),
          ),
          mode: InsertMode.replace,
        );

    return SourcedTrack(
      ref: ref,
      source: source,
      siblings: newSiblings,
      sources: manifest,
      info: newSourceInfo,
      query: query,
    );
  }

  Future<SourcedTrack?> swapWithSiblingOfIndex(int index) {
    return swapWithSibling(siblings[index]);
  }

  Future<SourcedTrack> refreshStream() async {
    if (source == "telegram") {
      return this;
    }

    final audioSource = await ref.read(audioSourcePluginProvider.future);
    final audioSourceConfig = await ref.read(metadataPluginsProvider
        .selectAsync((data) => data.defaultAudioSourcePluginConfig));
    if (audioSource == null || audioSourceConfig == null) {
      throw MetadataPluginException.noDefaultAudioSourcePlugin();
    }

    List<SpotubeAudioSourceStreamObject> validStreams = [];

    final stringBuffer = StringBuffer();
    for (final source in sources) {
      final res = await globalDio.head(
        source.url,
        options:
            Options(validateStatus: (status) => status != null && status < 500),
      );

      stringBuffer.writeln(
        "[${query.id}] ${res.statusCode} ${source.container} ${source.codec} ${source.bitrate}",
      );

      if (res.statusCode! < 400) {
        validStreams.add(source);
      }
    }

    AppLogger.log.d(stringBuffer.toString());

    if (validStreams.isEmpty) {
      validStreams = await audioSource.audioSource.streams(info);
    }

    final sourcedTrack = SourcedTrack(
      ref: ref,
      siblings: siblings,
      source: source,
      sources: validStreams,
      info: info,
      query: query,
    );

    AppLogger.log.i("Refreshing ${query.name}: ${sourcedTrack.url}");

    return sourcedTrack;
  }

  String? get url {
    if (source == "telegram") {
      return sources.firstOrNull?.url;
    }

    final preferences = ref.read(audioSourcePresetsProvider);

    return getUrlOfQuality(
      preferences.presets[preferences.selectedStreamingContainerIndex],
      preferences.selectedStreamingQualityIndex,
    );
  }

  /// Returns the URL of the track based on the codec and quality preferences.
  /// If an exact match is not found, it will return the closest match based on
  /// the user's audio quality preference.
  ///
  /// If no sources match the codec, it will return the first or last source
  /// based on the user's audio quality preference.
  SpotubeAudioSourceStreamObject? getStreamOfQuality(
    SpotubeAudioSourceContainerPreset preset,
    int qualityIndex,
  ) {
    if (sources.isEmpty) return null;

    final quality = preset.qualities[qualityIndex];

    final exactMatch = sources.firstWhereOrNull(
      (source) {
        if (source.container != preset.name) return false;

        if (quality case SpotubeAudioLosslessContainerQuality()) {
          return source.sampleRate == quality.sampleRate &&
              source.bitDepth == quality.bitDepth;
        } else {
          return source.bitrate ==
              (quality as SpotubeAudioLossyContainerQuality).bitrate;
        }
      },
    );

    if (exactMatch != null) {
      return exactMatch;
    }

    // Find the preset with closest quality to the supplied quality
    return sources.where((source) {
      return source.container == preset.name;
    }).reduce((prev, curr) {
      if (quality is SpotubeAudioLosslessContainerQuality) {
        final prevDiff = ((prev.sampleRate ?? 0) - quality.sampleRate).abs() +
            ((prev.bitDepth ?? 0) - quality.bitDepth).abs();
        final currDiff = ((curr.sampleRate ?? 0) - quality.sampleRate).abs() +
            ((curr.bitDepth ?? 0) - quality.bitDepth).abs();
        return currDiff < prevDiff ? curr : prev;
      } else {
        final prevDiff = ((prev.bitrate ?? 0) -
                (quality as SpotubeAudioLossyContainerQuality).bitrate)
            .abs();
        final currDiff = ((curr.bitrate ?? 0) - quality.bitrate).abs();
        return currDiff < prevDiff ? curr : prev;
      }
    });
  }

  String? getUrlOfQuality(
    SpotubeAudioSourceContainerPreset preset,
    int qualityIndex,
  ) {
    return getStreamOfQuality(preset, qualityIndex)?.url;
  }

  SpotubeAudioSourceContainerPreset? get qualityPreset {
    final presetState = ref.read(audioSourcePresetsProvider);
    return presetState.presets
        .elementAtOrNull(presetState.selectedStreamingContainerIndex);
  }
}

bool _isTelegramDirectTrack(SpotubeFullTrackObject track) {
  return track.id.startsWith("telegram:") &&
      (track.externalUri.startsWith("https://api.telegram.org/file/bot") ||
          track.externalUri.startsWith("telegram-mtproto://"));
}

String _containerFromTelegramUrl(String url) {
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
  if (path.endsWith(".mp3")) return "mp3";
  if (path.endsWith(".m4a") || path.endsWith(".mp4")) return "mp4";
  if (path.endsWith(".ogg") || path.endsWith(".opus")) return "ogg";
  if (path.endsWith(".flac")) return "flac";
  if (path.endsWith(".wav")) return "wav";
  return "mp4";
}
