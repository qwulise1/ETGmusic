import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart' show ListTile, TextInputType, Wrap;
import 'package:flutter/widgets.dart'
    show FocusManager, ValueKey, WidgetsBinding;

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
    final sourcesController = useTextEditingController();
    final showToken = useState(false);
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
        final cacheText = result.cached + result.failed > 0
            ? " · скачано ${result.cached}, ошибок ${result.failed}"
            : "";
        _showTelegramToast(
          context,
          "Синхронизация: +${result.added}, всего ${result.total}$cacheText",
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
              "Вход по номеру телефона. ETGmusic читает выбранные чаты и каналы через локальную MTProto-сессию; код и 2FA вводятся здесь.",
              style: context.theme.typography.xSmall.copyWith(
                color: context.theme.colorScheme.mutedForeground,
              ),
            ),
          ),
          if (!value.isBotConnected && !value.isUserSessionConnected) ...[
            Button.primary(
              enabled: !loading,
              onPressed: () => _openTelegramSessionDialog(context, value),
              leading: loading
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(SpotubeIcons.login),
              child: Text(
                value.isUserSessionPending
                    ? "Продолжить вход через Telegram"
                    : "Войти через Telegram-сессию",
              ),
            ),
            Text(
              "Код вводится в отдельном окне сразу после успешной отправки. Если на аккаунте есть 2FA, следующим шагом появится поле пароля.",
              style: context.theme.typography.xSmall.copyWith(
                color: context.theme.colorScheme.mutedForeground,
              ),
            ),
          ],
          if (value.isUserSessionConnected)
            Text(
              "Сессия активна. Ключ хранится на устройстве и будет использоваться после обновлений APK.",
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

  Future<void> _openTelegramSessionDialog(
    BuildContext context,
    TelegramAuthState value,
  ) async {
    final result = await showDialog<_TelegramSessionDialogResult>(
      context: context,
      builder: (context) => _TelegramSessionDialog(initialState: value),
    );

    if (!context.mounted || result == null) return;
    if (result == _TelegramSessionDialogResult.connected) {
      _showTelegramToast(context, "Telegram-сессия подключена");
    }
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

enum _TelegramSessionStep {
  credentials,
  code,
  password,
}

enum _TelegramSessionDialogResult {
  connected,
}

class _TelegramSessionDialog extends HookConsumerWidget {
  final TelegramAuthState initialState;

  const _TelegramSessionDialog({
    required this.initialState,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apiIdController = useTextEditingController();
    final apiHashController = useTextEditingController();
    final phoneController = useTextEditingController(
      text: initialState.phoneNumber ?? "",
    );
    final codeController = useTextEditingController();
    final passwordController = useTextEditingController();
    final codeFocusNode = useFocusNode();
    final passwordFocusNode = useFocusNode();
    final showApiHash = useState(false);
    final showPassword = useState(false);
    final submitting = useState(false);
    final error = useState<String?>(null);
    final passwordHint = useState(initialState.passwordHint);
    final step = useState(switch (initialState.sessionStatus) {
      TelegramSessionStatus.codeSent => _TelegramSessionStep.code,
      TelegramSessionStatus.passwordRequired => _TelegramSessionStep.password,
      _ => _TelegramSessionStep.credentials,
    });

    useEffect(() {
      if (step.value != _TelegramSessionStep.password) return null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        passwordFocusNode.requestFocus();
      });
      return null;
    }, [step.value]);

    Future<void> requestCode() async {
      final apiId = int.tryParse(apiIdController.text.trim());
      if (apiId == null) {
        error.value = "API ID должен быть числом";
        return;
      }

      submitting.value = true;
      error.value = null;
      try {
        await ref.read(telegramAuthProvider.notifier).startUserSession(
              apiId: apiId,
              apiHash: apiHashController.text,
              phoneNumber: phoneController.text,
            );
        codeController.clear();
        step.value = _TelegramSessionStep.code;
      } catch (e) {
        error.value = e.toString();
      } finally {
        if (context.mounted) submitting.value = false;
      }
    }

    Future<void> confirmCode() async {
      if (codeController.text.trim().isEmpty) {
        error.value = "Введи код из Telegram";
        return;
      }

      submitting.value = true;
      error.value = null;
      try {
        await ref
            .read(telegramAuthProvider.notifier)
            .submitUserSessionCode(codeController.text);
        final next = ref.read(telegramAuthProvider).asData?.value;
        if (next?.sessionStatus == TelegramSessionStatus.passwordRequired) {
          passwordHint.value = next?.passwordHint;
          passwordController.clear();
          FocusManager.instance.primaryFocus?.unfocus();
          step.value = _TelegramSessionStep.password;
          return;
        }
        if (context.mounted) {
          Navigator.of(context).pop(_TelegramSessionDialogResult.connected);
        }
      } catch (e) {
        error.value = e.toString();
      } finally {
        if (context.mounted) submitting.value = false;
      }
    }

    Future<void> confirmPassword() async {
      if (passwordController.text.trim().isEmpty) {
        error.value = "Введи пароль 2FA";
        return;
      }

      submitting.value = true;
      error.value = null;
      try {
        await ref
            .read(telegramAuthProvider.notifier)
            .submitUserSessionPassword(passwordController.text);
        if (context.mounted) {
          Navigator.of(context).pop(_TelegramSessionDialogResult.connected);
        }
      } catch (e) {
        error.value = e.toString();
      } finally {
        if (context.mounted) submitting.value = false;
      }
    }

    final title = switch (step.value) {
      _TelegramSessionStep.credentials => "Telegram-сессия",
      _TelegramSessionStep.code => "Код из Telegram",
      _TelegramSessionStep.password => "Пароль 2FA",
    };
    final actionText = switch (step.value) {
      _TelegramSessionStep.credentials => "Отправить код",
      _TelegramSessionStep.code => "Подтвердить код",
      _TelegramSessionStep.password => "Подтвердить 2FA",
    };
    final onAction = switch (step.value) {
      _TelegramSessionStep.credentials => requestCode,
      _TelegramSessionStep.code => confirmCode,
      _TelegramSessionStep.password => confirmPassword,
    };

    return AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Text(
            switch (step.value) {
              _TelegramSessionStep.credentials =>
                "Укажи API ID/API hash с my.telegram.org и номер телефона. После успешной отправки здесь же появится поле для кода.",
              _TelegramSessionStep.code =>
                "Код приходит в Telegram. Введи его сюда; если включена двухфакторка, следующим шагом появится пароль.",
              _TelegramSessionStep.password =>
                "Telegram запросил пароль 2FA${passwordHint.value == null ? "" : ". Подсказка: ${passwordHint.value}"}",
            },
            style: context.theme.typography.small.copyWith(
              color: context.theme.colorScheme.mutedForeground,
            ),
          ),
          if (step.value == _TelegramSessionStep.credentials) ...[
            TextField(
              controller: apiIdController,
              keyboardType: TextInputType.number,
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
              keyboardType: TextInputType.phone,
              placeholder: const Text("+79990000000"),
            ),
          ],
          if (step.value == _TelegramSessionStep.code)
            TextField(
              key: const ValueKey("telegram-session-code"),
              controller: codeController,
              focusNode: codeFocusNode,
              keyboardType: TextInputType.number,
              placeholder: const Text("Код из Telegram"),
            ),
          if (step.value == _TelegramSessionStep.password)
            TextField(
              key: const ValueKey("telegram-session-password"),
              controller: passwordController,
              focusNode: passwordFocusNode,
              keyboardType: TextInputType.visiblePassword,
              obscureText: !showPassword.value,
              placeholder: const Text("Пароль 2FA"),
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
          if (error.value != null)
            Text(
              error.value!,
              style: TextStyle(color: context.theme.colorScheme.destructive),
            ),
        ],
      ),
      actions: [
        Button.outline(
          enabled: !submitting.value,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("Закрыть"),
        ),
        Button.primary(
          enabled: !submitting.value,
          onPressed: onAction,
          leading: submitting.value
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(SpotubeIcons.login),
          child: Text(actionText),
        ),
      ],
    );
  }
}
