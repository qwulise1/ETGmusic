# ETGmusic

ETGmusic is a Telegram-first music player adapted by **@qwulise** and rebuilt
on top of the open-source Spotube codebase.

The goal is a single Android app for streaming, local music, lyrics, downloads,
metadata/audio-source plugins, Telegram music sources, and scrobblers.

## Current Android Build

- Package: `io.qwulise1.etgmusic`
- App name: `ETGmusic`
- Latest APK: https://github.com/qwulise1/ETGmusic/releases/tag/latest
- CI: https://github.com/qwulise1/ETGmusic/actions/workflows/build_apk.yml

## Telegram

The app now has a Telegram account block in settings. It validates a Bot API
token through Telegram `getMe`, stores the token locally, and keeps the existing
plugin/scrobbling system untouched.

For group/channel sources, add the bot to the target Telegram chat first. Full
user-session MTProto parsing is a separate layer and should be implemented on
top of this auth foundation, not mixed into the existing Spotube plugin core.

## Attribution

This product includes software developed by Kingkor Roy Tirtho.

Upstream source: https://github.com/KRTirtho/spotube

License: BSD-4-Clause, preserved in [LICENSE](LICENSE).
