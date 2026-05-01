import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:etgmusic/models/metadata/metadata.dart';
import 'package:etgmusic/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:etgmusic/provider/metadata_plugin/utils/family_paginated.dart';
import 'package:etgmusic/provider/metadata_plugin/utils/common.dart';
import 'package:etgmusic/services/telegram/telegram_media.dart';

class MetadataPluginAlbumTracksNotifier
    extends AutoDisposeFamilyPaginatedAsyncNotifier<SpotubeFullTrackObject,
        String> {
  MetadataPluginAlbumTracksNotifier() : super();

  @override
  fetch(offset, limit) async {
    final tracks = await (await metadataPlugin).album.tracks(
          arg,
          offset: offset,
          limit: limit,
        );

    return tracks;
  }

  @override
  build(arg) async {
    ref.cacheFor();

    ref.watch(metadataPluginProvider);
    ref.watch(telegramMediaRevisionProvider);
    return await fetch(0, 20);
  }
}

final metadataPluginAlbumTracksProvider =
    AutoDisposeAsyncNotifierProviderFamily<MetadataPluginAlbumTracksNotifier,
        SpotubePaginationResponseObject<SpotubeFullTrackObject>, String>(
  () => MetadataPluginAlbumTracksNotifier(),
);
