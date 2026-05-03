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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.primary.withValues(alpha: 0.26),
                theme.colorScheme.secondary.withValues(alpha: 0.16),
                theme.colorScheme.card.withValues(alpha: 0.94),
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -46,
                top: -44,
                child: _HeroOrb(
                  color: theme.colorScheme.primary.withValues(alpha: 0.18),
                  size: 150,
                ),
              ),
              Positioned(
                left: -36,
                bottom: -52,
                child: _HeroOrb(
                  color: theme.colorScheme.secondary.withValues(alpha: 0.16),
                  size: 130,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(22),
                child: Wrap(
                  spacing: 18,
                  runSpacing: 18,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "ETGmusic",
                            style: theme.typography.h2.copyWith(
                              fontFamily: "Cookie",
                              fontSize: 48,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const Gap(6),
                          Text(
                            "Telegram, YouTube Music, локальные альбомы, офлайн-тексты и нормальный стриминг в одном месте.",
                            style: theme.typography.normal.copyWith(
                              color: theme.colorScheme.mutedForeground,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Gap(14),
                          const Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _HeroPill("Telegram"),
                              _HeroPill("YouTube Music"),
                              _HeroPill("Offline lyrics"),
                            ],
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
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroOrb extends StatelessWidget {
  final Color color;
  final double size;

  const _HeroOrb({
    required this.color,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  final String text;

  const _HeroPill(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(100),
        color: theme.colorScheme.background.withValues(alpha: 0.52),
        border: Border.all(
          color: theme.colorScheme.border.withValues(alpha: 0.45),
        ),
      ),
      child: Text(
        text,
        style: theme.typography.xSmall.copyWith(
          fontWeight: FontWeight.w800,
          color: theme.colorScheme.foreground,
        ),
      ),
    );
  }
}
