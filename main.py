import asyncio
import json
import re
import threading
from concurrent.futures import Future
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional

from kivy.clock import Clock
from kivy.core.audio import SoundLoader
from kivy.core.window import Window
from kivy.lang import Builder
from kivy.properties import BooleanProperty, NumericProperty, StringProperty
from kivy.uix.screenmanager import Screen, ScreenManager
from kivy.utils import platform
from kivymd.app import MDApp
from kivymd.uix.list import ThreeLineAvatarIconListItem
from telethon import TelegramClient, types as tg_types
from telethon.sessions import StringSession


KV = """
#:import dp kivy.metrics.dp

<TrackRow>:
    theme_bg_color: "Custom"
    md_bg_color: 0, 0, 0, 0
    divider: None
    on_release: app.on_track_selected(self.track_index)
    IconLeftWidget:
        icon: "music-note-outline"
        theme_text_color: "Custom"
        text_color: app.accent_rgb
    IconRightWidget:
        icon: "play-circle-outline"
        theme_text_color: "Custom"
        text_color: app.accent_rgb

<LibraryScreen>:
    MDBoxLayout:
        orientation: "vertical"
        spacing: dp(10)
        padding: dp(16), dp(14), dp(16), dp(10)

        MDBoxLayout:
            adaptive_height: True
            spacing: dp(10)

            MDBoxLayout:
                orientation: "vertical"
                adaptive_height: True

                MDLabel:
                    text: "ETGmusic"
                    font_style: "H4"
                    bold: True
                    theme_text_color: "Custom"
                    text_color: 0.95, 0.96, 0.98, 1

                MDLabel:
                    text: "Cybercore Telegram audio streaming"
                    adaptive_height: True
                    theme_text_color: "Secondary"

            Widget:

            MDRectangleFlatIconButton:
                text: "Player"
                icon: "play-network-outline"
                line_color: app.accent_rgb
                text_color: app.accent_rgb
                on_release: app.switch_screen("player")

        ScrollView:
            bar_width: dp(3)

            MDBoxLayout:
                orientation: "vertical"
                adaptive_height: True
                spacing: dp(12)
                padding: 0, 0, 0, dp(24)

                MDCard:
                    orientation: "vertical"
                    padding: dp(16)
                    spacing: dp(10)
                    radius: [28, 28, 28, 28]
                    theme_bg_color: "Custom"
                    md_bg_color: 0.08, 0.09, 0.12, 1
                    line_color: 0.12, 0.78, 0.58, 0.25
                    adaptive_height: True

                    MDLabel:
                        text: "Session bootstrap"
                        font_style: "H6"
                        adaptive_height: True
                        theme_text_color: "Custom"
                        text_color: 0.94, 0.97, 1, 1

                    MDLabel:
                        text: "Enter API ID / API Hash plus either StringSession or Bot Token."
                        adaptive_height: True
                        theme_text_color: "Secondary"

                    MDTextField:
                        id: api_id_input
                        hint_text: "API ID"
                        mode: "rectangle"
                        helper_text_mode: "persistent"
                        helper_text: "Required"
                        text: ""

                    MDTextField:
                        id: api_hash_input
                        hint_text: "API Hash"
                        mode: "rectangle"
                        helper_text_mode: "persistent"
                        helper_text: "Required"
                        text: ""

                    MDTextField:
                        id: string_session_input
                        hint_text: "StringSession"
                        mode: "rectangle"
                        helper_text_mode: "persistent"
                        helper_text: "Preferred for user account access"
                        multiline: True
                        max_height: dp(112)
                        text: ""

                    MDTextField:
                        id: bot_token_input
                        hint_text: "Bot Token"
                        mode: "rectangle"
                        helper_text_mode: "persistent"
                        helper_text: "Use if your bot is added to the music channel"
                        multiline: True
                        max_height: dp(86)
                        text: ""

                MDCard:
                    orientation: "vertical"
                    padding: dp(16)
                    spacing: dp(10)
                    radius: [28, 28, 28, 28]
                    theme_bg_color: "Custom"
                    md_bg_color: 0.08, 0.09, 0.12, 1
                    line_color: 0.12, 0.78, 0.58, 0.25
                    adaptive_height: True

                    MDLabel:
                        text: "Telegram source"
                        font_style: "H6"
                        adaptive_height: True
                        theme_text_color: "Custom"
                        text_color: 0.94, 0.97, 1, 1

                    MDTextField:
                        id: channel_input
                        hint_text: "Channel username / invite / numeric ID"
                        mode: "rectangle"
                        helper_text_mode: "persistent"
                        helper_text: "Example: @etg_music"
                        text: ""

                    MDBoxLayout:
                        adaptive_height: True
                        spacing: dp(8)

                        MDRaisedButton:
                            text: "Connect"
                            md_bg_color: app.accent_rgb
                            on_release: app.on_connect_pressed()

                        MDRectangleFlatButton:
                            text: "Refresh"
                            text_color: app.accent_rgb
                            line_color: app.accent_rgb
                            on_release: app.on_refresh_pressed()

                        MDRectangleFlatButton:
                            text: "Disconnect"
                            text_color: 0.83, 0.38, 0.48, 1
                            line_color: 0.83, 0.38, 0.48, 1
                            on_release: app.on_disconnect_pressed()

                    MDLabel:
                        text: app.status_text
                        adaptive_height: True
                        theme_text_color: "Custom"
                        text_color: 0.76, 0.8, 0.86, 1

                MDCard:
                    orientation: "vertical"
                    padding: dp(14)
                    spacing: dp(8)
                    radius: [28, 28, 28, 28]
                    theme_bg_color: "Custom"
                    md_bg_color: 0.06, 0.07, 0.1, 1
                    line_color: 0.12, 0.78, 0.58, 0.18
                    adaptive_height: True

                    MDBoxLayout:
                        adaptive_height: True
                        spacing: dp(8)

                        MDLabel:
                            text: "Track grid"
                            font_style: "H6"
                            adaptive_height: True
                            theme_text_color: "Custom"
                            text_color: 0.94, 0.97, 1, 1

                        Widget:

                        MDLabel:
                            text: app.track_counter_text
                            adaptive_height: True
                            halign: "right"
                            theme_text_color: "Secondary"

                    MDLabel:
                        text: app.channel_status_text
                        adaptive_height: True
                        theme_text_color: "Secondary"

                    MDList:
                        id: track_list

<PlayerScreen>:
    MDBoxLayout:
        orientation: "vertical"
        spacing: dp(14)
        padding: dp(20), dp(16), dp(20), dp(16)

        MDBoxLayout:
            adaptive_height: True
            spacing: dp(8)

            MDRectangleFlatIconButton:
                text: "Library"
                icon: "arrow-left"
                line_color: app.accent_rgb
                text_color: app.accent_rgb
                on_release: app.switch_screen("library")

            Widget:

            MDLabel:
                text: "Now Playing"
                adaptive_height: True
                halign: "right"
                theme_text_color: "Secondary"

        Widget:
            size_hint_y: 0.06

        MDCard:
            size_hint: None, None
            size: dp(290), dp(290)
            pos_hint: {"center_x": 0.5}
            radius: [42, 42, 42, 42]
            theme_bg_color: "Custom"
            md_bg_color: 0.1, 0.12, 0.16, 1
            line_color: app.accent_rgb

            MDBoxLayout:
                orientation: "vertical"
                padding: dp(16)

                Widget:

                MDIcon:
                    icon: "waveform"
                    halign: "center"
                    font_size: "82sp"
                    theme_text_color: "Custom"
                    text_color: app.accent_rgb

                MDLabel:
                    text: "Telegram Stream"
                    halign: "center"
                    adaptive_height: True
                    theme_text_color: "Custom"
                    text_color: 0.9, 0.95, 0.98, 1

                Widget:

        Widget:
            size_hint_y: 0.03

        MDLabel:
            text: app.current_title
            halign: "center"
            font_style: "H5"
            bold: True
            adaptive_height: True
            theme_text_color: "Custom"
            text_color: 0.96, 0.97, 0.98, 1

        MDLabel:
            text: app.current_artist
            halign: "center"
            adaptive_height: True
            theme_text_color: "Secondary"

        MDLabel:
            text: app.player_state_text
            halign: "center"
            adaptive_height: True
            theme_text_color: "Custom"
            text_color: app.accent_rgb

        MDSlider:
            id: seek_slider
            min: 0
            max: max(1, app.track_duration)
            value: app.track_position
            color: app.accent_rgb
            on_touch_up: app.on_seek_released(self, args[1])

        MDBoxLayout:
            adaptive_height: True

            MDLabel:
                text: app.position_label
                adaptive_height: True
                theme_text_color: "Secondary"

            Widget:

            MDLabel:
                text: app.duration_label
                adaptive_height: True
                halign: "right"
                theme_text_color: "Secondary"

        MDBoxLayout:
            adaptive_height: True
            spacing: dp(18)
            padding: dp(8), 0
            pos_hint: {"center_x": 0.5}

            Widget:

            MDIconButton:
                icon: "skip-previous"
                icon_size: "42sp"
                theme_icon_color: "Custom"
                icon_color: 0.95, 0.97, 0.99, 1
                on_release: app.play_previous()

            MDIconButton:
                icon: "play-pause"
                icon_size: "56sp"
                theme_icon_color: "Custom"
                icon_color: app.accent_rgb
                on_release: app.toggle_playback()

            MDIconButton:
                icon: "skip-next"
                icon_size: "42sp"
                theme_icon_color: "Custom"
                icon_color: 0.95, 0.97, 0.99, 1
                on_release: app.play_next()

            Widget:

        MDCard:
            orientation: "vertical"
            adaptive_height: True
            padding: dp(14)
            radius: [24, 24, 24, 24]
            theme_bg_color: "Custom"
            md_bg_color: 0.08, 0.09, 0.12, 1
            line_color: 0.12, 0.78, 0.58, 0.18

            MDLabel:
                text: app.buffer_text
                adaptive_height: True
                halign: "center"
                theme_text_color: "Secondary"
"""


@dataclass
class TrackRecord:
    uid: str
    chat_id: int
    message_id: int
    title: str
    artist: str
    duration_seconds: int
    file_name: str
    file_size: int
    source_label: str

    @property
    def subtitle(self) -> str:
        return self.artist or "Unknown artist"

    @property
    def meta_line(self) -> str:
        bits = [format_duration(self.duration_seconds)]
        if self.file_size > 0:
            bits.append(format_bytes(self.file_size))
        bits.append(self.file_name)
        return "  •  ".join(bits)


class TrackRow(ThreeLineAvatarIconListItem):
    track_index = NumericProperty(0)


class LibraryScreen(Screen):
    pass


class PlayerScreen(Screen):
    pass


def format_duration(total_seconds: int) -> str:
    seconds = max(int(total_seconds or 0), 0)
    minutes, seconds = divmod(seconds, 60)
    hours, minutes = divmod(minutes, 60)
    if hours:
        return f"{hours:02d}:{minutes:02d}:{seconds:02d}"
    return f"{minutes:02d}:{seconds:02d}"


def format_bytes(value: int) -> str:
    size = float(value or 0)
    for unit in ("B", "KB", "MB", "GB"):
        if size < 1024 or unit == "GB":
            return f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} GB"


def sanitize_filename(name: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9._ -]", "_", name or "track")
    return cleaned.strip() or "track"


class DesktopAudioPlayer:
    def __init__(self) -> None:
        self._sound = None
        self._paused_at = 0.0
        self._loaded_path = None

    def load(self, file_path: str) -> None:
        if self._loaded_path == file_path and self._sound is not None:
            return
        self.stop()
        self._sound = SoundLoader.load(file_path)
        self._loaded_path = file_path
        self._paused_at = 0.0
        if self._sound is None:
            raise RuntimeError(f"Unable to load audio file: {file_path}")

    def play(self) -> None:
        if self._sound is None:
            return
        self._sound.play()
        if self._paused_at and hasattr(self._sound, "seek"):
            self._sound.seek(self._paused_at)
            self._paused_at = 0.0

    def pause(self) -> None:
        if self._sound is None:
            return
        if hasattr(self._sound, "get_pos"):
            self._paused_at = max(0.0, float(self._sound.get_pos() or 0.0))
        self._sound.stop()

    def stop(self) -> None:
        if self._sound is not None:
            self._sound.stop()
        self._sound = None
        self._loaded_path = None
        self._paused_at = 0.0

    def seek(self, seconds: float) -> None:
        if self._sound is not None and hasattr(self._sound, "seek"):
            self._sound.seek(max(0.0, float(seconds)))

    def is_playing(self) -> bool:
        return bool(self._sound and getattr(self._sound, "state", "") == "play")

    def position(self) -> float:
        if self._sound is not None and hasattr(self._sound, "get_pos"):
            return max(0.0, float(self._sound.get_pos() or 0.0))
        return 0.0

    def duration(self) -> float:
        if self._sound is not None:
            return max(0.0, float(getattr(self._sound, "length", 0.0) or 0.0))
        return 0.0


class AndroidAudioPlayer:
    def __init__(self) -> None:
        from jnius import autoclass

        self._MediaPlayer = autoclass("android.media.MediaPlayer")
        self._player = None
        self._loaded_path = None

    def load(self, file_path: str) -> None:
        if self._loaded_path == file_path and self._player is not None:
            return
        self.stop()
        self._player = self._MediaPlayer()
        self._player.setDataSource(file_path)
        self._player.prepare()
        self._loaded_path = file_path

    def play(self) -> None:
        if self._player is not None and not self._player.isPlaying():
            self._player.start()

    def pause(self) -> None:
        if self._player is not None and self._player.isPlaying():
            self._player.pause()

    def stop(self) -> None:
        if self._player is None:
            return
        try:
            self._player.stop()
        except Exception:
            pass
        try:
            self._player.release()
        except Exception:
            pass
        self._player = None
        self._loaded_path = None

    def seek(self, seconds: float) -> None:
        if self._player is not None:
            self._player.seekTo(int(max(0.0, seconds) * 1000))

    def is_playing(self) -> bool:
        return bool(self._player and self._player.isPlaying())

    def position(self) -> float:
        if self._player is not None:
            return float(self._player.getCurrentPosition()) / 1000.0
        return 0.0

    def duration(self) -> float:
        if self._player is not None:
            return max(0.0, float(self._player.getDuration()) / 1000.0)
        return 0.0


class TelegramAudioBackend:
    def __init__(self, cache_dir: Path, dispatch) -> None:
        self._cache_dir = cache_dir
        self._cache_dir.mkdir(parents=True, exist_ok=True)
        self._dispatch = dispatch
        self._loop = asyncio.new_event_loop()
        self._thread = threading.Thread(target=self._run_loop, daemon=True)
        self._thread.start()
        self._client: Optional[TelegramClient] = None
        self._message_index: Dict[str, Any] = {}

    def _run_loop(self) -> None:
        asyncio.set_event_loop(self._loop)
        self._loop.run_forever()

    def _emit(self, event_name: str, payload: Dict[str, Any]) -> None:
        Clock.schedule_once(lambda dt: self._dispatch(event_name, payload), 0)

    def submit(self, coro) -> Future:
        return asyncio.run_coroutine_threadsafe(coro, self._loop)

    def connect(self, api_id: str, api_hash: str, string_session: str, bot_token: str) -> None:
        future = self.submit(self._connect(api_id, api_hash, string_session, bot_token))
        future.add_done_callback(self._wrap_future("connected"))

    def disconnect(self) -> None:
        future = self.submit(self._disconnect())
        future.add_done_callback(self._wrap_future("disconnected"))

    def fetch_tracks(self, channel_ref: str, limit: int = 100) -> None:
        future = self.submit(self._fetch_tracks(channel_ref, limit))
        future.add_done_callback(self._wrap_future("tracks_loaded"))

    def stream_track(self, track: TrackRecord) -> None:
        future = self.submit(self._stream_track(track))
        future.add_done_callback(self._wrap_future("stream_finished"))

    def stop(self) -> None:
        self.submit(self._disconnect())
        self._loop.call_soon_threadsafe(self._loop.stop)

    def _wrap_future(self, success_event: str):
        def callback(future: Future) -> None:
            try:
                result = future.result()
            except Exception as exc:
                self._emit("error", {"message": str(exc)})
                return
            self._emit(success_event, result or {})

        return callback

    async def _connect(
        self,
        api_id: str,
        api_hash: str,
        string_session: str,
        bot_token: str,
    ) -> Dict[str, Any]:
        await self._disconnect()
        if not api_id.strip() or not api_hash.strip():
            raise ValueError("API ID and API Hash are required.")

        session_value = string_session.strip()
        bot_token_value = bot_token.strip()
        if not session_value and not bot_token_value:
            raise ValueError("Provide either a StringSession or a Bot Token.")

        client = TelegramClient(
            StringSession(session_value if session_value else ""),
            int(api_id),
            api_hash.strip(),
            device_model="ETGmusic",
            system_version="Android",
            app_version="1.0.0",
            system_lang_code="en",
            lang_code="en",
        )

        if session_value:
            await client.connect()
            if not await client.is_user_authorized():
                await client.disconnect()
                raise ValueError("The provided StringSession is not authorized.")
        else:
            await client.start(bot_token=bot_token_value)

        me = await client.get_me()
        self._client = client
        return {
            "identity": getattr(me, "username", None) or getattr(me, "first_name", None) or str(getattr(me, "id", "unknown")),
        }

    async def _disconnect(self) -> Dict[str, Any]:
        if self._client is not None:
            await self._client.disconnect()
        self._client = None
        self._message_index.clear()
        return {"state": "offline"}

    async def _fetch_tracks(self, channel_ref: str, limit: int) -> Dict[str, Any]:
        if self._client is None:
            raise ValueError("Connect to Telegram before refreshing the track list.")
        if not channel_ref.strip():
            raise ValueError("Enter a Telegram channel or chat reference.")

        entity = await self._client.get_entity(channel_ref.strip())
        source_label = getattr(entity, "title", None) or getattr(entity, "username", None) or channel_ref.strip()

        tracks: List[TrackRecord] = []
        self._message_index.clear()
        async for message in self._client.iter_messages(entity, limit=limit):
            track = self._message_to_track(message, source_label)
            if track is None:
                continue
            tracks.append(track)
            self._message_index[track.uid] = message

        return {"source_label": source_label, "tracks": tracks}

    def _message_to_track(self, message, source_label: str) -> Optional[TrackRecord]:
        document = getattr(message, "document", None)
        if document is None:
            return None

        audio_attr = None
        for attr in getattr(document, "attributes", []):
            if isinstance(attr, tg_types.DocumentAttributeAudio) and not getattr(attr, "voice", False):
                audio_attr = attr
                break

        file_info = getattr(message, "file", None)
        mime_type = getattr(file_info, "mime_type", "") or getattr(document, "mime_type", "") or ""
        if audio_attr is None and not mime_type.startswith("audio/"):
            return None

        title = getattr(audio_attr, "title", None) or getattr(file_info, "name", None) or f"Track {message.id}"
        artist = getattr(audio_attr, "performer", None) or source_label
        duration = int(getattr(audio_attr, "duration", 0) or 0)
        file_name = getattr(file_info, "name", None) or f"{sanitize_filename(title)}.mp3"
        file_size = int(getattr(document, "size", 0) or 0)
        uid = f"{int(message.chat_id)}:{int(message.id)}"

        return TrackRecord(
            uid=uid,
            chat_id=int(message.chat_id),
            message_id=int(message.id),
            title=str(title),
            artist=str(artist),
            duration_seconds=duration,
            file_name=str(file_name),
            file_size=file_size,
            source_label=source_label,
        )

    async def _stream_track(self, track: TrackRecord) -> Dict[str, Any]:
        if self._client is None:
            raise ValueError("Connect to Telegram before streaming.")

        message = self._message_index.get(track.uid)
        if message is None:
            raise ValueError("Track reference expired. Refresh the channel list.")

        suffix = Path(track.file_name).suffix or ".mp3"
        cache_name = f"{track.message_id}_{sanitize_filename(Path(track.file_name).stem)}{suffix}"
        cache_path = self._cache_dir / cache_name
        expected_size = int(track.file_size or 0)

        if cache_path.exists() and expected_size and cache_path.stat().st_size >= expected_size:
            self._emit("stream_ready", {"track_uid": track.uid, "path": str(cache_path)})
            return {"track_uid": track.uid}

        if cache_path.exists():
            cache_path.unlink()

        threshold = 512 * 1024
        if expected_size:
            threshold = min(max(expected_size // 8, 384 * 1024), 2 * 1024 * 1024)

        ready_sent = False

        def progress_callback(current: int, total: int) -> None:
            nonlocal ready_sent
            percent = 0.0 if not total else max(0.0, min(100.0, (current / total) * 100))
            self._emit(
                "download_progress",
                {
                    "track_uid": track.uid,
                    "current_bytes": current,
                    "total_bytes": total,
                    "percent": percent,
                },
            )
            if not ready_sent and current >= min(threshold, total or threshold) and cache_path.exists():
                ready_sent = True
                self._emit("stream_ready", {"track_uid": track.uid, "path": str(cache_path)})

        await self._client.download_media(message, file=str(cache_path), progress_callback=progress_callback)
        if cache_path.exists() and not ready_sent:
            self._emit("stream_ready", {"track_uid": track.uid, "path": str(cache_path)})

        return {"track_uid": track.uid, "path": str(cache_path)}


class ETGmusicApp(MDApp):
    status_text = StringProperty("Idle. Enter credentials and a source channel.")
    channel_status_text = StringProperty("No channel loaded.")
    track_counter_text = StringProperty("0 tracks")
    current_title = StringProperty("Nothing selected")
    current_artist = StringProperty("Choose a Telegram audio message to start streaming.")
    buffer_text = StringProperty("Player is waiting for a stream.")
    player_state_text = StringProperty("Stopped")
    position_label = StringProperty("00:00")
    duration_label = StringProperty("00:00")
    track_position = NumericProperty(0.0)
    track_duration = NumericProperty(1.0)
    is_buffering = BooleanProperty(False)

    accent_rgb = (0.12, 0.78, 0.58, 1)
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.settings_path = None
        self.cache_dir = None
        self.backend = None
        self.audio_player = AndroidAudioPlayer() if platform == "android" else DesktopAudioPlayer()
        self.tracks: List[TrackRecord] = []
        self.current_index = -1
        self.current_track_uid = None
        self._loaded_audio_path = None
        self._settings: Dict[str, str] = {}

    def build(self):
        self.title = "ETGmusic"
        self.theme_cls.theme_style = "Dark"
        self.theme_cls.primary_palette = "Green"
        self.theme_cls.accent_palette = "Teal"

        if platform != "android":
            Window.clearcolor = (0.03, 0.04, 0.06, 1)
            Window.size = (412, 915)

        Builder.load_string(KV)
        root = ScreenManager()
        root.add_widget(LibraryScreen(name="library"))
        root.add_widget(PlayerScreen(name="player"))
        return root

    def on_start(self):
        self.settings_path = Path(self.user_data_dir) / "settings.json"
        self.cache_dir = Path(self.user_data_dir) / "stream_cache"
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.backend = TelegramAudioBackend(self.cache_dir, self.on_backend_event)
        self._settings = self.load_settings()
        self.apply_settings_to_ui()
        Clock.schedule_interval(self.sync_player_state, 0.5)

    def on_stop(self):
        if self.backend is not None:
            self.backend.stop()
        self.audio_player.stop()

    def on_pause(self):
        return True

    def switch_screen(self, name: str) -> None:
        self.root.current = name

    def load_settings(self) -> Dict[str, str]:
        if self.settings_path and self.settings_path.exists():
            try:
                return json.loads(self.settings_path.read_text(encoding="utf-8"))
            except Exception:
                return {}
        return {}

    def save_settings(self) -> None:
        values = {
            "api_id": self.library_ids.api_id_input.text.strip(),
            "api_hash": self.library_ids.api_hash_input.text.strip(),
            "string_session": self.library_ids.string_session_input.text.strip(),
            "bot_token": self.library_ids.bot_token_input.text.strip(),
            "channel": self.library_ids.channel_input.text.strip(),
        }
        self._settings = values
        self.settings_path.write_text(json.dumps(values, indent=2), encoding="utf-8")

    def apply_settings_to_ui(self) -> None:
        self.library_ids.api_id_input.text = self._settings.get("api_id", "")
        self.library_ids.api_hash_input.text = self._settings.get("api_hash", "")
        self.library_ids.string_session_input.text = self._settings.get("string_session", "")
        self.library_ids.bot_token_input.text = self._settings.get("bot_token", "")
        self.library_ids.channel_input.text = self._settings.get("channel", "")

    @property
    def library_ids(self):
        return self.root.get_screen("library").ids

    def on_connect_pressed(self) -> None:
        self.save_settings()
        self.status_text = "Connecting to Telegram..."
        self.backend.connect(
            self.library_ids.api_id_input.text,
            self.library_ids.api_hash_input.text,
            self.library_ids.string_session_input.text,
            self.library_ids.bot_token_input.text,
        )

    def on_disconnect_pressed(self) -> None:
        self.status_text = "Disconnecting..."
        self.backend.disconnect()
        self.audio_player.stop()
        self.player_state_text = "Stopped"

    def on_refresh_pressed(self) -> None:
        self.save_settings()
        self.status_text = "Refreshing audio messages..."
        self.backend.fetch_tracks(self.library_ids.channel_input.text, limit=100)

    def on_track_selected(self, index: int) -> None:
        if index < 0 or index >= len(self.tracks):
            return
        self.current_index = index
        track = self.tracks[index]
        self.current_track_uid = track.uid
        self.current_title = track.title
        self.current_artist = track.artist
        self.buffer_text = "Buffering from Telegram servers..."
        self.player_state_text = "Buffering"
        self.track_position = 0.0
        self.track_duration = max(1.0, float(track.duration_seconds or 1))
        self.position_label = "00:00"
        self.duration_label = format_duration(track.duration_seconds)
        self.audio_player.stop()
        self._loaded_audio_path = None
        self.switch_screen("player")
        self.backend.stream_track(track)

    def play_previous(self) -> None:
        if not self.tracks:
            return
        new_index = (self.current_index - 1) % len(self.tracks)
        self.on_track_selected(new_index)

    def play_next(self) -> None:
        if not self.tracks:
            return
        new_index = (self.current_index + 1) % len(self.tracks)
        self.on_track_selected(new_index)

    def toggle_playback(self) -> None:
        if self._loaded_audio_path is None:
            return
        if self.audio_player.is_playing():
            self.audio_player.pause()
            self.player_state_text = "Paused"
        else:
            self.audio_player.play()
            self.player_state_text = "Playing"

    def on_seek_released(self, slider, touch) -> None:
        if not slider.collide_point(*touch.pos):
            return
        if self._loaded_audio_path is None:
            return
        self.audio_player.seek(slider.value)
        self.track_position = slider.value

    def sync_player_state(self, *_args) -> None:
        if self._loaded_audio_path is None:
            return
        position = max(0.0, self.audio_player.position())
        duration = self.audio_player.duration()
        if duration > 0:
            self.track_duration = duration
        self.track_position = min(position, self.track_duration)
        self.position_label = format_duration(int(self.track_position))
        self.duration_label = format_duration(int(self.track_duration))

        if self.current_index >= 0 and not self.audio_player.is_playing():
            if self.player_state_text == "Playing" and self.track_position >= max(1.0, self.track_duration - 1.0):
                self.play_next()

    def populate_track_list(self) -> None:
        track_list = self.library_ids.track_list
        track_list.clear_widgets()
        for index, track in enumerate(self.tracks):
            track_list.add_widget(
                TrackRow(
                    track_index=index,
                    text=track.title,
                    secondary_text=track.subtitle,
                    tertiary_text=track.meta_line,
                )
            )
        self.track_counter_text = f"{len(self.tracks)} tracks"

    def start_local_playback(self, file_path: str) -> None:
        try:
            self.audio_player.load(file_path)
            self.audio_player.play()
            self._loaded_audio_path = file_path
            self.player_state_text = "Playing"
            self.buffer_text = "Streaming via Telegram cache buffer."
        except Exception as exc:
            self.buffer_text = f"Waiting for more buffer... {exc}"

    def on_backend_event(self, event_name: str, payload: Dict[str, Any]) -> None:
        if event_name == "connected":
            identity = payload.get("identity", "unknown")
            self.status_text = f"Connected as {identity}."
            if self.library_ids.channel_input.text.strip():
                self.on_refresh_pressed()
            return

        if event_name == "disconnected":
            self.status_text = "Disconnected."
            self.channel_status_text = "No channel loaded."
            self.tracks = []
            self.populate_track_list()
            return

        if event_name == "tracks_loaded":
            raw_tracks = payload.get("tracks", [])
            self.tracks = raw_tracks
            self.populate_track_list()
            source_label = payload.get("source_label", "Unknown source")
            self.channel_status_text = f"Loaded from {source_label}"
            self.status_text = f"Fetched {len(self.tracks)} audio messages."
            return

        if event_name == "download_progress":
            if payload.get("track_uid") == self.current_track_uid:
                percent = payload.get("percent", 0.0)
                self.buffer_text = f"Buffering from Telegram... {percent:.0f}%"
            return

        if event_name == "stream_ready":
            if payload.get("track_uid") == self.current_track_uid:
                self.start_local_playback(payload["path"])
            return

        if event_name == "stream_finished":
            if payload.get("track_uid") == self.current_track_uid and self._loaded_audio_path is None:
                self.start_local_playback(payload["path"])
            return

        if event_name == "error":
            self.status_text = f"Error: {payload.get('message', 'unknown error')}"
            self.buffer_text = self.status_text


if __name__ == "__main__":
    ETGmusicApp().run()
