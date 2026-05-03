import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:etgmusic/components/fallbacks/error_box.dart';
import 'package:etgmusic/components/inter_scrollbar/inter_scrollbar.dart';
import 'package:etgmusic/modules/search/loading.dart';
import 'package:etgmusic/pages/search/search.dart';
import 'package:etgmusic/modules/search/sections/albums.dart';
import 'package:etgmusic/modules/search/sections/artists.dart';
import 'package:etgmusic/modules/search/sections/playlists.dart';
import 'package:etgmusic/modules/search/sections/tracks.dart';
import 'package:etgmusic/provider/metadata_plugin/search/all.dart';

class SearchPageAllTab extends HookConsumerWidget {
  const SearchPageAllTab({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final scrollController = ScrollController();
    final searchTerm = ref.watch(searchTermStateProvider);
    final searchSnapshot =
        ref.watch(metadataPluginSearchAllProvider(searchTerm));
    final result = searchSnapshot.asData?.value;
    final hasPlaylists = result?.playlists.isNotEmpty == true;
    final hasArtists = result?.artists.isNotEmpty == true;
    final hasAlbums = result?.albums.isNotEmpty == true;

    if (searchSnapshot.hasError) {
      return ErrorBox(
        error: searchSnapshot.error!,
        onRetry: () {
          ref.invalidate(metadataPluginSearchAllProvider(searchTerm));
        },
      );
    }

    return SearchPlaceholder(
      snapshot: searchSnapshot,
      child: InterScrollbar(
        controller: scrollController,
        child: SingleChildScrollView(
          controller: scrollController,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SearchTracksSection(),
                  if (hasPlaylists) ...[
                    const SearchPlaylistsSection(),
                    const Gap(20),
                  ],
                  if (hasArtists) ...[
                    const SearchArtistsSection(),
                    const Gap(20),
                  ],
                  if (hasAlbums) const SearchAlbumsSection(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
