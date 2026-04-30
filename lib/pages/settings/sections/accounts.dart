import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart' show ListTile, Wrap;

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';
import 'package:etgmusic/collections/routes.gr.dart';
import 'package:etgmusic/collections/spotube_icons.dart';
import 'package:etgmusic/modules/settings/section_card_with_heading.dart';
import 'package:etgmusic/extensions/context.dart';
import 'package:etgmusic/provider/scrobbler/scrobbler.dart';
import 'package:etgmusic/provider/telegram/telegram_auth.dart';
import 'package:etgmusic/services/telegram/telegram_media.dart';

class SettingsAccountSection extends HookConsumerWidget {
  const SettingsAccountSection({super.key});

  @override
  Widget build(context, ref) {
    final scrobbler = ref.watch(scrobblerProvider);

    return SectionCardWithHeading(
      heading: context.l10n.account,
      children: [
        const TelegramAccountTile(),
        ListTile(
          leading: const Icon(SpotubeIcons.extensions),
          title: Text(context.l10n.plugins),
          subtitle: Text(context.l10n.configure_plugins),
          onTap: () {
            context.pushRoute(const SettingsMetadataProviderRoute());
          },
          trailing: const Icon(SpotubeIcons.angleRight),
        ),
        if (scrobbler.asData?.value == null)
          ListTile(
            leading: const Icon(SpotubeIcons.music),
            title: Text(context.l10n.audio_scrobblers),
            onTap: () {
              context.pushRoute(const SettingsScrobblingRoute());
            },
            trailing: const Icon(SpotubeIcons.angleRight),
          )
        else
          ListTile(
            leading: const Icon(SpotubeIcons.lastFm),
            title: Text(context.l10n.disconnect_lastfm),
            trailing: Button.destructive(
              onPressed: () {
                ref.read(scrobblerProvider.notifier).logout();
              },
              child: Text(context.l10n.disconnect),
            ),
          ),
      ],
    );
  }
}

class TelegramAccountTile extends HookConsumerWidget {
  const TelegramAccountTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(telegramAuthProvider);
    final filters = ref.watch(telegramSourceFiltersProvider);
    final tracks = ref.watch(telegramMediaTracksProvider);
    final tokenController = useTextEditingController();
    final sourcesController = useTextEditingController();
    final showToken = useState(false);
    final syncing = useState(false);

    useEffect(() {
      final value = filters.asData?.value;
      if (value != null && sourcesController.text.isEmpty) {
        sourcesController.text = value.join("\n");
      }
      return null;
    }, [filters.asData?.value.join("\n")]);

    Future<void> connect() async {
      try {
        await ref
            .read(telegramAuthProvider.notifier)
            .connectBot(tokenController.text);
        tokenController.clear();
        if (!context.mounted) return;
        _showTelegramToast(context, "Telegram подключен");
      } catch (e) {
        if (!context.mounted) return;
        _showTelegramToast(context, e.toString(), error: true);
      }
    }

    Future<void> disconnect() async {
      await ref.read(telegramAuthProvider.notifier).disconnect();
      if (!context.mounted) return;
      _showTelegramToast(context, "Telegram отключен");
    }

    Future<void> saveSources() async {
      await ref
          .read(telegramMediaServiceProvider)
          .setSourceFiltersFromText(sourcesController.text);
      if (!context.mounted) return;
      _showTelegramToast(context, "Источники Telegram сохранены");
    }

    Future<void> syncTelegram() async {
      try {
        syncing.value = true;
        final result =
            await ref.read(telegramMediaServiceProvider).syncBotUpdates();
        if (!context.mounted) return;
        _showTelegramToast(
          context,
          "Синхронизация: +${result.added}, всего ${result.total}",
        );
      } catch (e) {
        if (!context.mounted) return;
        _showTelegramToast(context, e.toString(), error: true);
      } finally {
        syncing.value = false;
      }
    }

    final value = auth.asData?.value ?? const TelegramAuthState();
    final loading = auth.isLoading;

    return Card(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 14,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              const Icon(SpotubeIcons.message),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [
                    const Text("Telegram").semiBold(),
                    Text(
                      value.title,
                      style: context.theme.typography.small,
                    ),
                    Text(
                      value.subtitle,
                      style: context.theme.typography.xSmall.copyWith(
                        color: context.theme.colorScheme.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              if (value.isConnected)
                Button.destructive(
                  enabled: !loading,
                  onPressed: disconnect,
                  child: const Text("Отключить"),
                ),
            ],
          ),
          if (!value.isConnected) ...[
            TextField(
              controller: tokenController,
              obscureText: !showToken.value,
              placeholder: const Text("Bot API token из @BotFather"),
              features: [
                InputFeature.trailing(
                  IconButton.ghost(
                    icon: Icon(
                      showToken.value ? SpotubeIcons.eye : SpotubeIcons.noEye,
                    ),
                    onPressed: () => showToken.value = !showToken.value,
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                Button.primary(
                  enabled: !loading,
                  onPressed: connect,
                  leading: loading
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(SpotubeIcons.login),
                  child: const Text("Подключить Telegram"),
                ),
                Expanded(
                  child: Text(
                    "Токен хранится локально. Для каналов и групп добавь бота туда, где ETGmusic должен искать треки.",
                    style: context.theme.typography.xSmall.copyWith(
                      color: context.theme.colorScheme.mutedForeground,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (value.isConnected) ...[
            TextField(
              controller: sourcesController,
              placeholder: const Text(
                "Источники: @channel, -1001234567890, название группы",
              ),
            ),
            Row(
              spacing: 10,
              children: [
                Button.secondary(
                  enabled: !loading,
                  onPressed: saveSources,
                  leading: const Icon(SpotubeIcons.save),
                  child: const Text("Сохранить источники"),
                ),
                Button.primary(
                  enabled: !syncing.value,
                  onPressed: syncTelegram,
                  leading: syncing.value
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(SpotubeIcons.refresh),
                  child: const Text("Синхронизировать"),
                ),
              ],
            ),
            Text(
              "В библиотеке Telegram: ${tracks.asData?.value.length ?? 0}. Если поле источников пустое, берутся все каналы и группы, где бот видит новые аудио.",
              style: context.theme.typography.xSmall.copyWith(
                color: context.theme.colorScheme.mutedForeground,
              ),
            ),
            Text(
              "Bot API не выгружает старую историю канала. Для старых треков перешли их заново после добавления бота или используй будущий MTProto-вход через пользовательскую сессию.",
              style: context.theme.typography.xSmall.copyWith(
                color: context.theme.colorScheme.mutedForeground,
              ),
            ),
          ],
          if (auth.hasError)
            Text(
              auth.error.toString(),
              style: TextStyle(color: context.theme.colorScheme.destructive),
            ),
        ],
      ),
    );
  }

  void _showTelegramToast(
    BuildContext context,
    String message, {
    bool error = false,
  }) {
    showToast(
      context: context,
      builder: (context, overlay) => SurfaceCard(
        child: Basic(
          leading: Icon(
            error ? SpotubeIcons.error : SpotubeIcons.done,
            color: error ? Colors.red : Colors.green,
          ),
          title: Text(message),
        ),
      ),
    );
  }
}
