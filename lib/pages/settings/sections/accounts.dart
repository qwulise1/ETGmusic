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
import 'package:etgmusic/provider/telegram/telegram_auth.dart';
import 'package:etgmusic/services/telegram/telegram_media.dart';

class SettingsAccountSection extends HookConsumerWidget {
  const SettingsAccountSection({super.key});

  @override
  Widget build(context, ref) {
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
        ListTile(
          leading: const Icon(SpotubeIcons.music),
          title: Text(context.l10n.audio_scrobblers),
          onTap: () {
            context.pushRoute(const SettingsScrobblingRoute());
          },
          trailing: const Icon(SpotubeIcons.angleRight),
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
    final tokenController = useTextEditingController();
    final apiIdController = useTextEditingController();
    final apiHashController = useTextEditingController();
    final phoneController = useTextEditingController();
    final codeController = useTextEditingController();
    final passwordController = useTextEditingController();
    final sourcesController = useTextEditingController();
    final showToken = useState(false);
    final showApiHash = useState(false);
    final showPassword = useState(false);
    final syncing = useState(false);
    final filtersText = filters.asData?.value.join("\n") ?? "";

    useEffect(() {
      if (filters.asData != null && sourcesController.text != filtersText) {
        sourcesController.text = filtersText;
      }
      return null;
    }, [filtersText, filters.asData != null]);

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

    Future<void> startSession() async {
      try {
        final apiId = int.tryParse(apiIdController.text.trim());
        if (apiId == null) {
          throw const TelegramAuthException("API ID должен быть числом");
        }
        await ref.read(telegramAuthProvider.notifier).startUserSession(
              apiId: apiId,
              apiHash: apiHashController.text,
              phoneNumber: phoneController.text,
            );
        codeController.clear();
        if (!context.mounted) return;
        _showTelegramToast(context, "Код отправлен в Telegram");
      } catch (e) {
        if (!context.mounted) return;
        _showTelegramToast(context, e.toString(), error: true);
      }
    }

    Future<void> submitCode() async {
      try {
        await ref
            .read(telegramAuthProvider.notifier)
            .submitUserSessionCode(codeController.text);
        codeController.clear();
        if (!context.mounted) return;
        _showTelegramToast(context, "Telegram-сессия подключена");
      } catch (e) {
        if (!context.mounted) return;
        _showTelegramToast(context, e.toString(), error: true);
      }
    }

    Future<void> submitPassword() async {
      try {
        await ref
            .read(telegramAuthProvider.notifier)
            .submitUserSessionPassword(passwordController.text);
        passwordController.clear();
        if (!context.mounted) return;
        _showTelegramToast(context, "Telegram-сессия подключена");
      } catch (e) {
        if (!context.mounted) return;
        _showTelegramToast(context, e.toString(), error: true);
      }
    }

    Future<List<String>> saveSources({bool silent = false}) async {
      final saved = await ref
          .read(telegramMediaServiceProvider)
          .setSourceFiltersFromText(sourcesController.text);
      sourcesController.text = saved.join("\n");
      if (context.mounted && !silent) {
        _showTelegramToast(context, "Источники Telegram сохранены");
      }
      return saved;
    }

    Future<void> syncTelegram() async {
      try {
        syncing.value = true;
        await saveSources(silent: true);
        final authState = await ref.read(telegramAuthProvider.future);
        final result = authState.isUserSessionConnected
            ? await ref
                .read(telegramMediaServiceProvider)
                .syncUserSessionHistory()
            : await ref.read(telegramMediaServiceProvider).syncBotUpdates();
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
              ],
            ),
            Text(
              "Токен хранится локально. Для каналов и групп добавь бота туда, где ETGmusic должен искать треки.",
              style: context.theme.typography.xSmall.copyWith(
                color: context.theme.colorScheme.mutedForeground,
              ),
            ),
          ],
          const Divider(),
          Basic(
            leading: const Icon(SpotubeIcons.user),
            title: const Text("Telegram-сессия (MTProto)").semiBold(),
            subtitle: Text(
              "Вход через номер, код Telegram и 2FA. В active sessions устройство отправляется как ETGmusic; чтобы приложение в Telegram называлось ETGmusic, создай API app с таким названием на my.telegram.org.",
              style: context.theme.typography.xSmall.copyWith(
                color: context.theme.colorScheme.mutedForeground,
              ),
            ),
          ),
          if (!value.isBotConnected && value.mode != TelegramAuthMode.user) ...[
            TextField(
              controller: apiIdController,
              placeholder: const Text("Telegram API ID"),
            ),
            TextField(
              controller: apiHashController,
              obscureText: !showApiHash.value,
              placeholder: const Text("Telegram API hash"),
              features: [
                InputFeature.trailing(
                  IconButton.ghost(
                    icon: Icon(
                      showApiHash.value
                          ? SpotubeIcons.eye
                          : SpotubeIcons.noEye,
                    ),
                    onPressed: () => showApiHash.value = !showApiHash.value,
                  ),
                ),
              ],
            ),
            TextField(
              controller: phoneController,
              placeholder: const Text("+79990000000"),
            ),
            Button.primary(
              enabled: !loading,
              onPressed: startSession,
              leading: loading
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(SpotubeIcons.login),
              child: const Text("Получить код Telegram"),
            ),
          ],
          if (value.sessionStatus == TelegramSessionStatus.codeSent) ...[
            TextField(
              controller: codeController,
              placeholder: const Text("Код из Telegram"),
            ),
            Button.primary(
              enabled: !loading,
              onPressed: submitCode,
              leading: const Icon(SpotubeIcons.done),
              child: const Text("Подтвердить код"),
            ),
          ],
          if (value.sessionStatus == TelegramSessionStatus.passwordRequired) ...[
            TextField(
              controller: passwordController,
              obscureText: !showPassword.value,
              placeholder: Text(
                value.passwordHint == null
                    ? "Пароль 2FA"
                    : "Пароль 2FA, подсказка: ${value.passwordHint}",
              ),
              features: [
                InputFeature.trailing(
                  IconButton.ghost(
                    icon: Icon(
                      showPassword.value
                          ? SpotubeIcons.eye
                          : SpotubeIcons.noEye,
                    ),
                    onPressed: () => showPassword.value = !showPassword.value,
                  ),
                ),
              ],
            ),
            Button.primary(
              enabled: !loading,
              onPressed: submitPassword,
              leading: const Icon(SpotubeIcons.done),
              child: const Text("Подтвердить 2FA"),
            ),
          ],
          if (value.isUserSessionConnected)
            Text(
              "Telegram-сессия подключена, auth key сохранен локально. Для отображения в Telegram используй API app с названием ETGmusic.",
              style: context.theme.typography.xSmall.copyWith(
                color: context.theme.colorScheme.mutedForeground,
              ),
            ),
          if (value.isBotConnected || value.isUserSessionConnected) ...[
            TextField(
              controller: sourcesController,
              placeholder: const Text(
                "Источники: @channel, -1001234567890, me, название группы",
              ),
            ),
            Row(
              spacing: 10,
              children: [
                Button.secondary(
                  enabled: !loading,
                  onPressed: () => saveSources(),
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
              value.isUserSessionConnected
                  ? "Telegram-сессия читает историю указанных каналов/чатов. Если поле пустое, ETGmusic возьмет последние диалоги из аккаунта."
                  : "Если поле источников пустое, берутся все каналы и группы, где бот видит новые аудио.",
              style: context.theme.typography.xSmall.copyWith(
                color: context.theme.colorScheme.mutedForeground,
              ),
            ),
            if (value.isBotConnected)
              Text(
                "Bot API не выгружает старую историю канала. Для старых треков перешли их заново после добавления бота или войди через Telegram-сессию.",
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
