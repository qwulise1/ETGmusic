import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lrc/lrc.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:etgmusic/models/database/database.dart';
import 'package:etgmusic/models/lyrics.dart';
import 'package:etgmusic/models/metadata/metadata.dart';
import 'package:etgmusic/provider/database/database.dart';
import 'package:etgmusic/services/dio/dio.dart';
import 'package:etgmusic/services/logger/logger.dart';

class SyncedLyricsNotifier
    extends FamilyAsyncNotifier<SubtitleSimple, SpotubeTrackObject?> {
  SpotubeTrackObject get _track => arg!;

  /// Lyrics credits: [lrclib.net](https://lrclib.net) and their contributors
  /// Thanks for their generous public API
  Future<SubtitleSimple> getLRCLibLyrics() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final options = Options(
      headers: {
        "User-Agent":
            "ETGmusic v${packageInfo.version} (https://github.com/qwulise1/ETGmusic)"
      },
      responseType: ResponseType.json,
    );
    final queries = _lyricsQueries();

    for (final query in queries) {
      final result = await _fetchLrcLibExact(query, options);
      if (result != null) return result;
    }

    for (final query in queries) {
      final result = await _fetchLrcLibSearch(query, options);
      if (result != null) return result;
    }

    for (final query in queries) {
      final result = await _fetchGeniusLyrics(query, options);
      if (result != null) return result;
    }

    return SubtitleSimple(
      lyrics: [],
      name: _track.name,
      uri: Uri.https("lrclib.net", "/api/search"),
      rating: 0,
      provider: "LRCLib",
    );
  }

  Future<SubtitleSimple?> _fetchGeniusLyrics(
    _LyricsQuery query,
    Options options,
  ) async {
    final searchQuery = query.queryText;
    if (searchQuery == null) return null;

    try {
      final search = await globalDio.getUri(
        Uri(
          scheme: "https",
          host: "genius.com",
          path: "/api/search/multi",
          queryParameters: {"q": searchQuery},
        ),
        options: options,
      );

      final data = search.data;
      if (data is! Map) return null;

      final sections = (data["response"] as Map?)?["sections"];
      if (sections is! List) return null;

      String? url;
      for (final section in sections.whereType<Map>()) {
        final hits = section["hits"];
        if (hits is! List) continue;
        for (final hit in hits.whereType<Map>()) {
          final result = hit["result"];
          if (result is! Map) continue;
          url = _string(result["url"]);
          if (url != null) break;
        }
        if (url != null) break;
      }

      if (url == null) return null;

      final page = await globalDio.getUri(
        Uri.parse(url),
        options: options.copyWith(responseType: ResponseType.plain),
      );
      final rawHtml = page.data?.toString();
      if (rawHtml == null || rawHtml.isEmpty) return null;

      final document = html_parser.parse(rawHtml);
      final containers = document.querySelectorAll("[data-lyrics-container]");
      final text = containers
          .map((node) {
            final html = node.innerHtml.replaceAll(
              RegExp(r"<br\s*/?>", caseSensitive: false),
              "\n",
            );
            return html_parser.parseFragment(html).text ?? "";
          })
          .join("\n")
          .replaceAll(RegExp(r"\n{3,}"), "\n\n")
          .trim();

      if (text.isEmpty) return null;

      return SubtitleSimple(
        lyrics: text
            .split("\n")
            .map((line) => LyricSlice(text: line.trim(), time: Duration.zero))
            .toList(),
        name: _track.name,
        uri: Uri.parse(url),
        rating: 0,
        provider: "Genius",
      );
    } catch (_) {
      return null;
    }
  }

  Future<SubtitleSimple?> _fetchLrcLibExact(
    _LyricsQuery query,
    Options options,
  ) async {
    final parameters = query.exactParameters();
    if (parameters == null) return null;

    try {
      final res = await globalDio.getUri(
        Uri(
          scheme: "https",
          host: "lrclib.net",
          path: "/api/get",
          queryParameters: parameters,
        ),
        options: options,
      );

      final data = res.data;
      if (data is! Map) return null;
      return _subtitleFromJson(data.cast<String, dynamic>(), res.realUri);
    } catch (_) {
      return null;
    }
  }

  Future<SubtitleSimple?> _fetchLrcLibSearch(
    _LyricsQuery query,
    Options options,
  ) async {
    final parameters = query.searchParameters();
    if (parameters == null) return null;

    try {
      final res = await globalDio.getUri(
        Uri(
          scheme: "https",
          host: "lrclib.net",
          path: "/api/search",
          queryParameters: parameters,
        ),
        options: options,
      );

      final data = res.data;
      if (data is! List) return null;

      for (final item in data.whereType<Map>()) {
        final subtitle = _subtitleFromJson(
          item.cast<String, dynamic>(),
          res.realUri,
          fallbackRating: 75,
        );
        if (subtitle?.lyrics.isNotEmpty == true) return subtitle;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  SubtitleSimple? _subtitleFromJson(
    Map<String, dynamic> json,
    Uri uri, {
    int fallbackRating = 100,
  }) {
    final name =
        _string(json["trackName"]) ?? _string(json["name"]) ?? _track.name;
    final syncedLyricsRaw = _string(json["syncedLyrics"]);
    final syncedLyrics = syncedLyricsRaw?.isNotEmpty == true
        ? Lrc.parse(syncedLyricsRaw!)
            .lyrics
            .map(LyricSlice.fromLrcLine)
            .toList()
        : null;

    if (syncedLyrics?.isNotEmpty == true) {
      return SubtitleSimple(
        lyrics: syncedLyrics!,
        name: name,
        uri: uri,
        rating: fallbackRating,
        provider: "LRCLib",
      );
    }

    final plainLyricsRaw = _string(json["plainLyrics"]);
    if (plainLyricsRaw == null || plainLyricsRaw.isEmpty) return null;

    final plainLyrics = plainLyricsRaw
        .split("\n")
        .map((line) => LyricSlice(text: line, time: Duration.zero))
        .toList();

    return SubtitleSimple(
      lyrics: plainLyrics,
      name: name,
      uri: uri,
      rating: 0,
      provider: "LRCLib",
    );
  }

  List<_LyricsQuery> _lyricsQueries() {
    final artist = _track.artists.isEmpty ? "" : _track.artists.first.name;
    final title = _track.name;
    final album =
        _isGenericTelegramName(_track.album.name) ? null : _track.album.name;
    final duration =
        _track.durationMs > 0 ? (_track.durationMs / 1000).round() : null;
    final parsed = _splitArtistTitle(title);
    final cleanedTitle = _cleanLyricsTerm(parsed?.title ?? title);
    final cleanedArtist = _cleanLyricsTerm(parsed?.artist ?? artist);
    final queryArtist =
        _isGenericTelegramName(cleanedArtist) ? "" : cleanedArtist;

    final queries = [
      _LyricsQuery(
        trackName: title,
        artistName: artist,
        albumName: album,
        duration: duration,
      ),
      _LyricsQuery(
        trackName: cleanedTitle,
        artistName: cleanedArtist,
        albumName: album,
      ),
      _LyricsQuery(
        trackName: cleanedTitle,
        artistName: cleanedArtist,
      ),
      if (parsed != null)
        _LyricsQuery(
          trackName: _cleanLyricsTerm(parsed.title),
          artistName: _cleanLyricsTerm(parsed.artist),
        ),
      _LyricsQuery(query: "$queryArtist $cleanedTitle".trim()),
      _LyricsQuery(query: cleanedTitle),
    ];

    final seen = <String>{};
    return queries.where((query) => seen.add(query.key)).toList();
  }

  @override
  FutureOr<SubtitleSimple> build(track) async {
    try {
      final database = ref.watch(databaseProvider);

      if (track == null) {
        throw "No track currently";
      }

      final cachedLyrics = await (database.select(database.lyricsTable)
            ..where((tbl) => tbl.trackId.equals(track.id)))
          .map((row) => row.data)
          .get()
          .then((rows) => rows.isEmpty ? null : rows.last);

      SubtitleSimple? lyrics = cachedLyrics;

      if (lyrics == null ||
          lyrics.lyrics.isEmpty ||
          lyrics.lyrics.length <= 5) {
        lyrics = await getLRCLibLyrics();
      }

      if (lyrics.lyrics.isEmpty) {
        throw Exception("Unable to find lyrics");
      }

      if (cachedLyrics == null ||
          cachedLyrics.lyrics.isEmpty ||
          (cachedLyrics.lyrics.length <= 5 &&
              lyrics.lyrics.length > cachedLyrics.lyrics.length)) {
        await (database.delete(database.lyricsTable)
              ..where((tbl) => tbl.trackId.equals(track.id)))
            .go();
        await database.into(database.lyricsTable).insert(
              LyricsTableCompanion.insert(
                trackId: track.id,
                data: lyrics,
              ),
              mode: InsertMode.replace,
            );
      }

      return lyrics;
    } catch (e, stackTrace) {
      AppLogger.reportError(e, stackTrace);
      rethrow;
    }
  }
}

final syncedLyricsDelayProvider = StateProvider<int>((ref) => 0);

class _LyricsQuery {
  final String? trackName;
  final String? artistName;
  final String? albumName;
  final int? duration;
  final String? query;

  const _LyricsQuery({
    this.trackName,
    this.artistName,
    this.albumName,
    this.duration,
    this.query,
  });

  String get key {
    return [
      trackName,
      artistName,
      albumName,
      duration?.toString(),
      query,
    ].map((value) => value?.trim().toLowerCase() ?? "").join("|");
  }

  Map<String, String>? exactParameters() {
    final cleanTrack = _string(trackName);
    final cleanArtist = _string(artistName);
    if (cleanTrack == null || cleanArtist == null) return null;

    return {
      "artist_name": cleanArtist,
      "track_name": cleanTrack,
      if (_string(albumName) != null) "album_name": _string(albumName)!,
      if (duration != null && duration! > 0) "duration": duration.toString(),
    };
  }

  Map<String, String>? searchParameters() {
    final cleanQuery = _string(query);
    if (cleanQuery != null) return {"q": cleanQuery};

    final cleanTrack = _string(trackName);
    if (cleanTrack == null) return null;

    final cleanArtist = _string(artistName);
    return {
      "track_name": cleanTrack,
      if (cleanArtist != null) "artist_name": cleanArtist,
      if (_string(albumName) != null) "album_name": _string(albumName)!,
    };
  }

  String? get queryText {
    final cleanQuery = _string(query);
    if (cleanQuery != null) return cleanQuery;

    final cleanTrack = _string(trackName);
    if (cleanTrack == null) return null;

    final cleanArtist = _string(artistName);
    return [cleanArtist, cleanTrack]
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .join(" ");
  }
}

_ParsedTrackName? _splitArtistTitle(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) return null;

  final match = RegExp(r"^(.+?)\s+(?:-|–|—|:)\s+(.+)$").firstMatch(text);
  if (match == null) return null;

  final artist = match.group(1)?.trim();
  final title = match.group(2)?.trim();
  if (artist == null || title == null || artist.isEmpty || title.isEmpty) {
    return null;
  }

  return _ParsedTrackName(artist: artist, title: title);
}

String _cleanLyricsTerm(String value) {
  return value
      .replaceAll(
        RegExp(r"\.(mp3|m4a|flac|ogg|opus|wav)$", caseSensitive: false),
        "",
      )
      .replaceAll(
        RegExp(
          r"\s*[\[\(].*?(official|lyrics|audio|video|slowed|reverb).*?[\]\)]",
          caseSensitive: false,
        ),
        "",
      )
      .replaceAll(RegExp(r"\s+"), " ")
      .trim();
}

bool _isGenericTelegramName(String value) {
  return value.trim().toLowerCase() == "telegram";
}

String? _string(Object? value) {
  final string = value?.toString().trim();
  if (string == null || string.isEmpty) return null;
  return string;
}

class _ParsedTrackName {
  final String artist;
  final String title;

  const _ParsedTrackName({
    required this.artist,
    required this.title,
  });
}

final syncedLyricsProvider = AsyncNotifierProviderFamily<SyncedLyricsNotifier,
    SubtitleSimple, SpotubeTrackObject?>(
  () => SyncedLyricsNotifier(),
);

final syncedLyricsMapProvider =
    FutureProvider.family((ref, SpotubeTrackObject? track) async {
  final syncedLyrics = await ref.watch(syncedLyricsProvider(track).future);

  final isStaticLyrics =
      syncedLyrics.lyrics.every((l) => l.time == Duration.zero);

  final lyricsMap = syncedLyrics.lyrics
      .map((lyric) => {lyric.time.inSeconds: lyric.text})
      .reduce((accumulator, lyricSlice) => {...accumulator, ...lyricSlice});

  return (static: isStaticLyrics, lyricsMap: lyricsMap);
});
