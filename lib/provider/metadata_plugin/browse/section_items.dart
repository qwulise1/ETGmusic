import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:etgmusic/models/metadata/metadata.dart';
import 'package:etgmusic/provider/metadata_plugin/core/auth.dart';
import 'package:etgmusic/provider/metadata_plugin/utils/family_paginated.dart';
import 'package:etgmusic/services/telegram/telegram_media.dart';

class MetadataPluginBrowseSectionItemsNotifier
    extends FamilyPaginatedAsyncNotifier<Object, String> {
  @override
  Future<SpotubePaginationResponseObject<Object>> fetch(
    int offset,
    int limit,
  ) async {
    return await (await metadataPlugin).browse.sectionItems(
          arg,
          limit: limit,
          offset: offset,
        );
  }

  @override
  build(arg) async {
    ref.watch(metadataPluginAuthenticatedProvider);
    ref.watch(telegramMediaRevisionProvider);
    return await fetch(0, 20);
  }
}

final metadataPluginBrowseSectionItemsProvider = AsyncNotifierProviderFamily<
    MetadataPluginBrowseSectionItemsNotifier,
    SpotubePaginationResponseObject<Object>,
    String>(
  () => MetadataPluginBrowseSectionItemsNotifier(),
);
