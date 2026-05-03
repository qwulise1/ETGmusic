import 'package:flutter/services.dart';
import 'package:collection/collection.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:etgmusic/collections/routes.gr.dart';

import 'package:etgmusic/collections/spotube_icons.dart';
import 'package:etgmusic/components/fallbacks/error_box.dart';
import 'package:etgmusic/components/fallbacks/no_default_metadata_plugin.dart';
import 'package:etgmusic/components/titlebar/titlebar.dart';
import 'package:etgmusic/extensions/context.dart';
import 'package:etgmusic/hooks/controllers/use_shadcn_text_editing_controller.dart';
import 'package:etgmusic/pages/search/tabs/albums.dart';
import 'package:etgmusic/pages/search/tabs/all.dart';
import 'package:etgmusic/pages/search/tabs/artists.dart';
import 'package:etgmusic/pages/search/tabs/playlists.dart';
import 'package:etgmusic/pages/search/tabs/tracks.dart';
import 'package:etgmusic/provider/metadata_plugin/search/all.dart';
import 'package:etgmusic/services/kv_store/kv_store.dart';
import 'package:auto_route/auto_route.dart';
import 'package:etgmusic/services/metadata/errors/exceptions.dart';

final searchTermStateProvider = StateProvider<String>((ref) {
  return "";
});

@RoutePage()
class SearchPage extends HookConsumerWidget {
  static const name = "search";

  const SearchPage({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final controller = useShadcnTextEditingController();
    final focusNode = useFocusNode();

    final searchTerm = ref.watch(searchTermStateProvider);
    final searchChipSnapshot = ref.watch(metadataPluginSearchChipsProvider);
    final chips = searchChipSnapshot.asData?.value ?? const <String>[];
    final selectedChip = useState<String?>("all");

    ref.listen(
      metadataPluginSearchChipsProvider,
      (previous, next) {
        selectedChip.value = next.asData?.value.firstOrNull ?? "all";
      },
    );

    useEffect(() {
      controller.text = searchTerm;

      return null;
    }, []);

    void onSubmitted(String value) {
      ref.read(searchTermStateProvider.notifier).state = value;
      if (value.trim().isEmpty) {
        return;
      }
      KVStoreService.setRecentSearches(
        {
          value,
          ...KVStoreService.recentSearches,
        }.toList(),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        context.navigateTo(const HomeRoute());
      },
      child: SafeArea(
        bottom: false,
        child: Scaffold(
          headers: [
            if (kTitlebarVisible)
              const TitleBar(automaticallyImplyLeading: false, height: 30)
          ],
          child: Builder(builder: (context) {
            if (searchChipSnapshot.error
                case MetadataPluginException(
                  errorCode: MetadataPluginErrorCode.noDefaultMetadataPlugin,
                  message: _
                )) {
              return const NoDefaultMetadataPlugin();
            }

            if (searchChipSnapshot.hasError) {
              return ErrorBox(
                error: searchChipSnapshot.error!,
                onRetry: () {
                  ref.invalidate(metadataPluginSearchChipsProvider);
                },
              );
            }

            return Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        child: ListenableBuilder(
                            listenable: controller,
                            builder: (context, _) {
                              final suggestions = controller.text.isEmpty
                                  ? KVStoreService.recentSearches
                                  : KVStoreService.recentSearches
                                      .where(
                                        (s) =>
                                            weightedRatio(
                                              s.toLowerCase(),
                                              controller.text.toLowerCase(),
                                            ) >
                                            50,
                                      )
                                      .toList();

                              return KeyboardListener(
                                focusNode: focusNode,
                                autofocus: true,
                                onKeyEvent: (value) {
                                  final isEnter = value.logicalKey ==
                                      LogicalKeyboardKey.enter;

                                  if (isEnter) {
                                    onSubmitted(controller.text);
                                    focusNode.unfocus();
                                  }
                                },
                                child: AutoComplete(
                                  suggestions: suggestions.length <= 2
                                      ? [
                                          ...suggestions,
                                          "Twenty One Pilots",
                                          "Linkin Park",
                                          "d4vd"
                                        ]
                                      : suggestions,
                                  completer: (suggestion) => suggestion,
                                  mode: AutoCompleteMode.replaceAll,
                                  child: TextField(
                                    autofocus: true,
                                    controller: controller,
                                    features: [
                                      const InputFeature.leading(
                                        Icon(SpotubeIcons.search),
                                      ),
                                      InputFeature.trailing(
                                        AnimatedCrossFade(
                                          duration:
                                              const Duration(milliseconds: 300),
                                          crossFadeState:
                                              controller.text.isNotEmpty
                                                  ? CrossFadeState.showFirst
                                                  : CrossFadeState.showSecond,
                                          firstChild: IconButton.ghost(
                                            size: ButtonSize.small,
                                            icon:
                                                const Icon(SpotubeIcons.close),
                                            onPressed: () {
                                              controller.clear();
                                            },
                                          ),
                                          secondChild: const SizedBox.square(
                                              dimension: 28),
                                        ),
                                      )
                                    ],
                                    textInputAction: TextInputAction.search,
                                    placeholder: Text(context.l10n.search),
                                    onSubmitted: onSubmitted,
                                  ),
                                ),
                              );
                            }),
                      ),
                    ),
                  ],
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Row(
                    spacing: 8,
                    children: [
                      for (final chip in chips)
                          Chip(
                            style: selectedChip.value == chip
                                ? ButtonVariance.primary.copyWith(
                                    decoration: (context, states, value) {
                                      return ButtonVariance.primary
                                          .decoration(context, states)
                                          .copyWithIfBoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(100),
                                          );
                                    },
                                  )
                                : ButtonVariance.secondary.copyWith(
                                    decoration: (context, states, value) {
                                      return ButtonVariance.secondary
                                          .decoration(context, states)
                                          .copyWithIfBoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(100),
                                          );
                                    },
                                  ),
                            child: Text(_chipLabel(chip.toString())),
                            onPressed: () {
                              selectedChip.value = chip;
                            },
                          ),
                    ],
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: switch (selectedChip.value) {
                      "tracks" => const SearchPageTracksTab(),
                      "albums" => const SearchPageAlbumsTab(),
                      "artists" => const SearchPageArtistsTab(),
                      "playlists" => const SearchPagePlaylistsTab(),
                      _ => const SearchPageAllTab(),
                    },
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

String _chipLabel(String value) {
  if (value.isEmpty) return value;
  return "${value[0].toUpperCase()}${value.substring(1)}";
}
