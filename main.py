import asyncio
import json
import re
import threading
import time
import urllib.parse
import urllib.request
from concurrent.futures import Future
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from kivy.clock import Clock
from kivy.core.audio import SoundLoader
from kivy.core.window import Window
from kivy.lang import Builder
from kivy.properties import BooleanProperty, ListProperty, NumericProperty, StringProperty
from kivy.uix.screenmanager import Screen, ScreenManager
from kivy.utils import platform
from kivymd.app import MDApp
from kivymd.uix.list import ThreeLineAvatarIconListItem
from telethon import TelegramClient, types as tg_types
from telethon.sessions import StringSession


KV = """
#:import dp kivy.metrics.dp

<GlassCard@MDCard>:
    orientation: "vertical"
    padding: dp(16)
    spacing: dp(10)
    radius: [30, 30, 30, 30]
    adaptive_height: True
    theme_bg_color: "Custom"
    md_bg_color: app.card_rgb
    line_color: app.line_rgb

<PillButton@MDRectangleFlatButton>:
    text_color: app.accent_rgb
    line_color: app.accent_rgb

<SolidButton@MDRaisedButton>:
    md_bg_color: app.accent_rgb

<TrackRow>:
    theme_bg_color: "Custom"
    md_bg_color: 0, 0, 0, 0
    divider: None
    on_release: app.on_track_selected(self.track_index)
    IconLeftWidget:
        icon: "heart" if app.is_favorite_uid(root.track_uid) else "music-note-outline"
        theme_text_color: "Custom"
        text_color: app.accent_rgb
    IconRightWidget:
        icon: "play-circle-outline"
        theme_text_color: "Custom"
        text_color: app.accent_rgb

<AlbumRow>:
    theme_bg_color: "Custom"
    md_bg_color: 0, 0, 0, 0
    divider: None
    on_release: app.play_album(self.album_name)
    IconLeftWidget:
        icon: "album"
        theme_text_color: "Custom"
        text_color: app.accent_rgb
    IconRightWidget:
        icon: "playlist-play"
        theme_text_color: "Custom"
        text_color: app.accent_rgb

<NavBar@MDBoxLayout>:
    adaptive_height: True
    spacing: dp(8)
    padding: 0, 0, 0, dp(8)
    PillButton:
        text: "Радар"
        on_release: app.switch_screen("library")
    PillButton:
        text: "Плеер"
        on_release: app.switch_screen("player")
    PillButton:
        text: "Коллекции"
        on_release: app.switch_screen("albums")
    PillButton:
        text: "Настройки"
        on_release: app.switch_screen("settings")

<LibraryScreen>:
    MDBoxLayout:
        orientation: "vertical"
        padding: dp(16), dp(12), dp(16), dp(8)
        spacing: dp(10)
        md_bg_color: app.bg_rgb

        MDBoxLayout:
            adaptive_height: True
            spacing: dp(10)

            MDBoxLayout:
                orientation: "vertical"
                adaptive_height: True

                MDLabel:
                    text: "ETGmusic"
                    font_style: "H3"
                    bold: True
                    adaptive_height: True
                    theme_text_color: "Custom"
                    text_color: app.text_rgb

                MDLabel:
                    text: "Telegram-first streaming. Каналы, боты, группы, тексты, альбомы."
                    adaptive_height: True
                    theme_text_color: "Custom"
                    text_color: app.muted_rgb

            MDIconButton:
                icon: "refresh"
                icon_size: "34sp"
                theme_icon_color: "Custom"
                icon_color: app.accent_rgb
                on_release: app.on_refresh_pressed()

        NavBar:

        ScrollView:
            bar_width: dp(3)
            MDBoxLayout:
                orientation: "vertical"
                adaptive_height: True
                spacing: dp(12)
                padding: 0, 0, 0, dp(28)

                GlassCard:
                    md_bg_color: app.hero_rgb
                    line_color: app.accent_rgb

                    MDLabel:
                        text: "Музыкальный радар"
                        font_style: "H5"
                        bold: True
                        adaptive_height: True
                        theme_text_color: "Custom"
                        text_color: app.text_rgb

                    MDLabel:
                        text: "Сканирует указанные Telegram-боты, каналы, группы и супергруппы. Аудио стартует как поток через Telegram cache buffer, не ожидая полного скачивания."
                        adaptive_height: True
                        theme_text_color: "Custom"
                        text_color: app.muted_rgb

                    MDLabel:
                        text: app.status_text
                        adaptive_height: True
                        theme_text_color: "Custom"
                        text_color: app.accent_rgb

                GlassCard:
                    MDLabel:
                        text: "Telegram вход"
                        font_style: "H6"
                        bold: True
                        adaptive_height: True
                        theme_text_color: "Custom"
                        text_color: app.text_rgb

                    MDTextField:
                        id: api_id_input
                        hint_text: "API ID"
                        mode: "rectangle"
                        input_filter: "int"

                    MDTextField:
                        id: api_hash_input
                        hint_text: "API Hash"
                        mode: "rectangle"

                    MDTextField:
                        id: string_session_input
                        hint_text: "StringSession пользователя"
                        helper_text: "Лучший режим для каналов/групп, где бот не состоит"
                        helper_text_mode: "persistent"
                        mode: "rectangle"
                        multiline: True
                        max_height: dp(92)

                    MDTextField:
                        id: bot_token_input
                        hint_text: "Bot Token"
                        helper_text: "Работает, если бот добавлен в нужные источники"
                        helper_text_mode: "persistent"
                        mode: "rectangle"
                        multiline: True
                        max_height: dp(72)

                    MDBoxLayout:
                        adaptive_height: True
                        spacing: dp(8)
                        SolidButton:
                            text: "Подключиться"
                            on_release: app.on_connect_pressed()
                        PillButton:
                            text: "Отключить"
                            text_color: 0.95, 0.35, 0.43, 1
                            line_color: 0.95, 0.35, 0.43, 1
                            on_release: app.on_disconnect_pressed()

                GlassCard:
                    MDLabel:
                        text: "Источники"
                        font_style: "H6"
                        bold: True
                        adaptive_height: True
                        theme_text_color: "Custom"
                        text_color: app.text_rgb

                    MDTextField:
                        id: source_input
                        hint_text: "@channel, @bot, invite link, numeric id. Один источник на строку."
                        mode: "rectangle"
                        multiline: True
                        max_height: dp(150)

                    MDBoxLayout:
                        adaptive_height: True
                        spacing: dp(8)
                        MDTextField:
                            id: scan_limit_input
                            hint_text: "Лимит на источник"
                            mode: "rectangle"
                            input_filter: "int"
                            text: "120"
                        SolidButton:
                            text: "Сканировать"
                            on_release: app.on_refresh_pressed()

                    MDLabel:
                        text: app.channel_status_text
                        adaptive_height: True
                        theme_text_color: "Custom"
                        text_color: app.muted_rgb

                GlassCard:
                    MDBoxLayout:
                        adaptive_height: True
                        spacing: dp(8)
                        MDLabel:
                            text: "Треки"
                            font_style: "H6"
                            bold: True
                            adaptive_height: True
                            theme_text_color: "Custom"
                            text_color: app.text_rgb
                        Widget:
                        MDLabel:
                            text: app.track_counter_text
                            adaptive_height: True
                            halign: "right"
                            theme_text_color: "Custom"
                            text_color: app.muted_rgb

                    MDTextField:
                        id: search_input
                        hint_text: "Фильтр по названию / артисту / источнику"
                        mode: "rectangle"
                        on_text: app.populate_track_list()

                    MDList:
                        id: track_list

<PlayerScreen>:
    MDBoxLayout:
        orientation: "vertical"
        padding: dp(18), dp(12), dp(18), dp(8)
        spacing: dp(10)
        md_bg_color: app.bg_rgb

        NavBar:

        ScrollView:
            bar_width: dp(3)
            MDBoxLayout:
                orientation: "vertical"
                adaptive_height: True
                spacing: dp(12)
                padding: 0, 0, 0, dp(28)

                MDCard:
                    size_hint: None, None
                    size: dp(304), dp(304)
                    pos_hint: {"center_x": 0.5}
                    radius: [48, 48, 48, 48]
                    theme_bg_color: "Custom"
                    md_bg_color: app.hero_rgb
                    line_color: app.accent_rgb
                    MDBoxLayout:
                        orientation: "vertical"
                        padding: dp(18)
                        Widget:
                        MDIcon:
                            icon: "waveform"
                            halign: "center"
                            font_size: "88sp"
                            theme_text_color: "Custom"
                            text_color: app.accent_rgb
                        MDLabel:
                            text: "Telegram stream deck"
                            halign: "center"
                            adaptive_height: True
                            theme_text_color: "Custom"
                            text_color: app.text_rgb
                        MDLabel:
                            text: app.player_state_text
                            halign: "center"
                            adaptive_height: True
                            theme_text_color: "Custom"
                            text_color: app.accent_rgb
                        Widget:

                MDLabel:
                    text: app.current_title
                    halign: "center"
                    font_style: "H5"
                    bold: True
                    adaptive_height: True
                    theme_text_color: "Custom"
                    text_color: app.text_rgb

                MDLabel:
                    text: app.current_artist
                    halign: "center"
                    adaptive_height: True
                    theme_text_color: "Custom"
                    text_color: app.muted_rgb

                MDLabel:
                    text: app.buffer_text
                    adaptive_height: True
                    halign: "center"
                    theme_text_color: "Custom"
                    text_color: app.muted_rgb

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
                        theme_text_color: "Custom"
                        text_color: app.muted_rgb
                    Widget:
                    MDLabel:
                        text: app.duration_label
                        adaptive_height: True
                        halign: "right"
                        theme_text_color: "Custom"
                        text_color: app.muted_rgb

                MDBoxLayout:
                    adaptive_height: True
                    spacing: dp(18)
                    Widget:
                    MDIconButton:
                        icon: "skip-previous"
                        icon_size: "42sp"
                        theme_icon_color: "Custom"
                        icon_color: app.text_rgb
                        on_release: app.play_previous()
                    MDIconButton:
                        icon: "play-pause"
                        icon_size: "60sp"
                        theme_icon_color: "Custom"
                        icon_color: app.accent_rgb
                        on_release: app.toggle_playback()
                    MDIconButton:
                        icon: "skip-next"
                        icon_size: "42sp"
                        theme_icon_color: "Custom"
                        icon_color: app.text_rgb
                        on_release: app.play_next()
                    Widget:

                MDBoxLayout:
                    adaptive_height: True
                    spacing: dp(8)
                    PillButton:
                        text: "Любимый"
                        on_release: app.toggle_current_favorite()
                    PillButton:
                        text: "В альбом"
                        on_release: app.add_current_to_album()
                    PillButton:
                        text: "Текст"
                        on_release: app.fetch_current_lyrics(force=True)

                GlassCard:
                    MDLabel:
                        text: app.lyrics_status_text
                        adaptive_height: True
                        theme_text_color: "Custom"
                        text_color: app.accent_rgb
                    MDLabel:
                        text: app.current_lyrics_text
                        adaptive_height: True
                        halign: "center"
                        theme_text_color: "Custom"
                        text_color: app.text_rgb
                    MDTextField:
                        id: custom_lyrics_input
                        hint_text: "Свой текст или LRC для текущего трека"
                        mode: "rectangle"
                        multiline: True
                        max_height: dp(150)
                    PillButton:
                        text: "Сохранить свой текст"
                        on_release: app.save_custom_lyrics()

<AlbumsScreen>:
    MDBoxLayout:
        orientation: "vertical"
        padding: dp(18), dp(12), dp(18), dp(8)
        spacing: dp(10)
        md_bg_color: app.bg_rgb

        NavBar:

        ScrollView:
            bar_width: dp(3)
            MDBoxLayout:
                orientation: "vertical"
                adaptive_height: True
                spacing: dp(12)
                padding: 0, 0, 0, dp(28)

                GlassCard:
                    MDLabel:
                        text: "Локальная коллекция"
                        font_style: "H5"
                        bold: True
                        adaptive_height: True
                        theme_text_color: "Custom"
                        text_color: app.text_rgb
                    MDLabel:
                        text: "Альбомы и любимые хранятся локально. Это плейлисты поверх Telegram-треков: источник не копируется, но порядок и выбор сохраняются."
                        adaptive_height: True
                        theme_text_color: "Custom"
                        text_color: app.muted_rgb

                GlassCard:
                    MDTextField:
                        id: album_name_input
                        hint_text: "Название альбома"
                        mode: "rectangle"
                    MDBoxLayout:
                        adaptive_height: True
                        spacing: dp(8)
                        SolidButton:
                            text: "Создать"
                            on_release: app.create_album()
                        PillButton:
                            text: "Добавить текущий"
                            on_release: app.add_current_to_album()
                        PillButton:
                            text: "Играть любимые"
                            on_release: app.play_favorites()
                    MDLabel:
                        text: app.album_status_text
                        adaptive_height: True
                        theme_text_color: "Custom"
                        text_color: app.muted_rgb

                GlassCard:
                    MDLabel:
                        text: "Альбомы"
                        font_style: "H6"
                        bold: True
                        adaptive_height: True
                        theme_text_color: "Custom"
                        text_color: app.text_rgb
                    MDList:
                        id: album_list

<SettingsScreen>:
    MDBoxLayout:
        orientation: "vertical"
        padding: dp(18), dp(12), dp(18), dp(8)
        spacing: dp(10)
        md_bg_color: app.bg_rgb

        NavBar:

        ScrollView:
            bar_width: dp(3)
            MDBoxLayout:
                orientation: "vertical"
                adaptive_height: True
                spacing: dp(12)
                padding: 0, 0, 0, dp(28)

                GlassCard:
                    MDLabel:
                        text: "Темы"
                        font_style: "H6"
                        bold: True
                        adaptive_height: True
                        theme_text_color: "Custom"
                        text_color: app.text_rgb
                    MDLabel:
                        text: app.theme_status_text
                        adaptive_height: True
                        theme_text_color: "Custom"
                        text_color: app.muted_rgb
                    MDBoxLayout:
                        adaptive_height: True
                        spacing: dp(8)
                        PillButton:
                            text: "Cyber"
                            on_release: app.set_theme("cyber")
                        PillButton:
                            text: "Amber"
                            on_release: app.set_theme("amber")
                        PillButton:
                            text: "Ice"
                            on_release: app.set_theme("ice")
                    MDBoxLayout:
                        adaptive_height: True
                        spacing: dp(8)
                        PillButton:
                            text: "Ruby"
                            on_release: app.set_theme("ruby")
                        PillButton:
                            text: "Forest"
                            on_release: app.set_theme("forest")
                        PillButton:
                            text: "Mono"
                            on_release: app.set_theme("mono")

                GlassCard:
                    MDLabel:
                        text: "MTProto / SOCKS proxy"
                        font_style: "H6"
                        bold: True
                        adaptive_height: True
                        theme_text_color: "Custom"
                        text_color: app.text_rgb
                    MDTextField:
                        id: proxy_type_input
                        hint_text: "off / mtproto / socks5 / socks4 / http"
                        mode: "rectangle"
                    MDTextField:
                        id: proxy_host_input
                        hint_text: "Host"
                        mode: "rectangle"
                    MDTextField:
                        id: proxy_port_input
                        hint_text: "Port"
                        mode: "rectangle"
                        input_filter: "int"
                    MDTextField:
                        id: proxy_secret_input
                        hint_text: "MTProto secret или SOCKS username"
                        mode: "rectangle"
                    MDTextField:
                        id: proxy_password_input
                        hint_text: "SOCKS password"
                        mode: "rectangle"
                    PillButton:
                        text: "Сохранить proxy"
                        on_release: app.save_settings()
                    MDLabel:
                        text: app.proxy_status_text
                        adaptive_height: True
                        theme_text_color: "Custom"
                        text_color: app.muted_rgb

                GlassCard:
                    MDLabel:
                        text: "Таймер сна"
                        font_style: "H6"
                        bold: True
                        adaptive_height: True
                        theme_text_color: "Custom"
                        text_color: app.text_rgb
                    MDTextField:
                        id: sleep_minutes_input
                        hint_text: "Минуты до паузы"
                        mode: "rectangle"
                        input_filter: "int"
                        text: "30"
                    MDBoxLayout:
                        adaptive_height: True
                        spacing: dp(8)
                        SolidButton:
                            text: "Старт"
                            on_release: app.start_sleep_timer()
                        PillButton:
                            text: "Отмена"
                            on_release: app.cancel_sleep_timer()
                    MDLabel:
                        text: app.sleep_timer_text
                        adaptive_height: True
                        theme_text_color: "Custom"
                        text_color: app.muted_rgb
"""


THEMES = {
    "cyber": {
        "bg": [0.025, 0.030, 0.045, 1],
        "card": [0.060, 0.075, 0.105, 0.96],
        "hero": [0.030, 0.120, 0.145, 1],
        "accent": [0.000, 0.900, 0.650, 1],
        "line": [0.000, 0.900, 0.650, 0.28],
        "text": [0.940, 0.980, 1.000, 1],
        "muted": [0.630, 0.700, 0.780, 1],
        "style": "Dark",
    },
    "amber": {
        "bg": [0.070, 0.045, 0.020, 1],
        "card": [0.150, 0.100, 0.045, 0.96],
        "hero": [0.230, 0.120, 0.025, 1],
        "accent": [1.000, 0.630, 0.130, 1],
        "line": [1.000, 0.630, 0.130, 0.28],
        "text": [1.000, 0.960, 0.900, 1],
        "muted": [0.820, 0.720, 0.620, 1],
        "style": "Dark",
    },
    "ice": {
        "bg": [0.930, 0.970, 1.000, 1],
        "card": [1.000, 1.000, 1.000, 0.98],
        "hero": [0.830, 0.930, 1.000, 1],
        "accent": [0.040, 0.440, 0.900, 1],
        "line": [0.040, 0.440, 0.900, 0.25],
        "text": [0.050, 0.070, 0.110, 1],
        "muted": [0.340, 0.410, 0.500, 1],
        "style": "Light",
    },
    "ruby": {
        "bg": [0.060, 0.020, 0.040, 1],
        "card": [0.120, 0.040, 0.075, 0.96],
        "hero": [0.210, 0.035, 0.110, 1],
        "accent": [1.000, 0.190, 0.410, 1],
        "line": [1.000, 0.190, 0.410, 0.30],
        "text": [1.000, 0.940, 0.980, 1],
        "muted": [0.830, 0.650, 0.730, 1],
        "style": "Dark",
    },
    "forest": {
        "bg": [0.025, 0.055, 0.040, 1],
        "card": [0.050, 0.110, 0.075, 0.96],
        "hero": [0.045, 0.170, 0.105, 1],
        "accent": [0.280, 0.920, 0.420, 1],
        "line": [0.280, 0.920, 0.420, 0.28],
        "text": [0.920, 1.000, 0.940, 1],
        "muted": [0.620, 0.780, 0.660, 1],
        "style": "Dark",
    },
    "mono": {
        "bg": [0.020, 0.020, 0.022, 1],
        "card": [0.095, 0.095, 0.105, 0.96],
        "hero": [0.145, 0.145, 0.160, 1],
        "accent": [0.930, 0.930, 0.950, 1],
        "line": [0.930, 0.930, 0.950, 0.22],
        "text": [0.970, 0.970, 0.980, 1],
        "muted": [0.650, 0.650, 0.690, 1],
        "style": "Dark",
    },
}


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
        return f"{self.artist or 'Unknown artist'}  •  {self.source_label}"

    @property
    def meta_line(self) -> str:
        bits = [format_duration(self.duration_seconds)]
        if self.file_size > 0:
            bits.append(format_bytes(self.file_size))
        if self.file_name:
            bits.append(self.file_name)
        return "  •  ".join(bits)

    @classmethod
    def from_dict(cls, value: Dict[str, Any]) -> "TrackRecord":
        return cls(
            uid=str(value.get("uid", "")),
            chat_id=int(value.get("chat_id", 0)),
            message_id=int(value.get("message_id", 0)),
            title=str(value.get("title", "Track")),
            artist=str(value.get("artist", "")),
            duration_seconds=int(value.get("duration_seconds", 0) or 0),
            file_name=str(value.get("file_name", "")),
            file_size=int(value.get("file_size", 0) or 0),
            source_label=str(value.get("source_label", "")),
        )


class TrackRow(ThreeLineAvatarIconListItem):
    track_index = NumericProperty(0)
    track_uid = StringProperty("")


class AlbumRow(ThreeLineAvatarIconListItem):
    album_name = StringProperty("")


class LibraryScreen(Screen):
    pass


class PlayerScreen(Screen):
    pass


class AlbumsScreen(Screen):
    pass


class SettingsScreen(Screen):
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


def parse_source_refs(raw: str) -> List[str]:
    refs: List[str] = []
    seen = set()
    for line in re.split(r"[\n,;]+", raw or ""):
        value = line.split("#", 1)[0].strip()
        if not value or value in seen:
            continue
        seen.add(value)
        refs.append(value)
    return refs


def parse_lrc(raw: str) -> List[Tuple[float, str]]:
    rows: List[Tuple[float, str]] = []
    pattern = re.compile(r"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]")
    for line in (raw or "").splitlines():
        matches = list(pattern.finditer(line))
        if not matches:
            continue
        text = pattern.sub("", line).strip()
        for match in matches:
            minutes = int(match.group(1))
            seconds = int(match.group(2))
            fraction = match.group(3) or "0"
            millis = int(fraction.ljust(3, "0")[:3])
            rows.append(((minutes * 60) + seconds + (millis / 1000.0), text))
    return sorted(rows, key=lambda item: item[0])


def lyric_line_at(lines: List[Tuple[float, str]], position: float) -> str:
    if not lines:
        return ""
    current = lines[0][1]
    for timestamp, text in lines:
        if timestamp <= position + 0.2:
            current = text
        else:
            break
    return current or ""


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

    def connect(self, api_id: str, api_hash: str, string_session: str, bot_token: str, proxy_config: Dict[str, str]) -> None:
        future = self.submit(self._connect(api_id, api_hash, string_session, bot_token, proxy_config))
        future.add_done_callback(self._wrap_future("connected"))

    def disconnect(self) -> None:
        future = self.submit(self._disconnect())
        future.add_done_callback(self._wrap_future("disconnected"))

    def fetch_tracks(self, source_refs: List[str], limit: int = 120) -> None:
        future = self.submit(self._fetch_tracks(source_refs, limit))
        future.add_done_callback(self._wrap_future("tracks_loaded"))

    def stream_track(self, track: TrackRecord) -> None:
        future = self.submit(self._stream_track(track))
        future.add_done_callback(self._wrap_future("stream_finished"))

    def fetch_lyrics(self, track: TrackRecord) -> None:
        future = self.submit(self._fetch_lyrics(track))
        future.add_done_callback(self._wrap_future("lyrics_loaded"))

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

    def _build_proxy_kwargs(self, proxy_config: Dict[str, str]) -> Dict[str, Any]:
        proxy_type = (proxy_config.get("proxy_type") or "off").strip().lower()
        host = (proxy_config.get("proxy_host") or "").strip()
        port_raw = (proxy_config.get("proxy_port") or "").strip()
        if proxy_type in ("", "off", "none", "direct"):
            return {}
        if not host or not port_raw:
            raise ValueError("Proxy enabled, but host/port are empty.")
        port = int(port_raw)
        if proxy_type in ("mtproto", "mtproxy"):
            from telethon import connection

            secret = (proxy_config.get("proxy_secret") or "").strip()
            if not secret:
                raise ValueError("MTProto proxy requires secret.")
            return {
                "connection": connection.ConnectionTcpMTProxyRandomizedIntermediate,
                "proxy": (host, port, secret),
            }

        import socks

        proxy_map = {
            "socks5": socks.SOCKS5,
            "socks4": socks.SOCKS4,
            "http": socks.HTTP,
        }
        if proxy_type not in proxy_map:
            raise ValueError("Proxy type must be off, mtproto, socks5, socks4, or http.")
        username = (proxy_config.get("proxy_secret") or "").strip() or None
        password = (proxy_config.get("proxy_password") or "").strip() or None
        return {"proxy": (proxy_map[proxy_type], host, port, True, username, password)}

    async def _connect(
        self,
        api_id: str,
        api_hash: str,
        string_session: str,
        bot_token: str,
        proxy_config: Dict[str, str],
    ) -> Dict[str, Any]:
        await self._disconnect()
        if not api_id.strip() or not api_hash.strip():
            raise ValueError("API ID and API Hash are required.")

        session_value = string_session.strip()
        bot_token_value = bot_token.strip()
        if not session_value and not bot_token_value:
            raise ValueError("Provide either a StringSession or a Bot Token.")

        client_kwargs = self._build_proxy_kwargs(proxy_config)
        client = TelegramClient(
            StringSession(session_value if session_value else ""),
            int(api_id),
            api_hash.strip(),
            device_model="ETGmusic",
            system_version="Android",
            app_version="0.2.0",
            system_lang_code="ru",
            lang_code="ru",
            **client_kwargs,
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
            "proxy": proxy_config.get("proxy_type", "off") or "off",
        }

    async def _disconnect(self) -> Dict[str, Any]:
        if self._client is not None:
            await self._client.disconnect()
        self._client = None
        self._message_index.clear()
        return {"state": "offline"}

    async def _fetch_tracks(self, source_refs: List[str], limit: int) -> Dict[str, Any]:
        if self._client is None:
            raise ValueError("Connect to Telegram before refreshing the track list.")
        if not source_refs:
            raise ValueError("Add at least one Telegram source.")

        tracks: List[TrackRecord] = []
        errors: List[str] = []
        self._message_index.clear()

        for source_ref in source_refs:
            try:
                entity = await self._client.get_entity(source_ref)
                source_label = getattr(entity, "title", None) or getattr(entity, "username", None) or source_ref
                async for message in self._client.iter_messages(entity, limit=max(1, limit)):
                    track = self._message_to_track(message, source_label)
                    if track is None:
                        continue
                    tracks.append(track)
                    self._message_index[track.uid] = message
            except Exception as exc:
                errors.append(f"{source_ref}: {exc}")

        tracks.sort(key=lambda track: (track.source_label.lower(), -track.message_id))
        return {"sources": source_refs, "tracks": tracks, "errors": errors}

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
            raise ValueError("Track reference expired. Refresh the source list.")

        suffix = Path(track.file_name).suffix or ".mp3"
        cache_name = f"{track.chat_id}_{track.message_id}_{sanitize_filename(Path(track.file_name).stem)}{suffix}"
        cache_path = self._cache_dir / cache_name
        expected_size = int(track.file_size or 0)

        if cache_path.exists() and expected_size and cache_path.stat().st_size >= expected_size:
            self._emit("stream_ready", {"track_uid": track.uid, "path": str(cache_path)})
            return {"track_uid": track.uid, "path": str(cache_path)}

        if cache_path.exists():
            cache_path.unlink()

        threshold = 512 * 1024
        if expected_size:
            threshold = min(max(expected_size // 9, 384 * 1024), 2 * 1024 * 1024)

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

    async def _fetch_lyrics(self, track: TrackRecord) -> Dict[str, Any]:
        def request() -> Dict[str, Any]:
            params = urllib.parse.urlencode({"track_name": track.title, "artist_name": track.artist})
            url = f"https://lrclib.net/api/search?{params}"
            req = urllib.request.Request(url, headers={"User-Agent": "ETGmusic/0.2"})
            with urllib.request.urlopen(req, timeout=12) as response:
                data = json.loads(response.read().decode("utf-8"))
            if not isinstance(data, list) or not data:
                return {"track_uid": track.uid, "lyrics": "", "source": "LRCLIB"}
            best = next((item for item in data if item.get("syncedLyrics")), data[0])
            lyrics = best.get("syncedLyrics") or best.get("plainLyrics") or ""
            return {
                "track_uid": track.uid,
                "lyrics": lyrics,
                "source": best.get("source") or best.get("name") or "LRCLIB",
            }

        return await asyncio.to_thread(request)


class ETGmusicApp(MDApp):
    status_text = StringProperty("Введи Telegram-сессию или bot token, потом добавь источники.")
    channel_status_text = StringProperty("Источники еще не сканировались.")
    track_counter_text = StringProperty("0 треков")
    current_title = StringProperty("Ничего не выбрано")
    current_artist = StringProperty("Выбери аудио из Telegram-источника.")
    buffer_text = StringProperty("Плеер ждет поток.")
    player_state_text = StringProperty("Stopped")
    position_label = StringProperty("00:00")
    duration_label = StringProperty("00:00")
    lyrics_status_text = StringProperty("Текст трека")
    current_lyrics_text = StringProperty("Здесь появится LRC/lyrics или твой ручной текст.")
    album_status_text = StringProperty("Создай альбом и добавляй туда текущие треки.")
    theme_status_text = StringProperty("Тема: cyber")
    proxy_status_text = StringProperty("Proxy выключен.")
    sleep_timer_text = StringProperty("Sleep timer выключен.")
    track_position = NumericProperty(0.0)
    track_duration = NumericProperty(1.0)
    is_buffering = BooleanProperty(False)

    bg_rgb = ListProperty(THEMES["cyber"]["bg"])
    card_rgb = ListProperty(THEMES["cyber"]["card"])
    hero_rgb = ListProperty(THEMES["cyber"]["hero"])
    accent_rgb = ListProperty(THEMES["cyber"]["accent"])
    line_rgb = ListProperty(THEMES["cyber"]["line"])
    text_rgb = ListProperty(THEMES["cyber"]["text"])
    muted_rgb = ListProperty(THEMES["cyber"]["muted"])

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.settings_path: Optional[Path] = None
        self.state_path: Optional[Path] = None
        self.cache_dir: Optional[Path] = None
        self.backend: Optional[TelegramAudioBackend] = None
        self.audio_player = AndroidAudioPlayer() if platform == "android" else DesktopAudioPlayer()
        self.tracks: List[TrackRecord] = []
        self.track_catalog: Dict[str, TrackRecord] = {}
        self.favorites = set()
        self.albums: Dict[str, List[str]] = {}
        self.lyrics_overrides: Dict[str, str] = {}
        self.current_lrc_lines: List[Tuple[float, str]] = []
        self.current_index = -1
        self.current_track_uid: Optional[str] = None
        self.active_queue: List[str] = []
        self._loaded_audio_path: Optional[str] = None
        self._settings: Dict[str, str] = {}
        self._sleep_event = None
        self._sleep_deadline = 0.0

    def build(self):
        self.title = "ETGmusic"
        self.theme_cls.theme_style = "Dark"
        self.theme_cls.primary_palette = "Green"
        self.theme_cls.accent_palette = "Teal"

        if platform != "android":
            Window.size = (430, 920)

        Builder.load_string(KV)
        root = ScreenManager()
        root.add_widget(LibraryScreen(name="library"))
        root.add_widget(PlayerScreen(name="player"))
        root.add_widget(AlbumsScreen(name="albums"))
        root.add_widget(SettingsScreen(name="settings"))
        return root

    def on_start(self):
        data_dir = Path(self.user_data_dir)
        self.settings_path = data_dir / "settings.json"
        self.state_path = data_dir / "library_state.json"
        self.cache_dir = data_dir / "stream_cache"
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.backend = TelegramAudioBackend(self.cache_dir, self.on_backend_event)
        self._settings = self.load_settings()
        self.load_library_state()
        self.apply_settings_to_ui()
        self.apply_theme(self._settings.get("theme", "cyber"))
        self.render_albums()
        Clock.schedule_interval(self.sync_player_state, 0.5)

    def on_stop(self):
        if self.backend is not None:
            self.backend.stop()
        self.audio_player.stop()

    def on_pause(self):
        return True

    @property
    def library_ids(self):
        return self.root.get_screen("library").ids

    @property
    def player_ids(self):
        return self.root.get_screen("player").ids

    @property
    def album_ids(self):
        return self.root.get_screen("albums").ids

    @property
    def settings_ids(self):
        return self.root.get_screen("settings").ids

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
            "sources": self.library_ids.source_input.text.strip(),
            "scan_limit": self.library_ids.scan_limit_input.text.strip() or "120",
            "proxy_type": self.settings_ids.proxy_type_input.text.strip() or "off",
            "proxy_host": self.settings_ids.proxy_host_input.text.strip(),
            "proxy_port": self.settings_ids.proxy_port_input.text.strip(),
            "proxy_secret": self.settings_ids.proxy_secret_input.text.strip(),
            "proxy_password": self.settings_ids.proxy_password_input.text.strip(),
            "theme": self._settings.get("theme", "cyber"),
        }
        self._settings = values
        if self.settings_path:
            self.settings_path.write_text(json.dumps(values, indent=2, ensure_ascii=False), encoding="utf-8")
        self.proxy_status_text = self.describe_proxy()

    def apply_settings_to_ui(self) -> None:
        self.library_ids.api_id_input.text = self._settings.get("api_id", "")
        self.library_ids.api_hash_input.text = self._settings.get("api_hash", "")
        self.library_ids.string_session_input.text = self._settings.get("string_session", "")
        self.library_ids.bot_token_input.text = self._settings.get("bot_token", "")
        self.library_ids.source_input.text = self._settings.get("sources", "")
        self.library_ids.scan_limit_input.text = self._settings.get("scan_limit", "120")
        self.settings_ids.proxy_type_input.text = self._settings.get("proxy_type", "off")
        self.settings_ids.proxy_host_input.text = self._settings.get("proxy_host", "")
        self.settings_ids.proxy_port_input.text = self._settings.get("proxy_port", "")
        self.settings_ids.proxy_secret_input.text = self._settings.get("proxy_secret", "")
        self.settings_ids.proxy_password_input.text = self._settings.get("proxy_password", "")
        self.proxy_status_text = self.describe_proxy()

    def load_library_state(self) -> None:
        if not self.state_path or not self.state_path.exists():
            return
        try:
            raw = json.loads(self.state_path.read_text(encoding="utf-8"))
        except Exception:
            return
        self.favorites = set(raw.get("favorites", []))
        self.albums = {str(name): list(dict.fromkeys(uids)) for name, uids in raw.get("albums", {}).items()}
        self.lyrics_overrides = {str(uid): str(text) for uid, text in raw.get("lyrics_overrides", {}).items()}
        self.track_catalog = {
            uid: TrackRecord.from_dict(value)
            for uid, value in raw.get("track_catalog", {}).items()
            if isinstance(value, dict)
        }

    def save_library_state(self) -> None:
        if not self.state_path:
            return
        payload = {
            "favorites": sorted(self.favorites),
            "albums": self.albums,
            "lyrics_overrides": self.lyrics_overrides,
            "track_catalog": {uid: asdict(track) for uid, track in self.track_catalog.items()},
        }
        self.state_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")

    def apply_theme(self, name: str) -> None:
        theme_name = name if name in THEMES else "cyber"
        theme = THEMES[theme_name]
        self.bg_rgb = theme["bg"]
        self.card_rgb = theme["card"]
        self.hero_rgb = theme["hero"]
        self.accent_rgb = theme["accent"]
        self.line_rgb = theme["line"]
        self.text_rgb = theme["text"]
        self.muted_rgb = theme["muted"]
        self.theme_cls.theme_style = theme["style"]
        Window.clearcolor = theme["bg"]
        self.theme_status_text = f"Тема: {theme_name}"

    def set_theme(self, name: str) -> None:
        self._settings["theme"] = name
        self.apply_theme(name)
        self.save_settings()

    def describe_proxy(self) -> str:
        proxy_type = (self._settings.get("proxy_type") or "off").strip()
        if proxy_type.lower() in ("", "off", "none", "direct"):
            return "Proxy выключен."
        host = self._settings.get("proxy_host", "").strip()
        port = self._settings.get("proxy_port", "").strip()
        return f"Proxy: {proxy_type} {host}:{port}"

    def current_proxy_config(self) -> Dict[str, str]:
        return {
            "proxy_type": self.settings_ids.proxy_type_input.text.strip() or "off",
            "proxy_host": self.settings_ids.proxy_host_input.text.strip(),
            "proxy_port": self.settings_ids.proxy_port_input.text.strip(),
            "proxy_secret": self.settings_ids.proxy_secret_input.text.strip(),
            "proxy_password": self.settings_ids.proxy_password_input.text.strip(),
        }

    def on_connect_pressed(self) -> None:
        self.save_settings()
        self.status_text = "Подключаюсь к Telegram..."
        self.backend.connect(
            self.library_ids.api_id_input.text,
            self.library_ids.api_hash_input.text,
            self.library_ids.string_session_input.text,
            self.library_ids.bot_token_input.text,
            self.current_proxy_config(),
        )

    def on_disconnect_pressed(self) -> None:
        self.status_text = "Отключаюсь..."
        self.backend.disconnect()
        self.audio_player.stop()
        self.player_state_text = "Stopped"

    def on_refresh_pressed(self) -> None:
        self.save_settings()
        sources = parse_source_refs(self.library_ids.source_input.text)
        limit = int(self.library_ids.scan_limit_input.text or "120")
        self.status_text = f"Сканирую {len(sources)} Telegram-источник(ов)..."
        self.backend.fetch_tracks(sources, limit=limit)

    def is_favorite_uid(self, uid: str) -> bool:
        return uid in self.favorites

    def populate_track_list(self) -> None:
        track_list = self.library_ids.track_list
        if track_list is None:
            return
        query = self.library_ids.search_input.text.strip().lower() if "search_input" in self.library_ids else ""
        track_list.clear_widgets()
        visible_count = 0
        for index, track in enumerate(self.tracks):
            haystack = f"{track.title} {track.artist} {track.source_label}".lower()
            if query and query not in haystack:
                continue
            prefix = "♥ " if track.uid in self.favorites else ""
            track_list.add_widget(
                TrackRow(
                    track_index=index,
                    track_uid=track.uid,
                    text=prefix + track.title,
                    secondary_text=track.subtitle,
                    tertiary_text=track.meta_line,
                )
            )
            visible_count += 1
        self.track_counter_text = f"{visible_count}/{len(self.tracks)} треков"

    def on_track_selected(self, index: int) -> None:
        if index < 0 or index >= len(self.tracks):
            return
        self.current_index = index
        track = self.tracks[index]
        self.current_track_uid = track.uid
        self.track_catalog[track.uid] = track
        self.current_title = track.title
        self.current_artist = track.artist
        self.buffer_text = "Буферизую Telegram stream..."
        self.player_state_text = "Buffering"
        self.track_position = 0.0
        self.track_duration = max(1.0, float(track.duration_seconds or 1))
        self.position_label = "00:00"
        self.duration_label = format_duration(track.duration_seconds)
        self.audio_player.stop()
        self._loaded_audio_path = None
        self.prepare_lyrics_for_track(track)
        self.save_library_state()
        self.switch_screen("player")
        self.backend.stream_track(track)

    def play_previous(self) -> None:
        if not self.tracks:
            return
        new_index = self.resolve_queue_index(-1)
        self.on_track_selected(new_index)

    def play_next(self) -> None:
        if not self.tracks:
            return
        new_index = self.resolve_queue_index(1)
        self.on_track_selected(new_index)

    def resolve_queue_index(self, direction: int) -> int:
        if self.active_queue and self.current_track_uid in self.active_queue:
            queue_index = self.active_queue.index(self.current_track_uid)
            target_uid = self.active_queue[(queue_index + direction) % len(self.active_queue)]
            for index, track in enumerate(self.tracks):
                if track.uid == target_uid:
                    return index
        return (self.current_index + direction) % len(self.tracks)

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
        if self._sleep_deadline:
            remaining = max(0, int(self._sleep_deadline - time.time()))
            self.sleep_timer_text = f"Sleep timer: {format_duration(remaining)} до паузы"
        if self._loaded_audio_path is None:
            return
        position = max(0.0, self.audio_player.position())
        duration = self.audio_player.duration()
        if duration > 0:
            self.track_duration = duration
        self.track_position = min(position, self.track_duration)
        self.position_label = format_duration(int(self.track_position))
        self.duration_label = format_duration(int(self.track_duration))
        if self.current_lrc_lines:
            line = lyric_line_at(self.current_lrc_lines, self.track_position)
            if line:
                self.current_lyrics_text = line

        if self.current_index >= 0 and not self.audio_player.is_playing():
            if self.player_state_text == "Playing" and self.track_position >= max(1.0, self.track_duration - 1.0):
                self.play_next()

    def start_local_playback(self, file_path: str) -> None:
        try:
            self.audio_player.load(file_path)
            self.audio_player.play()
            self._loaded_audio_path = file_path
            self.player_state_text = "Playing"
            self.buffer_text = "Играет через Telegram progressive cache."
        except Exception as exc:
            self.buffer_text = f"Жду больше буфера... {exc}"

    def toggle_current_favorite(self) -> None:
        if not self.current_track_uid:
            return
        if self.current_track_uid in self.favorites:
            self.favorites.remove(self.current_track_uid)
            self.album_status_text = "Убрано из любимых."
        else:
            self.favorites.add(self.current_track_uid)
            self.album_status_text = "Добавлено в любимые."
        self.save_library_state()
        self.populate_track_list()
        self.render_albums()

    def create_album(self) -> None:
        name = self.album_ids.album_name_input.text.strip()
        if not name:
            self.album_status_text = "Введи название альбома."
            return
        self.albums.setdefault(name, [])
        self.save_library_state()
        self.render_albums()
        self.album_status_text = f"Альбом создан: {name}"

    def add_current_to_album(self) -> None:
        if not self.current_track_uid:
            self.album_status_text = "Сначала выбери трек."
            return
        name = self.album_ids.album_name_input.text.strip() or "Мой альбом"
        album = self.albums.setdefault(name, [])
        if self.current_track_uid not in album:
            album.append(self.current_track_uid)
        self.save_library_state()
        self.render_albums()
        self.album_status_text = f"Трек добавлен в {name}."

    def render_albums(self) -> None:
        if self.root is None:
            return
        album_list = self.album_ids.album_list
        album_list.clear_widgets()
        album_list.add_widget(
            AlbumRow(
                album_name="__favorites__",
                text="Любимые треки",
                secondary_text=f"{len(self.favorites)} треков",
                tertiary_text="Локальная подборка",
            )
        )
        for name, uids in sorted(self.albums.items(), key=lambda item: item[0].lower()):
            album_list.add_widget(
                AlbumRow(
                    album_name=name,
                    text=name,
                    secondary_text=f"{len(uids)} треков",
                    tertiary_text="Нажми, чтобы поставить очередь из загруженных треков",
                )
            )

    def play_favorites(self) -> None:
        self.play_uid_collection(sorted(self.favorites), "любимые")

    def play_album(self, album_name: str) -> None:
        if album_name == "__favorites__":
            self.play_favorites()
            return
        self.play_uid_collection(self.albums.get(album_name, []), album_name)

    def play_uid_collection(self, uids: List[str], label: str) -> None:
        available = [uid for uid in uids if any(track.uid == uid for track in self.tracks)]
        if not available:
            self.album_status_text = f"В {label} нет треков из текущего скана. Обнови источники."
            return
        self.active_queue = available
        target_uid = available[0]
        for index, track in enumerate(self.tracks):
            if track.uid == target_uid:
                self.album_status_text = f"Очередь: {label}"
                self.on_track_selected(index)
                return

    def prepare_lyrics_for_track(self, track: TrackRecord) -> None:
        override = self.lyrics_overrides.get(track.uid, "")
        self.player_ids.custom_lyrics_input.text = override
        if override:
            self.apply_lyrics(track.uid, override, "ручной текст")
            return
        self.current_lrc_lines = []
        self.current_lyrics_text = "Ищу текст через LRCLIB..."
        self.lyrics_status_text = "Lyrics: поиск"
        self.fetch_current_lyrics(force=False)

    def fetch_current_lyrics(self, force: bool = True) -> None:
        if not self.current_track_uid:
            return
        track = self.track_catalog.get(self.current_track_uid)
        if not track:
            return
        if not force and self.current_track_uid in self.lyrics_overrides:
            return
        self.lyrics_status_text = "Lyrics: LRCLIB search"
        self.backend.fetch_lyrics(track)

    def save_custom_lyrics(self) -> None:
        if not self.current_track_uid:
            return
        text = self.player_ids.custom_lyrics_input.text.strip()
        if text:
            self.lyrics_overrides[self.current_track_uid] = text
            self.apply_lyrics(self.current_track_uid, text, "ручной текст")
        else:
            self.lyrics_overrides.pop(self.current_track_uid, None)
            self.current_lyrics_text = "Ручной текст очищен."
        self.save_library_state()

    def apply_lyrics(self, uid: str, raw: str, source: str) -> None:
        if uid != self.current_track_uid:
            return
        self.current_lrc_lines = parse_lrc(raw)
        self.lyrics_status_text = f"Lyrics: {source}"
        if self.current_lrc_lines:
            self.current_lyrics_text = lyric_line_at(self.current_lrc_lines, self.track_position) or "LRC загружен."
        else:
            self.current_lyrics_text = raw.strip() or "Текст не найден."

    def start_sleep_timer(self) -> None:
        minutes = int(self.settings_ids.sleep_minutes_input.text or "0")
        if minutes <= 0:
            self.sleep_timer_text = "Укажи минуты больше 0."
            return
        self.cancel_sleep_timer(silent=True)
        self._sleep_deadline = time.time() + (minutes * 60)
        self._sleep_event = Clock.schedule_once(lambda dt: self.on_sleep_timer_expired(), minutes * 60)
        self.sleep_timer_text = f"Sleep timer: {minutes} мин."

    def cancel_sleep_timer(self, silent: bool = False) -> None:
        if self._sleep_event is not None:
            self._sleep_event.cancel()
        self._sleep_event = None
        self._sleep_deadline = 0.0
        if not silent:
            self.sleep_timer_text = "Sleep timer выключен."

    def on_sleep_timer_expired(self) -> None:
        self.audio_player.pause()
        self.player_state_text = "Paused by sleep timer"
        self._sleep_event = None
        self._sleep_deadline = 0.0
        self.sleep_timer_text = "Sleep timer сработал."

    def on_backend_event(self, event_name: str, payload: Dict[str, Any]) -> None:
        if event_name == "connected":
            identity = payload.get("identity", "unknown")
            proxy = payload.get("proxy", "off")
            self.status_text = f"Подключено: {identity}. Proxy: {proxy}."
            if parse_source_refs(self.library_ids.source_input.text):
                self.on_refresh_pressed()
            return

        if event_name == "disconnected":
            self.status_text = "Отключено."
            self.channel_status_text = "Источники не загружены."
            self.tracks = []
            self.populate_track_list()
            return

        if event_name == "tracks_loaded":
            self.tracks = payload.get("tracks", [])
            for track in self.tracks:
                self.track_catalog[track.uid] = track
            self.populate_track_list()
            errors = payload.get("errors", [])
            ok_sources = len(payload.get("sources", [])) - len(errors)
            self.channel_status_text = f"Готово: {ok_sources} источников, ошибок: {len(errors)}"
            self.status_text = f"Найдено {len(self.tracks)} аудио."
            if errors:
                self.status_text += " " + " | ".join(errors[:2])
            self.save_library_state()
            return

        if event_name == "download_progress":
            if payload.get("track_uid") == self.current_track_uid:
                percent = payload.get("percent", 0.0)
                self.buffer_text = f"Telegram buffer... {percent:.0f}%"
            return

        if event_name == "stream_ready":
            if payload.get("track_uid") == self.current_track_uid:
                self.start_local_playback(payload["path"])
            return

        if event_name == "stream_finished":
            if payload.get("track_uid") == self.current_track_uid and self._loaded_audio_path is None:
                self.start_local_playback(payload["path"])
            return

        if event_name == "lyrics_loaded":
            uid = payload.get("track_uid", "")
            lyrics = payload.get("lyrics", "")
            source = payload.get("source", "LRCLIB")
            self.apply_lyrics(uid, lyrics, source if lyrics else "не найдено")
            return

        if event_name == "error":
            self.status_text = f"Ошибка: {payload.get('message', 'unknown error')}"
            self.buffer_text = self.status_text


if __name__ == "__main__":
    ETGmusicApp().run()
