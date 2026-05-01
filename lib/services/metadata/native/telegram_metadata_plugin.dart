import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:etgmusic/models/metadata/metadata.dart';
import 'package:etgmusic/provider/telegram/telegram_auth.dart';
import 'package:etgmusic/services/metadata/metadata.dart';
import 'package:etgmusic/services/telegram/telegram_media.dart';

MetadataPlugin createTelegramMetadataPlugin(
  Ref ref,
  TelegramAuthState authState,
) {
  final user = _TelegramUserEndpoint(ref, authState);
  final library = _TelegramLibraryEndpoint(ref, user);

  return MetadataPlugin.native(
    auth: _TelegramAuthEndpoint(ref, authState),
    audioSource: _TelegramAudioSourceEndpoint(),
    album: _TelegramAlbumEndpoint(ref),
    artist: _TelegramArtistEndpoint(ref),
    browse: _TelegramBrowseEndpoint(),
    search: _TelegramSearchEndpoint(ref, user),
    playlist: _TelegramPlaylistEndpoint(ref, user),
    track: _TelegramTrackEndpoint(ref),
    user: library,
    core: _TelegramCoreEndpoint(),
  );
}

class _TelegramAuthEndpoint {
  final Ref ref;
  final TelegramAuthState authState;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  _TelegramAuthEndpoint(this.ref, this.authState);

  Stream<bool> get authStateStream => _controller.stream;

  Future<void> authenticate() async {
    _controller.add(authState.isConnected);
  }

  bool isAuthenticated() => authState.isConnected;

  Future<void> logout() async {
    await ref.read(telegramAuthProvider.notifier).disconnect();
    _controller.add(false);
  }
}

class _TelegramUserEndpoint {
  final Ref ref;
  final TelegramAuthState authState;

  _TelegramUserEndpoint(this.ref, this.authState);

  SpotubeUserObject owner() {
    final username = authState.botUsername;
    return SpotubeUserObject(
      id: "telegram:${authState.botId ?? "bot"}",
      name: authState.botName ?? username ?? "ETGmusic Telegram",
      externalUri: username == null ? "tg://resolve" : "https://t.me/$username",
      images: const [],
    );
  }
}

class _TelegramLibraryEndpoint {
  final Ref ref;
  final _TelegramUserEndpoint userEndpoint;

  _TelegramLibraryEndpoint(this.ref, this.userEndpoint);

  Future<SpotubeUserObject> me() async => userEndpoint.owner();

  Future<SpotubePaginationResponseObject<SpotubeFullTrackObject>> savedTracks({
    int? offset,
    int? limit,
  }) async {
    return _paginate(
      await ref.read(telegramMediaTracksProvider.future),
      offset: offset,
      limit: limit,
    );
  }

  Future<SpotubePaginationResponseObject<SpotubeSimplePlaylistObject>>
      savedPlaylists({
    int? offset,
    int? limit,
  }) async {
    return _paginate(
      [_telegramPlaylist(userEndpoint.owner())],
      offset: offset,
      limit: limit,
    );
  }

  Future<SpotubePaginationResponseObject<SpotubeSimpleAlbumObject>>
      savedAlbums({
    int? offset,
    int? limit,
  }) async {
    final tracks = await ref.read(telegramMediaTracksProvider.future);
    final albums = {
      for (final track in tracks) track.album.id: track.album,
    }.values.toList();

    return _paginate(albums, offset: offset, limit: limit);
  }

  Future<SpotubePaginationResponseObject<SpotubeFullArtistObject>>
      savedArtists({
    int? offset,
    int? limit,
  }) async {
    final tracks = await ref.read(telegramMediaTracksProvider.future);
    final artists = {
      for (final track in tracks)
        for (final artist in track.artists)
          artist.id: SpotubeFullArtistObject(
            id: artist.id,
            name: artist.name,
            externalUri: artist.externalUri,
            images: artist.images ?? const [],
          ),
    }.values.toList();

    return _paginate(artists, offset: offset, limit: limit);
  }

  Future<bool> isSavedPlaylist(String playlistId) async {
    return playlistId == _telegramPlaylistId;
  }

  Future<List<bool>> isSavedTracks(List<String> ids) async {
    final tracks = await ref.read(telegramMediaTracksProvider.future);
    final savedIds = tracks.map((track) => track.id).toSet();
    return ids.map(savedIds.contains).toList();
  }

  Future<List<bool>> isSavedAlbums(List<String> ids) async {
    final albums = await savedAlbums(limit: 10000);
    final savedIds = albums.items.map((album) => album.id).toSet();
    return ids.map(savedIds.contains).toList();
  }

  Future<List<bool>> isSavedArtists(List<String> ids) async {
    final artists = await savedArtists(limit: 10000);
    final savedIds = artists.items.map((artist) => artist.id).toSet();
    return ids.map(savedIds.contains).toList();
  }
}

class _TelegramSearchEndpoint {
  final Ref ref;
  final _TelegramUserEndpoint userEndpoint;

  _TelegramSearchEndpoint(this.ref, this.userEndpoint);

  List<String> get chips => const ["tracks", "playlists"];

  Future<SpotubeSearchResponseObject> all(String query) async {
    final tracks = (await _filterTracks(query)).take(8).toList();
    return SpotubeSearchResponseObject(
      tracks: tracks,
      playlists: query.trim().isEmpty
          ? []
          : [_telegramPlaylist(userEndpoint.owner())],
      albums: const [],
      artists: const [],
    );
  }

  Future<SpotubePaginationResponseObject<SpotubeFullTrackObject>> tracks(
    String query, {
    int? limit,
    int? offset,
  }) async {
    return _paginate(
      await _filterTracks(query),
      offset: offset,
      limit: limit,
    );
  }

  Future<SpotubePaginationResponseObject<SpotubeSimplePlaylistObject>>
      playlists(
    String query, {
    int? limit,
    int? offset,
  }) async {
    final normalized = query.trim().toLowerCase();
    final items = normalized.isEmpty ||
            "telegram etgmusic сохраненные треки".contains(normalized)
        ? [_telegramPlaylist(userEndpoint.owner())]
        : <SpotubeSimplePlaylistObject>[];
    return _paginate(items, offset: offset, limit: limit);
  }

  Future<SpotubePaginationResponseObject<SpotubeSimpleAlbumObject>> albums(
    String query, {
    int? limit,
    int? offset,
  }) async {
    final tracks = await _filterTracks(query);
    final albums = {
      for (final track in tracks) track.album.id: track.album,
    }.values.toList();
    return _paginate(albums, offset: offset, limit: limit);
  }

  Future<SpotubePaginationResponseObject<SpotubeFullArtistObject>> artists(
    String query, {
    int? limit,
    int? offset,
  }) async {
    final tracks = await _filterTracks(query);
    final artists = {
      for (final track in tracks)
        for (final artist in track.artists)
          artist.id: SpotubeFullArtistObject(
            id: artist.id,
            name: artist.name,
            externalUri: artist.externalUri,
            images: artist.images ?? const [],
          ),
    }.values.toList();
    return _paginate(artists, offset: offset, limit: limit);
  }

  Future<List<SpotubeFullTrackObject>> _filterTracks(String query) async {
    final tracks = await ref.read(telegramMediaTracksProvider.future);
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return tracks;

    return tracks.where((track) {
      final haystack = [
        track.name,
        track.album.name,
        ...track.artists.map((artist) => artist.name),
      ].join(" ").toLowerCase();
      return haystack.contains(normalized);
    }).toList();
  }
}

class _TelegramPlaylistEndpoint {
  final Ref ref;
  final _TelegramUserEndpoint userEndpoint;

  _TelegramPlaylistEndpoint(this.ref, this.userEndpoint);

  Future<SpotubeFullPlaylistObject> getPlaylist(String id) async {
    final simple = _telegramPlaylist(userEndpoint.owner());
    return SpotubeFullPlaylistObject(
      id: simple.id,
      name: simple.name,
      description: simple.description,
      externalUri: simple.externalUri,
      owner: simple.owner,
      images: simple.images,
      collaborative: false,
      public: false,
    );
  }

  Future<SpotubePaginationResponseObject<SpotubeFullTrackObject>> tracks(
    String id, {
    int? offset,
    int? limit,
  }) async {
    return _paginate(
      await ref.read(telegramMediaTracksProvider.future),
      offset: offset,
      limit: limit,
    );
  }

  Future<SpotubeFullPlaylistObject?> create(
    String userId, {
    required String name,
    String? description,
    bool? public,
    bool? collaborative,
  }) async {
    return null;
  }

  Future<void> update(
    String playlistId, {
    String? name,
    String? description,
    bool? public,
    bool? collaborative,
  }) async {}

  Future<void> addTracks(
    String playlistId, {
    required List<String> trackIds,
    int? position,
  }) async {}

  Future<void> removeTracks(
    String playlistId, {
    required List<String> trackIds,
  }) async {}

  Future<void> save(String playlistId) async {}

  Future<void> unsave(String playlistId) async {}

  Future<void> deletePlaylist(String playlistId) async {}
}

class _TelegramBrowseEndpoint {
  Future<SpotubePaginationResponseObject<SpotubeBrowseSectionObject<Object>>>
      sections({
    int? offset,
    int? limit,
  }) async {
    return _paginate(const [], offset: offset, limit: limit);
  }

  Future<SpotubePaginationResponseObject<Object>> sectionItems(
    String id, {
    int? offset,
    int? limit,
  }) async {
    return _paginate<Object>(const [], offset: offset, limit: limit);
  }
}

class _TelegramTrackEndpoint {
  final Ref ref;

  _TelegramTrackEndpoint(this.ref);

  Future<SpotubeFullTrackObject> getTrack(String id) async {
    final tracks = await ref.read(telegramMediaTracksProvider.future);
    return tracks.firstWhere(
      (track) => track.id == id,
      orElse: () => throw StateError("Telegram track not found: $id"),
    );
  }

  Future<void> save(List<String> ids) async {}

  Future<void> unsave(List<String> ids) async {}

  Future<List<SpotubeFullTrackObject>> radio(String id) async {
    final tracks = await ref.read(telegramMediaTracksProvider.future);
    return tracks.where((track) => track.id != id).take(30).toList();
  }
}

class _TelegramAlbumEndpoint {
  final Ref ref;

  _TelegramAlbumEndpoint(this.ref);

  Future<SpotubeFullAlbumObject> getAlbum(String id) async {
    final tracks = await ref.read(telegramMediaTracksProvider.future);
    final albumTracks = tracks.where((track) => track.album.id == id).toList();
    final album = albumTracks.firstOrNull?.album;

    return SpotubeFullAlbumObject(
      id: id,
      name: album?.name ?? "Telegram",
      artists: album?.artists ?? const [],
      images: album?.images ?? const [],
      releaseDate: album?.releaseDate ?? DateTime.now().year.toString(),
      externalUri: album?.externalUri ?? "tg://resolve",
      totalTracks: albumTracks.length,
      albumType: album?.albumType ?? SpotubeAlbumType.album,
    );
  }

  Future<SpotubePaginationResponseObject<SpotubeFullTrackObject>> tracks(
    String id, {
    int? offset,
    int? limit,
  }) async {
    final tracks = await ref.read(telegramMediaTracksProvider.future);
    return _paginate(
      tracks.where((track) => track.album.id == id).toList(),
      offset: offset,
      limit: limit,
    );
  }

  Future<SpotubePaginationResponseObject<SpotubeSimpleAlbumObject>> releases({
    int? offset,
    int? limit,
  }) async {
    final tracks = await ref.read(telegramMediaTracksProvider.future);
    final albums = {
      for (final track in tracks) track.album.id: track.album,
    }.values.toList();
    return _paginate(albums, offset: offset, limit: limit);
  }

  Future<void> save(List<String> ids) async {}

  Future<void> unsave(List<String> ids) async {}
}

class _TelegramArtistEndpoint {
  final Ref ref;

  _TelegramArtistEndpoint(this.ref);

  Future<SpotubeFullArtistObject> getArtist(String id) async {
    final tracks = await ref.read(telegramMediaTracksProvider.future);
    final artist = tracks
        .expand((track) => track.artists)
        .firstWhere((artist) => artist.id == id);

    return SpotubeFullArtistObject(
      id: artist.id,
      name: artist.name,
      externalUri: artist.externalUri,
      images: artist.images ?? const [],
    );
  }

  Future<SpotubePaginationResponseObject<SpotubeFullTrackObject>> topTracks(
    String id, {
    int? offset,
    int? limit,
  }) async {
    final tracks = await ref.read(telegramMediaTracksProvider.future);
    return _paginate(
      tracks
          .where((track) => track.artists.any((artist) => artist.id == id))
          .toList(),
      offset: offset,
      limit: limit,
    );
  }

  Future<SpotubePaginationResponseObject<SpotubeSimpleAlbumObject>> albums(
    String id, {
    int? offset,
    int? limit,
  }) async {
    final tracks = await topTracks(id, limit: 10000);
    final albums = {
      for (final track in tracks.items) track.album.id: track.album,
    }.values.toList();
    return _paginate(albums, offset: offset, limit: limit);
  }

  Future<SpotubePaginationResponseObject<SpotubeFullArtistObject>> related(
    String id, {
    int? offset,
    int? limit,
  }) async {
    return _paginate<SpotubeFullArtistObject>(
      const [],
      offset: offset,
      limit: limit,
    );
  }

  Future<void> save(List<String> ids) async {}

  Future<void> unsave(List<String> ids) async {}
}

class _TelegramAudioSourceEndpoint {
  List<SpotubeAudioSourceContainerPreset> get supportedPresets => const [];

  Future<List<SpotubeAudioSourceMatchObject>> matches(
    SpotubeFullTrackObject track,
  ) async {
    return const [];
  }

  Future<List<SpotubeAudioSourceStreamObject>> streams(
    SpotubeAudioSourceMatchObject match,
  ) async {
    return const [];
  }
}

class _TelegramCoreEndpoint {
  Future<PluginUpdateAvailable?> checkUpdate(PluginConfiguration pluginConfig) {
    return Future.value(null);
  }

  Future<String> get support async {
    return "Telegram-источник ETGmusic: подключи бота или Telegram-сессию, укажи каналы/чаты и нажми синхронизацию в настройках.";
  }

  Future<void> scrobble(Map<String, dynamic> details) async {}
}

const _telegramPlaylistId = "telegram-library";
SpotubeSimplePlaylistObject _telegramPlaylist(SpotubeUserObject owner) {
  return SpotubeSimplePlaylistObject(
    id: _telegramPlaylistId,
    name: "Telegram",
    description: "Треки из подключенных ботов, каналов, групп и супергрупп",
    externalUri: "tg://resolve",
    owner: owner,
    images: const [],
  );
}

SpotubePaginationResponseObject<T> _paginate<T>(
  List<T> items, {
  int? offset,
  int? limit,
}) {
  final safeOffset = offset ?? 0;
  final safeLimit = limit ?? 20;
  final page = items.skip(safeOffset).take(safeLimit).toList();
  final nextOffset = safeOffset + page.length;

  return SpotubePaginationResponseObject<T>(
    items: page,
    total: items.length,
    limit: safeLimit,
    hasMore: nextOffset < items.length,
    nextOffset: nextOffset < items.length ? nextOffset : null,
  );
}
