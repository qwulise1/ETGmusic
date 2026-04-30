import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:etgmusic/components/links/anchor_button.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:etgmusic/extensions/context.dart';
import 'package:version/version.dart';

class RootAppUpdateDialog extends StatelessWidget {
  final Version? version;
  final int? nightlyBuildNum;

  const RootAppUpdateDialog({super.key, this.version}) : nightlyBuildNum = null;
  const RootAppUpdateDialog.nightly({super.key, required this.nightlyBuildNum})
      : version = null;

  @override
  Widget build(BuildContext context) {
    const url = "https://github.com/qwulise1/ETGmusic/releases/tag/latest";
    const nightlyUrl =
        "https://github.com/qwulise1/ETGmusic/actions/workflows/build_apk.yml";
    return AlertDialog(
      title: Text(context.l10n.etgmusic_has_an_update),
      actions: [
        Button.primary(
          child: Text(context.l10n.download_now),
          onPressed: () => launchUrlString(
            nightlyBuildNum != null ? nightlyUrl : url,
            mode: LaunchMode.externalApplication,
          ),
        ),
      ],
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            nightlyBuildNum != null
                ? context.l10n.nightly_version(nightlyBuildNum!)
                : context.l10n.release_version(version!),
          ),
          if (nightlyBuildNum == null)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(context.l10n.read_the_latest),
                AnchorButton(
                  context.l10n.release_notes,
                  style: const TextStyle(color: Colors.blue),
                  onTap: () => launchUrlString(
                    url,
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
