# ETGmusic

Native Android music player prototype by `@qwulise`.

This branch intentionally replaced the old Kivy/Buildozer runtime with a normal
Android Gradle application. The APK is built the same way as the voicechanger
project: Android Gradle Plugin on GitHub Actions, no Python UI runtime inside
the app.

Current native base:

- ViMusic/RiMusic-inspired original native UI with compact song rows, quick
  picks, search-first library, generated cover tiles, collapsed mini player and
  theme packs;
- local player built on Android `MediaPlayer`;
- direct HTTP audio stream support;
- Telegram Bot API scanner for audio messages from bot updates/channel posts;
- local favorites and albums;
- LRCLIB lyrics search plus manual lyrics/LRC;
- sleep timer;
- built-in themes;
- MTProxy/SOCKS settings storage for the next TDLib/MTProto core layer.

User-account Telegram history via StringSession requires a real Android TDLib or
MTProto core. The native UI keeps the slot for it, but the first stable native
build avoids shipping the old crashing Python/Telethon runtime.
