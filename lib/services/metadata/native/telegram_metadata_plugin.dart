import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:etgmusic/models/metadata/metadata.dart';
import 'package:etgmusic/provider/telegram/telegram_auth.dart';
import 'package:etgmusic/services/metadata/metadata.dart';
import 'package:etgmusic/services/telegram/telegram_media.dart';
import 'package:etgmusic/services/youtube_engine/youtube_engine.dart';

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

MetadataPlugin createHybridTelegramMetadataPlugin(
  MetadataPlugin telegram,
  MetadataPlugin external, {
  YouTubeEngine? youtubeEngine,
}) {
  return MetadataPlugin.native(
    auth: _HybridAuthEndpoint(telegram.auth, external.auth),
    audioSource: telegram.audioSource,
    album: _HybridAlbumEndpoint(telegram.album, external.album),
    artist: _HybridArtistEndpoint(telegram.artist, external.artist),
    browse: _HybridBrowseEndpoint(external.browse),
    search: _HybridSearchEndpoint(
      telegram.search,
      external.search,
      youtubeEngine,
    ),
    playlist: _HybridPlaylistEndpoint(telegram.playlist, external.playlist),
    track: _HybridTrackEndpoint(telegram.track, external.track),
    user: telegram.user,
    core: _HybridCoreEndpoint(telegram.core, external.core),
  );
}

class _HybridAuthEndpoint {
  final dynamic telegram;
  final dynamic external;

  _HybridAuthEndpoint(this.telegram, this.external);

  Stream<bool> get authStateStream {
    try {
      return external.authStateStream as Stream<bool>;
    } catch (_) {
      return telegram.authStateStream as Stream<bool>;
    }
  }

  Future<void> authenticate() async {
    try {
      await external.authenticate();
    } catch (_) {
      await telegram.authenticate();
    }
  }

  bool isAuthenticated() {
    try {
      return external.isAuthenticated() == true ||
          telegram.isAuthenticated() == true;
    } catch (_) {
      return telegram.isAuthenticated() == true;
    }
  }

  Future<void> logout() async {
    try {
      await external.logout();
    } catch (_) {}
  }
}

class _HybridBrowseEndpoint {
  final dynamic external;

  _HybridBrowseEndpoint(this.external);

  Future<SpotubePaginationResponseObject<SpotubeBrowseSectionObject<Object>>>
      sections({
    int? offset,
    int? limit,
  }) async {
    return await _safeFuture(
      () async => await external.sections(
        offset: offset,
        limit: limit,
      ) as SpotubePaginationResponseObject<SpotubeBrowseSectionObject<Object>>,
      _paginate(
        const <SpotubeBrowseSectionObject<Object>>[],
        offset: offset,
        limit: limit,
      ),
    );
  }

  Future<SpotubePaginationResponseObject<Object>> sectionItems(
    String id, {
    int? offset,
    int? limit,
  }) async {
    return await _safeFuture(
      () async => await external.sectionItems(
        id,
        offset: offset,
        limit: limit,
      ) as SpotubePaginationResponseObject<Object>,
      _paginate(
        const <Object>[],
        offset: offset,
        limit: limit,
      ),
    );
  }
}

class _HybridSearchEndpoint {
  final dynamic telegram;
  final dynamic external;
  final YouTubeEngine? youtubeEngine;

  _HybridSearchEndpoint(this.telegram, this.external, this.youtubeEngine);

  List<String> get chips {
    final values = <String>[
      ..._safeSync<List<String>>(
        () => (telegram.chips as List).cast<String>(),
        const [],
      ),
      ..._safeSync<List<String>>(
        () => (external.chips as List).cast<String>(),
        const [],
      ),
    ];
    return {...values, "tracks"}.toList();
  }

  Future<SpotubeSearchResponseObject> all(String query) async {
    final telegramResult = await _safeFuture(
      () async => await telegram.all(query) as SpotubeSearchResponseObject,
      _emptySearch(),
    );
    final externalResult = await _safeFuture(
      () async => await external.all(query) as SpotubeSearchResponseObject,
      _emptySearch(),
    );
    final youtubeTracks = await _youtubeFallbackTracks(query, maxItems: 8);

    return SpotubeSearchResponseObject(
      tracks: _dedupeById([
        ...telegramResult.tracks,
        ...externalResult.tracks,
        ...youtubeTracks,
      ], (track) => track.id),
      albums: _dedupeById([
        ...telegramResult.albums,
        ...externalResult.albums,
      ], (album) => album.id),
      artists: _dedupeById([
        ...telegramResult.artists,
        ...externalResult.artists,
      ], (artist) => artist.id),
      playlists: _dedupeById([
        ...telegramResult.playlists,
        ...externalResult.playlists,
      ], (playlist) => playlist.id),
    );
  }

  Future<SpotubePaginationResponseObject<SpotubeFullTrackObject>> tracks(
    String query, {
    int? limit,
    int? offset,
  }) async {
    final fetchLimit = (offset ?? 0) + (limit ?? 20);
    final telegramItems = await _safeFuture(
      () async => (await telegram.tracks(
        query,
        limit: fetchLimit,
        offset: 0,
      ) as SpotubePaginationResponseObject<SpotubeFullTrackObject>)
          .items,
      const <SpotubeFullTrackObject>[],
    );
    final externalItems = await _safeFuture(
      () async => (await external.tracks(
        query,
        limit: fetchLimit,
        offset: 0,
      ) as SpotubePaginationResponseObject<SpotubeFullTrackObject>)
          .items,
      const <SpotubeFullTrackObject>[],
    );
    final youtubeItems = await _youtubeFallbackTracks(
      query,
      maxItems: fetchLimit,
    );
    return _paginate(
      _dedupeById([
        ...telegramItems,
        ...externalItems,
        ...youtubeItems,
      ], (track) => track.id),
      offset: offset,
      limit: limit,
    );
  }

  Future<SpotubePaginationResponseObject<SpotubeSimpleAlbumObject>> albums(
    String query, {
    int? limit,
    int? offset,
  }) async {
    final fetchLimit = (offset ?? 0) + (limit ?? 20);
    final telegramItems = await _safeFuture(
      () async => (await telegram.albums(
        query,
        limit: fetchLimit,
        offset: 0,
      ) as SpotubePaginationResponseObject<SpotubeSimpleAlbumObject>)
          .items,
      const <SpotubeSimpleAlbumObject>[],
    );
    final externalItems = await _safeFuture(
      () async => (await external.albums(
        query,
        limit: fetchLimit,
        offset: 0,
      ) as SpotubePaginationResponseObject<SpotubeSimpleAlbumObject>)
          .items,
      const <SpotubeSimpleAlbumObject>[],
    );
    return _paginate(
      _dedupeById([...telegramItems, ...externalItems], (album) => album.id),
      offset: offset,
      limit: limit,
    );
  }

  Future<SpotubePaginationResponseObject<SpotubeFullArtistObject>> artists(
    String query, {
    int? limit,
    int? offset,
  }) async {
    final fetchLimit = (offset ?? 0) + (limit ?? 20);
    final telegramItems = await _safeFuture(
      () async => (await telegram.artists(
        query,
        limit: fetchLimit,
        offset: 0,
      ) as SpotubePaginationResponseObject<SpotubeFullArtistObject>)
          .items,
      const <SpotubeFullArtistObject>[],
    );
    final externalItems = await _safeFuture(
      () async => (await external.artists(
        query,
        limit: fetchLimit,
        offset: 0,
      ) as SpotubePaginationResponseObject<SpotubeFullArtistObject>)
          .items,
      const <SpotubeFullArtistObject>[],
    );
    return _paginate(
      _dedupeById([...telegramItems, ...externalItems], (artist) => artist.id),
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
    final fetchLimit = (offset ?? 0) + (limit ?? 20);
    final telegramItems = await _safeFuture(
      () async => (await telegram.playlists(
        query,
        limit: fetchLimit,
        offset: 0,
      ) as SpotubePaginationResponseObject<SpotubeSimplePlaylistObject>)
          .items,
      const <SpotubeSimplePlaylistObject>[],
    );
    final externalItems = await _safeFuture(
      () async => (await external.playlists(
        query,
        limit: fetchLimit,
        offset: 0,
      ) as SpotubePaginationResponseObject<SpotubeSimplePlaylistObject>)
          .items,
      const <SpotubeSimplePlaylistObject>[],
    );
    return _paginate(
      _dedupeById([
        ...telegramItems,
        ...externalItems,
      ], (playlist) => playlist.id),
      offset: offset,
      limit: limit,
    );
  }

  Future<List<SpotubeFullTrackObject>> _youtubeFallbackTracks(
    String query, {
    required int maxItems,
  }) async {
    final engine = youtubeEngine;
    final normalized = query.trim();
    if (engine == null || normalized.isEmpty) {
      return const <SpotubeFullTrackObject>[];
    }

    final videos = await _safeFuture<List<dynamic>>(
      () async {
        final withAudio =
            (await engine.searchVideos("$normalized audio")).cast<dynamic>();
        final plain = (await engine.searchVideos(normalized)).cast<dynamic>();
        return _dedupeById(
          [...withAudio, ...plain],
          (video) => _videoId(video),
        );
      },
      const <dynamic>[],
    );

    return videos
        .where((video) => _isSearchableMusicVideo(video, normalized))
        .map(_youtubeVideoToTrack)
        .take(maxItems)
        .toList();
  }
}

class _HybridTrackEndpoint {
  final dynamic telegram;
  final dynamic external;

  _HybridTrackEndpoint(this.telegram, this.external);

  Future<SpotubeFullTrackObject> getTrack(String id) async {
    if (_isTelegramId(id)) return await telegram.getTrack(id);
    return await _safeFuture(
      () async => await external.getTrack(id) as SpotubeFullTrackObject,
      _fallbackTrack(id),
    );
  }

  Future<void> save(List<String> ids) async {
    final telegramIds = ids.where(_isTelegramId).toList();
    final externalIds = ids.where((id) => !_isTelegramId(id)).toList();
    if (telegramIds.isNotEmpty) {
      await _safeVoid(() async {
        await telegram.save(telegramIds);
      });
    }
    if (externalIds.isNotEmpty) {
      await _safeVoid(() async {
        await external.save(externalIds);
      });
    }
  }

  Future<void> unsave(List<String> ids) async {
    final telegramIds = ids.where(_isTelegramId).toList();
    final externalIds = ids.where((id) => !_isTelegramId(id)).toList();
    if (telegramIds.isNotEmpty) {
      await _safeVoid(() async {
        await telegram.unsave(telegramIds);
      });
    }
    if (externalIds.isNotEmpty) {
      await _safeVoid(() async {
        await external.unsave(externalIds);
      });
    }
  }

  Future<List<SpotubeFullTrackObject>> radio(String id) async {
    if (_isTelegramId(id)) {
      return await telegram.radio(id) as List<SpotubeFullTrackObject>;
    }
    return await _safeFuture(
      () async => await external.radio(id) as List<SpotubeFullTrackObject>,
      const <SpotubeFullTrackObject>[],
    );
  }
}

class _HybridAlbumEndpoint {
  final dynamic telegram;
  final dynamic external;

  _HybridAlbumEndpoint(this.telegram, this.external);

  Future<SpotubeFullAlbumObject> getAlbum(String id) async {
    if (_isTelegramId(id)) return await telegram.getAlbum(id);
    return await _safeFuture(
      () async => await external.getAlbum(id) as SpotubeFullAlbumObject,
      _fallbackAlbum(id),
    );
  }

  Future<SpotubePaginationResponseObject<SpotubeFullTrackObject>> tracks(
    String id, {
    int? offset,
    int? limit,
  }) async {
    if (_isTelegramId(id)) {
      return await telegram.tracks(id, offset: offset, limit: limit);
    }
    return await _safeFuture(
      () async => await external.tracks(
        id,
        offset: offset,
        limit: limit,
      ) as SpotubePaginationResponseObject<SpotubeFullTrackObject>,
      _paginate(const <SpotubeFullTrackObject>[], offset: offset, limit: limit),
    );
  }

  Future<SpotubePaginationResponseObject<SpotubeSimpleAlbumObject>> releases({
    int? offset,
    int? limit,
  }) async {
    return await _safeFuture(
      () async => await external.releases(
        offset: offset,
        limit: limit,
      ) as SpotubePaginationResponseObject<SpotubeSimpleAlbumObject>,
      _paginate(
        const <SpotubeSimpleAlbumObject>[],
        offset: offset,
        limit: limit,
      ),
    );
  }

  Future<void> save(List<String> ids) async {
    final externalIds = ids.where((id) => !_isTelegramId(id)).toList();
    if (externalIds.isNotEmpty) {
      await _safeVoid(() async {
        await external.save(externalIds);
      });
    }
  }

  Future<void> unsave(List<String> ids) async {
    final externalIds = ids.where((id) => !_isTelegramId(id)).toList();
    if (externalIds.isNotEmpty) {
      await _safeVoid(() async {
        await external.unsave(externalIds);
      });
    }
  }
}

class _HybridArtistEndpoint {
  final dynamic telegram;
  final dynamic external;

  _HybridArtistEndpoint(this.telegram, this.external);

  Future<SpotubeFullArtistObject> getArtist(String id) async {
    if (_isTelegramId(id)) return await telegram.getArtist(id);
    return await _safeFuture(
      () async => await external.getArtist(id) as SpotubeFullArtistObject,
      _fallbackArtist(id),
    );
  }

  Future<SpotubePaginationResponseObject<SpotubeFullTrackObject>> topTracks(
    String id, {
    int? offset,
    int? limit,
  }) async {
    if (_isTelegramId(id)) {
      return await telegram.topTracks(id, offset: offset, limit: limit);
    }
    return await _safeFuture(
      () async => await external.topTracks(
        id,
        offset: offset,
        limit: limit,
      ) as SpotubePaginationResponseObject<SpotubeFullTrackObject>,
      _paginate(const <SpotubeFullTrackObject>[], offset: offset, limit: limit),
    );
  }

  Future<SpotubePaginationResponseObject<SpotubeSimpleAlbumObject>> albums(
    String id, {
    int? offset,
    int? limit,
  }) async {
    if (_isTelegramId(id)) {
      return await telegram.albums(id, offset: offset, limit: limit);
    }
    return await _safeFuture(
      () async => await external.albums(
        id,
        offset: offset,
        limit: limit,
      ) as SpotubePaginationResponseObject<SpotubeSimpleAlbumObject>,
      _paginate(
        const <SpotubeSimpleAlbumObject>[],
        offset: offset,
        limit: limit,
      ),
    );
  }

  Future<SpotubePaginationResponseObject<SpotubeFullArtistObject>> related(
    String id, {
    int? offset,
    int? limit,
  }) async {
    if (_isTelegramId(id)) {
      return await telegram.related(id, offset: offset, limit: limit);
    }
    return await _safeFuture(
      () async => await external.related(
        id,
        offset: offset,
        limit: limit,
      ) as SpotubePaginationResponseObject<SpotubeFullArtistObject>,
      _paginate(const <SpotubeFullArtistObject>[], offset: offset, limit: limit),
    );
  }

  Future<void> save(List<String> ids) async {
    final externalIds = ids.where((id) => !_isTelegramId(id)).toList();
    if (externalIds.isNotEmpty) {
      await _safeVoid(() async {
        await external.save(externalIds);
      });
    }
  }

  Future<void> unsave(List<String> ids) async {
    final externalIds = ids.where((id) => !_isTelegramId(id)).toList();
    if (externalIds.isNotEmpty) {
      await _safeVoid(() async {
        await external.unsave(externalIds);
      });
    }
  }
}

class _HybridPlaylistEndpoint {
  final dynamic telegram;
  final dynamic external;

  _HybridPlaylistEndpoint(this.telegram, this.external);

  Future<SpotubeFullPlaylistObject> getPlaylist(String id) async {
    if (id == _telegramPlaylistId || _isTelegramId(id)) {
      return await telegram.getPlaylist(id);
    }
    return await _safeFuture(
      () async => await external.getPlaylist(id) as SpotubeFullPlaylistObject,
      _fallbackPlaylist(id),
    );
  }

  Future<SpotubePaginationResponseObject<SpotubeFullTrackObject>> tracks(
    String id, {
    int? offset,
    int? limit,
  }) async {
    if (id == _telegramPlaylistId || _isTelegramId(id)) {
      return await telegram.tracks(id, offset: offset, limit: limit);
    }
    return await _safeFuture(
      () async => await external.tracks(
        id,
        offset: offset,
        limit: limit,
      ) as SpotubePaginationResponseObject<SpotubeFullTrackObject>,
      _paginate(const <SpotubeFullTrackObject>[], offset: offset, limit: limit),
    );
  }

  Future<SpotubeFullPlaylistObject?> create(
    String userId, {
    required String name,
    String? description,
    bool? public,
    bool? collaborative,
  }) async {
    return await _safeFuture<SpotubeFullPlaylistObject?>(
      () async => await external.create(
        userId,
        name: name,
        description: description,
        public: public,
        collaborative: collaborative,
      ) as SpotubeFullPlaylistObject?,
      null,
    );
  }

  Future<void> update(
    String playlistId, {
    String? name,
    String? description,
    bool? public,
    bool? collaborative,
  }) async {
    if (playlistId == _telegramPlaylistId || _isTelegramId(playlistId)) return;
    await _safeVoid(
      () async {
        await external.update(
          playlistId,
          name: name,
          description: description,
          public: public,
          collaborative: collaborative,
        );
      },
    );
  }

  Future<void> addTracks(
    String playlistId, {
    required List<String> trackIds,
    int? position,
  }) async {
    if (playlistId == _telegramPlaylistId || _isTelegramId(playlistId)) return;
    await _safeVoid(
      () async {
        await external.addTracks(
          playlistId,
          trackIds: trackIds.where((id) => !_isTelegramId(id)).toList(),
          position: position,
        );
      },
    );
  }

  Future<void> removeTracks(
    String playlistId, {
    required List<String> trackIds,
  }) async {
    if (playlistId == _telegramPlaylistId || _isTelegramId(playlistId)) return;
    await _safeVoid(
      () async {
        await external.removeTracks(
          playlistId,
          trackIds: trackIds.where((id) => !_isTelegramId(id)).toList(),
        );
      },
    );
  }

  Future<void> save(String playlistId) async {
    if (playlistId == _telegramPlaylistId || _isTelegramId(playlistId)) return;
    await _safeVoid(() async {
      await external.save(playlistId);
    });
  }

  Future<void> unsave(String playlistId) async {
    if (playlistId == _telegramPlaylistId || _isTelegramId(playlistId)) return;
    await _safeVoid(() async {
      await external.unsave(playlistId);
    });
  }

  Future<void> deletePlaylist(String playlistId) async {
    if (playlistId == _telegramPlaylistId || _isTelegramId(playlistId)) return;
    await _safeVoid(() async {
      await external.deletePlaylist(playlistId);
    });
  }
}

class _HybridCoreEndpoint {
  final dynamic telegram;
  final dynamic external;

  _HybridCoreEndpoint(this.telegram, this.external);

  Future<PluginUpdateAvailable?> checkUpdate(
    PluginConfiguration pluginConfig,
  ) async {
    return await _safeFuture<PluginUpdateAvailable?>(
      () async =>
          await external.checkUpdate(pluginConfig) as PluginUpdateAvailable?,
      null,
    );
  }

  Future<String> get support async {
    final telegramSupport = await telegram.support as String;
    final externalSupport = await _safeFuture<String>(
      () async => await external.support as String,
      "",
    );
    return externalSupport.trim().isEmpty
        ? telegramSupport
        : "$telegramSupport\n\n$externalSupport";
  }

  Future<void> scrobble(Map<String, dynamic> details) async {
    await _safeVoid(() async {
      await external.scrobble(details);
    });
  }
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
    final likedIds =
        await ref.read(telegramMediaServiceProvider).loadLikedTrackIds();
    final tracks = (await ref.read(telegramMediaTracksProvider.future))
        .where((track) => likedIds.contains(track.id))
        .toList();
    return _paginate(
      tracks,
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
    final savedIds =
        await ref.read(telegramMediaServiceProvider).loadLikedTrackIds();
    return ids.map((id) => savedIds.contains(id)).toList();
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

  Future<void> save(List<String> ids) async {
    await ref.read(telegramMediaServiceProvider).addLikedTrackIds(ids);
  }

  Future<void> unsave(List<String> ids) async {
    await ref.read(telegramMediaServiceProvider).removeLikedTrackIds(ids);
  }

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

bool _isTelegramId(String id) {
  return id.startsWith("telegram:");
}

SpotubeSearchResponseObject _emptySearch() {
  return SpotubeSearchResponseObject(
    albums: const [],
    artists: const [],
    playlists: const [],
    tracks: const [],
  );
}

bool _isSearchableMusicVideo(dynamic video, String query) {
  final duration = _videoDuration(video);
  if (duration == null ||
      duration < const Duration(seconds: 35) ||
      duration > const Duration(minutes: 18)) {
    return false;
  }

  final title = _normalizeText(_videoTitle(video));
  final normalizedQuery = _normalizeText(query);
  final queryTokens = normalizedQuery
      .split(RegExp(r"\s+"))
      .where((token) => token.length > 2)
      .toList();
  if (queryTokens.isEmpty) return true;

  final matched = queryTokens.where((token) => title.contains(token)).length;
  return matched >= (queryTokens.length == 1 ? 1 : 2) ||
      matched >= (queryTokens.length / 2).ceil() ||
      title.contains("music") ||
      title.contains("audio") ||
      title.contains("lyric");
}

SpotubeFullTrackObject _youtubeVideoToTrack(dynamic video) {
  final videoId = _videoId(video);
  final rawTitle = _videoTitle(video);
  final author = _videoAuthor(video);
  final parsed = _splitVideoTitle(rawTitle, author);
  final artist = SpotubeSimpleArtistObject(
    id: "youtube:artist:${parsed.artist}",
    name: parsed.artist,
    externalUri: "https://music.youtube.com/search?q=${Uri.encodeComponent(
      parsed.artist,
    )}",
  );

  return SpotubeTrackObject.full(
    id: "youtube:$videoId",
    name: parsed.title,
    externalUri: _videoExternalUri(videoId),
    artists: [artist],
    album: SpotubeSimpleAlbumObject(
      id: "youtube:album:$videoId",
      name: "YouTube Music",
      externalUri: _videoExternalUri(videoId),
      artists: [artist],
      images: [
        SpotubeImageObject(
          url: "https://i.ytimg.com/vi/$videoId/hqdefault.jpg",
          height: 480,
          width: 480,
        ),
      ],
      albumType: SpotubeAlbumType.single,
      releaseDate: DateTime.now().year.toString(),
    ),
    durationMs:
        (_videoDuration(video) ?? const Duration(minutes: 3)).inMilliseconds,
    isrc: "",
    explicit: false,
  ) as SpotubeFullTrackObject;
}

({String artist, String title}) _splitVideoTitle(String title, String author) {
  final normalized = title
      .replaceAll(RegExp(r"\[[^\]]+\]"), "")
      .replaceAll(RegExp(r"\([Oo]fficial[^)]*\)"), "")
      .replaceAll(RegExp(r"\([Ll]yrics?[^)]*\)"), "")
      .replaceAll(RegExp(r"\([Aa]udio[^)]*\)"), "")
      .trim();
  final parts = normalized.split(RegExp(r"\s+-\s+"));
  if (parts.length >= 2 && parts.first.trim().isNotEmpty) {
    return (artist: parts.first.trim(), title: parts.skip(1).join(" - ").trim());
  }
  return (
    artist: author.trim().isEmpty ? "YouTube Music" : author.trim(),
    title: normalized.isEmpty ? title : normalized,
  );
}

String _videoId(dynamic video) {
  try {
    return video.id.value as String;
  } catch (_) {
    return video.id.toString();
  }
}

String _videoTitle(dynamic video) {
  try {
    return video.title as String;
  } catch (_) {
    return "YouTube track";
  }
}

String _videoAuthor(dynamic video) {
  try {
    return video.author as String;
  } catch (_) {
    return "YouTube Music";
  }
}

Duration? _videoDuration(dynamic video) {
  try {
    return video.duration as Duration?;
  } catch (_) {
    return null;
  }
}

String _videoExternalUri(String videoId) {
  return "https://music.youtube.com/watch?v=$videoId";
}

String _normalizeText(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-zа-яё0-9]+", unicode: true), " ")
      .trim();
}

SpotubeSimpleArtistObject _fallbackSimpleArtist(String id) {
  return SpotubeSimpleArtistObject(
    id: id,
    name: "Недоступно",
    externalUri: id,
  );
}

SpotubeFullArtistObject _fallbackArtist(String id) {
  return SpotubeFullArtistObject(
    id: id,
    name: "Недоступно",
    externalUri: id,
    images: const [],
  );
}

SpotubeSimpleAlbumObject _fallbackSimpleAlbum(String id) {
  return SpotubeSimpleAlbumObject(
    id: id,
    name: "Недоступный альбом",
    externalUri: id,
    artists: [_fallbackSimpleArtist("external:unavailable")],
    images: const [],
    albumType: SpotubeAlbumType.album,
    releaseDate: DateTime.now().year.toString(),
  );
}

SpotubeFullAlbumObject _fallbackAlbum(String id) {
  return SpotubeFullAlbumObject(
    id: id,
    name: "Недоступный альбом",
    artists: [_fallbackSimpleArtist("external:unavailable")],
    images: const [],
    releaseDate: DateTime.now().year.toString(),
    externalUri: id,
    totalTracks: 0,
    albumType: SpotubeAlbumType.album,
  );
}

SpotubeFullTrackObject _fallbackTrack(String id) {
  return SpotubeTrackObject.full(
    id: id,
    name: "Недоступный трек",
    externalUri: id,
    artists: [_fallbackSimpleArtist("external:unavailable")],
    album: _fallbackSimpleAlbum("external:unavailable-album"),
    durationMs: 0,
    isrc: "",
    explicit: false,
  ) as SpotubeFullTrackObject;
}

SpotubeUserObject _fallbackUser() {
  return SpotubeUserObject(
    id: "external:unavailable-user",
    name: "ETGmusic",
    externalUri: "etgmusic://external",
    images: const [],
  );
}

SpotubeFullPlaylistObject _fallbackPlaylist(String id) {
  return SpotubeFullPlaylistObject(
    id: id,
    name: "Недоступный плейлист",
    description: "",
    externalUri: id,
    owner: _fallbackUser(),
    images: const [],
    collaborative: false,
    public: false,
  );
}

List<T> _dedupeById<T>(List<T> items, String Function(T item) idOf) {
  final seen = <String>{};
  return items.where((item) => seen.add(idOf(item))).toList();
}

Future<T> _safeFuture<T>(Future<T> Function() task, T fallback) async {
  try {
    return await task();
  } catch (_) {
    return fallback;
  }
}

Future<void> _safeVoid(Future<void> Function() task) async {
  try {
    await task();
  } catch (_) {}
}

T _safeSync<T>(T Function() task, T fallback) {
  try {
    return task();
  } catch (_) {
    return fallback;
  }
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
