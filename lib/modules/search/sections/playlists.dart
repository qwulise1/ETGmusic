import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:etgmusic/components/horizontal_playbutton_card_view/horizontal_playbutton_card_view.dart';
import 'package:etgmusic/extensions/context.dart';
import 'package:etgmusic/pages/search/search.dart';
import 'package:etgmusic/provider/metadata_plugin/search/all.dart';

class SearchPlaylistsSection extends HookConsumerWidget {
  const SearchPlaylistsSection({
    super.key,
  });

  @override
  Widget build(BuildContext context, ref) {
    final searchTerm = ref.watch(searchTermStateProvider);
    final playlistsQuery =
        ref.watch(metadataPluginSearchAllProvider(searchTerm));
    final playlists = playlistsQuery.asData?.value.playlists ?? [];

    return HorizontalPlaybuttonCardView(
      isLoadingNextPage: false,
      hasNextPage: false,
      items: playlists,
      onFetchMore: () {},
      title: Text(context.l10n.playlists),
    );
  }
}
