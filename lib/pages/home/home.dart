import 'package:auto_route/auto_route.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:etgmusic/collections/routes.gr.dart';
import 'package:etgmusic/collections/spotube_icons.dart';
import 'package:etgmusic/models/database/database.dart';
import 'package:etgmusic/modules/connect/connect_device.dart';
import 'package:etgmusic/modules/home/sections/featured.dart';
import 'package:etgmusic/modules/home/sections/sections.dart';
import 'package:etgmusic/modules/home/sections/new_releases.dart';
import 'package:etgmusic/modules/home/sections/recent.dart';
import 'package:etgmusic/components/titlebar/titlebar.dart';
import 'package:etgmusic/extensions/constrains.dart';
import 'package:etgmusic/provider/user_preferences/user_preferences_provider.dart';
import 'package:etgmusic/utils/platform.dart';

@RoutePage()
class HomePage extends HookConsumerWidget {
  static const name = "home";
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final theme = Theme.of(context);
    final controller = useScrollController();
    final mediaQuery = MediaQuery.of(context);
    final layoutMode =
        ref.watch(userPreferencesProvider.select((s) => s.layoutMode));

    return SafeArea(
        bottom: false,
        child: Scaffold(
          headers: [
            if (kTitlebarVisible) const TitleBar(height: 30),
          ],
          child: CustomScrollView(
            controller: controller,
            slivers: [
              if (mediaQuery.smAndDown || layoutMode == LayoutMode.compact)
                SliverAppBar(
                  floating: true,
                  title: DefaultTextStyle(
                    style: TextStyle(
                      fontFamily: "Cookie",
                      fontSize: 30,
                      letterSpacing: 1.8,
                      color: theme.colorScheme.foreground,
                    ),
                    child: const Text("ETGmusic"),
                  ),
                  backgroundColor: theme.colorScheme.background,
                  foregroundColor: theme.colorScheme.foreground,
                  actions: [
                    const ConnectDeviceButton(),
                    const Gap(10),
                    IconButton.ghost(
                      icon: const Icon(SpotubeIcons.settings, size: 20),
                      onPressed: () {
                        context.navigateTo(const SettingsRoute());
                      },
                    ),
                    const Gap(10),
                  ],
                )
              else if (kIsMacOS)
                const SliverGap(10),
              const SliverGap(10),
              const SliverToBoxAdapter(child: _HomeHero()),
              SliverList.builder(
                itemCount: 3,
                itemBuilder: (context, index) {
                  return switch (index) {
                    // 0 => const HomeGenresSection(),
                    0 => const HomeRecentlyPlayedSection(),
                    1 => const HomeFeaturedSection(),
                    // 3 => const HomePageFriendsSection(),
                    _ => const HomeNewReleasesSection()
                  };
                },
              ),
              const SliverSafeArea(sliver: HomePageBrowseSection()),
            ],
          ),
        ));
  }
}

class _HomeHero extends StatelessWidget {
  const _HomeHero();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
      child: SurfaceCard(
        padding: const EdgeInsets.all(18),
        borderRadius: BorderRadius.circular(30),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.primary.withValues(alpha: 0.28),
                theme.colorScheme.secondary.withValues(alpha: 0.14),
                theme.colorScheme.background.withValues(alpha: 0.04),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Wrap(
              spacing: 14,
              runSpacing: 14,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "ETGmusic",
                        style: theme.typography.h2.copyWith(
                          fontFamily: "Cookie",
                          fontSize: 44,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Gap(6),
                      Text(
                        "Telegram-библиотека, YouTube Music поиск, локальные альбомы и офлайн-тексты в одном плеере.",
                        style: theme.typography.normal.copyWith(
                          color: theme.colorScheme.mutedForeground,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Button.primary(
                      onPressed: () => context.navigateTo(const SearchRoute()),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(SpotubeIcons.search),
                          Gap(8),
                          Text("Найти трек"),
                        ],
                      ),
                    ),
                    Button.outline(
                      onPressed: () => context.navigateTo(const StatsRoute()),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(SpotubeIcons.chart),
                          Gap(8),
                          Text("Статистика"),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
