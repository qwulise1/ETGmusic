import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:etgmusic/collections/env.dart';
import 'package:etgmusic/components/button/back_button.dart';
import 'package:etgmusic/components/links/hyper_link.dart';
import 'package:etgmusic/components/titlebar/titlebar.dart';
import 'package:etgmusic/extensions/context.dart';
import 'package:etgmusic/hooks/controllers/use_package_info.dart';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:auto_route/auto_route.dart';

final _licenseProvider = FutureProvider<String>((ref) async {
  return await rootBundle.loadString("LICENSE");
});

@RoutePage()
class AboutSpotubePage extends HookConsumerWidget {
  static const name = "about";

  const AboutSpotubePage({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final packageInfo = usePackageInfo();
    final license = ref.watch(_licenseProvider);
    final theme = Theme.of(context);

    const colon = TableCell(child: Text(":"));

    return SafeArea(
      bottom: false,
      child: Scaffold(
        headers: [
          TitleBar(
            leading: const [BackButton()],
            title: Text(context.l10n.about_etgmusic),
          )
        ],
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              children: [
                Image.asset(
                  "assets/branding/etgmusic-logo.png",
                  height: 200,
                  width: 200,
                ),
                Center(
                  child: Column(
                    children: [
                      Text(context.l10n.etgmusic_description).semiBold().large(),
                      const SizedBox(height: 20),
                      Table(
                        columnWidths: const {
                          0: FixedTableSize(95),
                          1: FixedTableSize(10),
                          2: IntrinsicTableSize(),
                        },
                        defaultRowHeight: const FixedTableSize(40),
                        rows: [
                          TableRow(
                            cells: [
                              const TableCell(child: Text("ETGmusic")),
                              colon,
                              const TableCell(
                                child: Hyperlink("@qwulise", "https://t.me/qwulise"),
                              )
                            ],
                          ),
                          TableRow(
                            cells: [
                              TableCell(child: Text(context.l10n.version)),
                              colon,
                              TableCell(child: Text("v${packageInfo.version}"))
                            ],
                          ),
                          TableRow(
                            cells: [
                              TableCell(child: Text(context.l10n.channel)),
                              colon,
                              TableCell(child: Text(Env.releaseChannel.name))
                            ],
                          ),
                          TableRow(
                            cells: [
                              TableCell(child: Text(context.l10n.build_number)),
                              colon,
                              TableCell(
                                child: Text(packageInfo.buildNumber
                                    .replaceAll(".", " ")),
                              )
                            ],
                          ),
                          TableRow(
                            cells: [
                              const TableCell(child: Text("База")),
                              colon,
                              const TableCell(
                                child: Hyperlink(
                                  "Spotube",
                                  "https://github.com/KRTirtho/spotube",
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  "ETGmusic адаптирован под Telegram-музыку, локальную библиотеку, плагины и скробблеры. Основа Spotube и BSD-4-Clause лицензия сохранены.",
                  textAlign: TextAlign.center,
                  style: theme.typography.small,
                ),
                Text(
                  "Автор адаптации: @qwulise",
                  textAlign: TextAlign.center,
                  style: theme.typography.small,
                ),
                const SizedBox(height: 20),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 750),
                  child: SafeArea(
                    child: license.when(
                      data: (data) {
                        return Text(
                          data,
                          style: theme.typography.small,
                        );
                      },
                      loading: () {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      },
                      error: (e, s) {
                        return Text(
                          e.toString(),
                          style: theme.typography.small,
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
