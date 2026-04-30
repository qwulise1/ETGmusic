package io.qwulise1.etgmusic;

import android.app.Activity;
import android.content.SharedPreferences;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.media.AudioAttributes;
import android.media.MediaPlayer;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.Editable;
import android.text.InputType;
import android.text.TextUtils;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.View;
import android.view.Window;
import android.widget.Button;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.ScrollView;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class MainActivity extends Activity {
    private static final String PREFS = "etgmusic_native";

    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private final ArrayList<Track> tracks = new ArrayList<>();
    private final Set<String> favorites = new HashSet<>();
    private final Map<String, ArrayList<String>> albums = new LinkedHashMap<>();
    private final ArrayList<LrcLine> lrcLines = new ArrayList<>();

    private SharedPreferences prefs;
    private LinearLayout content;
    private LinearLayout nav;
    private LinearLayout miniPlayer;
    private TextView miniTitle;
    private TextView miniSubtitle;
    private ProgressBar miniProgress;
    private TextView statusText;
    private TextView playerTitle;
    private TextView playerArtist;
    private TextView playerState;
    private TextView timeText;
    private TextView lyricsText;
    private TextView sleepText;
    private ProgressBar progressBar;
    private EditText botTokenInput;
    private EditText sessionInput;
    private EditText sourcesInput;
    private EditText manualTitleInput;
    private EditText manualArtistInput;
    private EditText manualUrlInput;
    private EditText librarySearchInput;
    private EditText albumNameInput;
    private EditText lyricsManualInput;

    private Theme theme = Theme.cyber();
    private String screen = "library";
    private String libraryFilter = "";
    private MediaPlayer player;
    private int currentIndex = -1;
    private long sleepDeadlineMs = 0L;
    private Runnable sleepRunnable;

    private final Runnable progressRunnable = new Runnable() {
        @Override
        public void run() {
            syncProgress();
            mainHandler.postDelayed(this, 500L);
        }
    };

    @Override
    protected void onCreate(Bundle bundle) {
        super.onCreate(bundle);
        prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
        loadState();
        applyTheme(prefs.getString("theme", "cyber"));
        buildShell();
        showLibrary();
        mainHandler.post(progressRunnable);
    }

    @Override
    protected void onDestroy() {
        mainHandler.removeCallbacksAndMessages(null);
        io.shutdownNow();
        releasePlayer();
        super.onDestroy();
    }

    private void buildShell() {
        Window window = getWindow();
        window.setStatusBarColor(theme.bgTop);
        window.setNavigationBarColor(theme.bgBottom);

        FrameLayout rootFrame = new FrameLayout(this);
        rootFrame.setBackgroundColor(theme.bgBottom);
        rootFrame.addView(new BackdropView(this), new FrameLayout.LayoutParams(-1, -1));

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(14), dp(12), dp(14), dp(8));

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(false);
        scroll.setClipToPadding(false);
        content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(0, 0, 0, dp(22));
        scroll.addView(content, new ScrollView.LayoutParams(-1, -2));

        miniPlayer = new LinearLayout(this);
        miniPlayer.setOrientation(LinearLayout.VERTICAL);
        miniPlayer.setPadding(0, 0, 0, 0);
        miniPlayer.setBackground(round(theme.card, dp(18), theme.line, 1));
        miniPlayer.setOnClickListener(v -> showPlayer());

        nav = new LinearLayout(this);
        nav.setOrientation(LinearLayout.HORIZONTAL);
        nav.setGravity(Gravity.CENTER);
        nav.setPadding(dp(6), dp(6), dp(6), dp(6));
        nav.setBackground(round(theme.navStrong, dp(30), theme.line, 1));

        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1f));
        root.addView(miniPlayer, withBottomMargin(new LinearLayout.LayoutParams(-1, -2), dp(8)));
        root.addView(nav, new LinearLayout.LayoutParams(-1, -2));
        rootFrame.addView(root, new FrameLayout.LayoutParams(-1, -1));
        setContentView(rootFrame);
        renderNav();
        renderMiniPlayer();
    }

    private void renderNav() {
        nav.removeAllViews();
        navButton("⌂", "Дом", () -> showLibrary());
        navButton("≋", "Плеер", () -> showPlayer());
        navButton("▣", "Альбомы", () -> showAlbums());
        navButton("⚙", "Сетап", () -> showSettings());
    }

    private void navButton(String icon, String label, Runnable action) {
        TextView view = chip(icon + "\n" + label, screen.equals(screenName(label)));
        view.setLineSpacing(0f, 0.92f);
        view.setOnClickListener(v -> action.run());
        nav.addView(view, new LinearLayout.LayoutParams(0, dp(48), 1f));
    }

    private String screenName(String label) {
        if ("Плеер".equals(label)) return "player";
        if ("Альбомы".equals(label)) return "albums";
        if ("Настройки".equals(label) || "Сетап".equals(label)) return "settings";
        return "library";
    }

    private void clear(String nextScreen) {
        screen = nextScreen;
        content.removeAllViews();
        renderNav();
        renderMiniPlayer();
    }

    private void renderMiniPlayer() {
        if (miniPlayer == null) return;
        miniPlayer.removeAllViews();
        Track track = currentTrack();
        if (track == null) {
            miniPlayer.setVisibility(View.GONE);
            return;
        }
        miniPlayer.setVisibility(View.VISIBLE);

        miniProgress = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        miniProgress.setMax(1000);
        miniPlayer.addView(miniProgress, new LinearLayout.LayoutParams(-1, dp(3)));

        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(dp(10), dp(8), dp(10), dp(8));
        row.addView(new ArtTile(this, track.title, theme.accent, theme.heroBottom), new LinearLayout.LayoutParams(dp(46), dp(46)));

        LinearLayout copy = new LinearLayout(this);
        copy.setOrientation(LinearLayout.VERTICAL);
        copy.setPadding(dp(10), 0, dp(10), 0);
        miniTitle = compact(track.title, theme.text, 15, true);
        miniSubtitle = compact(track.artist + " • " + track.source, theme.muted, 12, false);
        copy.addView(miniTitle);
        copy.addView(miniSubtitle);
        row.addView(copy, new LinearLayout.LayoutParams(0, -2, 1f));

        TextView play = compact(player != null && player.isPlaying() ? "Ⅱ" : "▶", theme.buttonText, 18, true);
        play.setGravity(Gravity.CENTER);
        play.setBackground(round(theme.accent, dp(18), theme.accent, 0));
        play.setOnClickListener(v -> togglePlayback());
        row.addView(play, new LinearLayout.LayoutParams(dp(40), dp(40)));

        TextView next = compact("›", theme.text, 20, true);
        next.setGravity(Gravity.CENTER);
        next.setOnClickListener(v -> playOffset(1));
        row.addView(next, new LinearLayout.LayoutParams(dp(34), dp(40)));
        miniPlayer.addView(row);
        syncProgress();
    }

    private void showLibrary() {
        clear("library");
        hero("ETGmusic", "Telegram streams, saved albums, lyrics and sleep timer.");
        content.addView(searchPanel());
        content.addView(quickStats());
        content.addView(sectionTitle("Quick picks"));
        content.addView(discoveryShelf());

        statusText = small("Готов. Добавь Telegram-источник или прямой URL. Поиск фильтрует локальную библиотеку.");
        content.addView(statusText);

        content.addView(sectionTitle("Библиотека"));
        LinearLayout list = card("");
        int visible = 0;
        for (int i = 0; i < tracks.size(); i++) {
            if (matchesFilter(tracks.get(i))) {
                list.addView(trackRow(i));
                visible++;
            }
        }
        if (visible == 0) {
            list.addView(emptyState());
        }
        content.addView(list);

        content.addView(sectionTitle("Источники"));
        LinearLayout auth = card("Telegram radar");
        auth.addView(label("Bot token"));
        botTokenInput = input("123456:ABC...", false);
        botTokenInput.setText(prefs.getString("bot_token", ""));
        auth.addView(botTokenInput);
        auth.addView(label("StringSession / TDLib slot"));
        sessionInput = input("Будущий MTProto user-login слой. Сейчас сохраняется локально.", true);
        sessionInput.setText(prefs.getString("string_session", ""));
        auth.addView(sessionInput);
        auth.addView(label("Источники: @канал, id, title. Один на строку. Для bot mode читаются getUpdates/channel_post."));
        sourcesInput = input("@music_channel\n-1001234567890", true);
        sourcesInput.setText(prefs.getString("sources", ""));
        auth.addView(sourcesInput);
        auth.addView(row(button("Сохранить", v -> saveInputs()), button("Сканировать bot updates", v -> scanTelegramBot())));
        content.addView(auth);

        LinearLayout manual = card("Быстрый stream");
        manual.addView(label("Прямая ссылка на mp3 / ogg / m4a"));
        manualTitleInput = input("Название", false);
        manualArtistInput = input("Артист", false);
        manualUrlInput = input("https://...", false);
        manual.addView(manualTitleInput);
        manual.addView(manualArtistInput);
        manual.addView(manualUrlInput);
        manual.addView(button("Добавить URL в библиотеку", v -> addManualTrack()));
        content.addView(manual);
    }

    private void showPlayer() {
        clear("player");
        hero("Плеер", currentTrack() == null ? "Выбери трек из библиотеки." : "Живой Telegram stream deck");

        LinearLayout deck = card("");
        Track current = currentTrack();
        ArtTile art = new ArtTile(this, current == null ? "ETGmusic" : current.title, theme.accent, theme.heroBottom);
        LinearLayout.LayoutParams artLp = new LinearLayout.LayoutParams(dp(246), dp(246));
        artLp.gravity = Gravity.CENTER_HORIZONTAL;
        artLp.setMargins(0, dp(8), 0, dp(18));
        deck.addView(art, artLp);

        playerTitle = title(currentTrack() == null ? "Ничего не выбрано" : currentTrack().title);
        playerTitle.setGravity(Gravity.CENTER);
        playerArtist = small(currentTrack() == null ? "ETGmusic" : currentTrack().artist);
        playerArtist.setGravity(Gravity.CENTER);
        playerState = small(player != null && player.isPlaying() ? "Playing" : "Stopped");
        playerState.setGravity(Gravity.CENTER);
        playerState.setTextColor(theme.accent);

        progressBar = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        progressBar.setMax(1000);
        progressBar.setProgress(0);
        timeText = small("00:00 / 00:00");
        timeText.setGravity(Gravity.CENTER);

        deck.addView(playerTitle);
        deck.addView(playerArtist);
        deck.addView(playerState);
        deck.addView(progressBar, new LinearLayout.LayoutParams(-1, dp(22)));
        deck.addView(timeText);
        deck.addView(row(
                ghostButton("‹", v -> playOffset(-1)),
                iconButton(player != null && player.isPlaying() ? "Ⅱ" : "▶", v -> togglePlayback()),
                ghostButton("›", v -> playOffset(1))
        ));
        deck.addView(row(
                button("Любимый", v -> toggleFavorite()),
                button("В альбом", v -> addCurrentToAlbum())
        ));
        content.addView(deck);

        LinearLayout lyrics = card("Lyrics");
        lyricsText = small("Текст появится здесь. Поддерживается LRC-синхронизация.");
        lyricsText.setGravity(Gravity.CENTER);
        lyricsManualInput = input("Свой текст или LRC", true);
        Track track = currentTrack();
        if (track != null) {
            lyricsManualInput.setText(prefs.getString("lyrics_" + track.uid, ""));
            loadLyricsFor(track);
        }
        lyrics.addView(lyricsText);
        lyrics.addView(lyricsManualInput);
        lyrics.addView(row(button("LRCLIB", v -> fetchLyrics()), button("Сохранить текст", v -> saveManualLyrics())));
        content.addView(lyrics);

        LinearLayout timer = card("Sleep timer");
        sleepText = small("Выключен");
        timer.addView(sleepText);
        timer.addView(row(
                button("15 мин", v -> startSleepTimer(15)),
                button("30 мин", v -> startSleepTimer(30)),
                button("Сброс", v -> cancelSleepTimer())
        ));
        content.addView(timer);
        syncProgress();
    }

    private void showAlbums() {
        clear("albums");
        hero("Коллекции", "Свои альбомы поверх Telegram-треков. Похоже на медиатеку, но без привязки к одному сервису.");
        content.addView(quickStats());

        LinearLayout create = card("Новый альбом");
        albumNameInput = input("Название альбома", false);
        create.addView(albumNameInput);
        create.addView(row(button("Создать", v -> createAlbum()), button("Добавить текущий", v -> addCurrentToAlbum())));
        content.addView(create);

        LinearLayout fav = card("Любимые");
        fav.addView(metricPill("♥", favorites.size() + " треков", "Быстрая очередь"));
        fav.addView(button("Играть любимые", v -> playCollection(new ArrayList<>(favorites))));
        content.addView(fav);

        LinearLayout albumList = card("Альбомы");
        if (albums.isEmpty()) {
            albumList.addView(small("Альбомов пока нет."));
        } else {
            for (Map.Entry<String, ArrayList<String>> entry : albums.entrySet()) {
                TextView row = rowText(entry.getKey(), entry.getValue().size() + " треков");
                row.setOnClickListener(v -> playCollection(entry.getValue()));
                albumList.addView(row);
            }
        }
        content.addView(albumList);
    }

    private void showSettings() {
        clear("settings");
        hero("Сетап", "Темы, proxy и Telegram core без мусорного Python runtime.");

        LinearLayout themes = card("Темы");
        themes.addView(small("Каждая тема меняет не только цвет кнопки, а всю атмосферу плеера."));
        themes.addView(row(button("Default", v -> setTheme("cyber")), button("Light", v -> setTheme("ice")), button("Amber", v -> setTheme("amber"))));
        themes.addView(row(button("Ruby", v -> setTheme("ruby")), button("Forest", v -> setTheme("forest")), button("AMOLED", v -> setTheme("mono"))));
        content.addView(themes);

        LinearLayout proxy = card("Proxy");
        proxy.addView(label("MTProxy/SOCKS настройки сохраняются для Telegram core. Bot API scanner использует прямой HTTPS."));
        EditText type = input("off / mtproto / socks5", false);
        EditText host = input("host", false);
        EditText port = input("port", false);
        EditText secret = input("secret / login", false);
        type.setText(prefs.getString("proxy_type", "off"));
        host.setText(prefs.getString("proxy_host", ""));
        port.setText(prefs.getString("proxy_port", ""));
        secret.setText(prefs.getString("proxy_secret", ""));
        proxy.addView(type);
        proxy.addView(host);
        proxy.addView(port);
        proxy.addView(secret);
        proxy.addView(button("Сохранить proxy", v -> {
            prefs.edit()
                    .putString("proxy_type", type.getText().toString().trim())
                    .putString("proxy_host", host.getText().toString().trim())
                    .putString("proxy_port", port.getText().toString().trim())
                    .putString("proxy_secret", secret.getText().toString().trim())
                    .apply();
            toast("Proxy сохранен");
        }));
        content.addView(proxy);
    }

    private void scanTelegramBot() {
        saveInputs();
        String token = botTokenInput.getText().toString().trim();
        if (token.isEmpty()) {
            toast("Нужен bot token");
            return;
        }
        status("Сканирую Telegram Bot API updates...");
        io.execute(() -> {
            try {
                List<Track> found = fetchBotTracks(token, parseSources(sourcesInput.getText().toString()));
                mainHandler.post(() -> {
                    tracks.clear();
                    tracks.addAll(found);
                    saveTracks();
                    status("Найдено " + found.size() + " треков через bot updates.");
                    showLibrary();
                });
            } catch (Exception e) {
                mainHandler.post(() -> status("Ошибка Telegram scan: " + e.getMessage()));
            }
        });
    }

    private List<Track> fetchBotTracks(String token, List<String> filters) throws Exception {
        ArrayList<Track> out = new ArrayList<>();
        String updatesRaw = httpGet("https://api.telegram.org/bot" + token + "/getUpdates?limit=100");
        JSONObject updates = new JSONObject(updatesRaw);
        if (!updates.optBoolean("ok")) {
            throw new IllegalStateException(updates.optString("description", "getUpdates failed"));
        }
        JSONArray result = updates.optJSONArray("result");
        if (result == null) return out;
        for (int i = 0; i < result.length(); i++) {
            JSONObject update = result.optJSONObject(i);
            if (update == null) continue;
            JSONObject message = update.optJSONObject("channel_post");
            if (message == null) message = update.optJSONObject("message");
            if (message == null) continue;
            JSONObject chat = message.optJSONObject("chat");
            String source = chatLabel(chat);
            if (!matchesSource(chat, source, filters)) continue;
            JSONObject audio = message.optJSONObject("audio");
            JSONObject document = message.optJSONObject("document");
            JSONObject media = audio != null ? audio : document;
            if (media == null) continue;
            String mime = media.optString("mime_type", "");
            if (audio == null && !mime.startsWith("audio/")) continue;
            String fileId = media.optString("file_id", "");
            if (fileId.isEmpty()) continue;
            String filePath = resolveBotFilePath(token, fileId);
            if (filePath.isEmpty()) continue;
            String url = "https://api.telegram.org/file/bot" + token + "/" + filePath;
            String title = media.optString("title", media.optString("file_name", "Telegram audio"));
            String artist = media.optString("performer", source);
            int duration = media.optInt("duration", 0);
            long size = media.optLong("file_size", 0L);
            String uid = media.optString("file_unique_id", chat.optString("id") + ":" + message.optString("message_id"));
            out.add(new Track(uid, title, artist, source, url, duration, size));
        }
        return out;
    }

    private String resolveBotFilePath(String token, String fileId) throws Exception {
        String encoded = URLEncoder.encode(fileId, "UTF-8");
        String raw = httpGet("https://api.telegram.org/bot" + token + "/getFile?file_id=" + encoded);
        JSONObject json = new JSONObject(raw);
        if (!json.optBoolean("ok")) return "";
        JSONObject result = json.optJSONObject("result");
        return result == null ? "" : result.optString("file_path", "");
    }

    private String httpGet(String url) throws Exception {
        HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
        connection.setConnectTimeout(12_000);
        connection.setReadTimeout(20_000);
        connection.setRequestProperty("User-Agent", "ETGmusic-native/0.3");
        try (InputStream input = connection.getResponseCode() >= 400 ? connection.getErrorStream() : connection.getInputStream()) {
            if (input == null) return "";
            BufferedReader reader = new BufferedReader(new InputStreamReader(input, StandardCharsets.UTF_8));
            StringBuilder builder = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) {
                builder.append(line);
            }
            return builder.toString();
        } finally {
            connection.disconnect();
        }
    }

    private void addManualTrack() {
        String url = manualUrlInput.getText().toString().trim();
        if (!url.startsWith("http://") && !url.startsWith("https://")) {
            toast("Нужна http/https ссылка");
            return;
        }
        String title = valueOr(manualTitleInput.getText().toString(), "Manual stream");
        String artist = valueOr(manualArtistInput.getText().toString(), "URL");
        Track track = new Track("manual:" + Math.abs(url.hashCode()), title, artist, "Manual", url, 0, 0);
        tracks.add(0, track);
        saveTracks();
        showLibrary();
    }

    private void playTrack(int index) {
        if (index < 0 || index >= tracks.size()) return;
        currentIndex = index;
        Track track = tracks.get(index);
        releasePlayer();
        player = new MediaPlayer();
        player.setAudioAttributes(new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build());
        player.setWakeMode(this, android.os.PowerManager.PARTIAL_WAKE_LOCK);
        try {
            player.setDataSource(track.url);
            player.setOnPreparedListener(mp -> {
                mp.start();
                toast("Играет: " + track.title);
                showPlayer();
            });
            player.setOnCompletionListener(mp -> playOffset(1));
            player.setOnErrorListener((mp, what, extra) -> {
                toast("MediaPlayer error " + what + "/" + extra);
                return true;
            });
            player.prepareAsync();
            showPlayer();
        } catch (Exception e) {
            toast("Не открыл поток: " + e.getMessage());
        }
    }

    private void togglePlayback() {
        if (player == null) {
            if (currentIndex >= 0) playTrack(currentIndex);
            return;
        }
        if (player.isPlaying()) {
            player.pause();
        } else {
            player.start();
        }
        syncProgress();
    }

    private void playOffset(int offset) {
        if (tracks.isEmpty()) return;
        int next = currentIndex < 0 ? 0 : (currentIndex + offset + tracks.size()) % tracks.size();
        playTrack(next);
    }

    private void releasePlayer() {
        if (player != null) {
            try {
                player.release();
            } catch (Exception ignored) {
            }
        }
        player = null;
    }

    private void syncProgress() {
        Track track = currentTrack();
        if (miniPlayer != null) {
            miniPlayer.setVisibility(track == null ? View.GONE : View.VISIBLE);
        }
        if (playerTitle != null && track != null) {
            playerTitle.setText(track.title);
            playerArtist.setText(track.artist + " • " + track.source);
        }
        if (miniTitle != null && track != null) {
            miniTitle.setText(track.title);
            miniSubtitle.setText(track.artist + " • " + track.source);
        }
        if (playerState != null) {
            playerState.setText(player != null && player.isPlaying() ? "Playing" : "Paused/Stopped");
        }
        if (player != null) {
            try {
                int duration = Math.max(player.getDuration(), 1);
                int position = Math.max(player.getCurrentPosition(), 0);
                int progress = (int) ((position / (float) duration) * 1000f);
                if (progressBar != null) progressBar.setProgress(progress);
                if (miniProgress != null) miniProgress.setProgress(progress);
                if (timeText != null) timeText.setText(formatMs(position) + " / " + formatMs(duration));
                updateLyrics(position / 1000f);
            } catch (IllegalStateException ignored) {
                if (progressBar != null) progressBar.setProgress(0);
                if (miniProgress != null) miniProgress.setProgress(0);
                if (timeText != null) timeText.setText("00:00 / 00:00");
            }
        }
        if (sleepText != null && sleepDeadlineMs > 0) {
            long left = Math.max(0L, sleepDeadlineMs - System.currentTimeMillis());
            sleepText.setText("Осталось " + formatMs(left));
        }
    }

    private void fetchLyrics() {
        Track track = currentTrack();
        if (track == null) return;
        lyricsText.setText("Ищу текст...");
        io.execute(() -> {
            try {
                String url = "https://lrclib.net/api/search?track_name=" +
                        URLEncoder.encode(track.title, "UTF-8") +
                        "&artist_name=" + URLEncoder.encode(track.artist, "UTF-8");
                JSONArray array = new JSONArray(httpGet(url));
                String lyrics = "";
                for (int i = 0; i < array.length(); i++) {
                    JSONObject item = array.optJSONObject(i);
                    if (item == null) continue;
                    lyrics = item.optString("syncedLyrics", "");
                    if (!lyrics.isEmpty()) break;
                    lyrics = item.optString("plainLyrics", "");
                }
                String finalLyrics = lyrics;
                mainHandler.post(() -> applyLyrics(finalLyrics.isEmpty() ? "Текст не найден." : finalLyrics));
            } catch (Exception e) {
                mainHandler.post(() -> lyricsText.setText("Lyrics error: " + e.getMessage()));
            }
        });
    }

    private void saveManualLyrics() {
        Track track = currentTrack();
        if (track == null) return;
        String text = lyricsManualInput.getText().toString();
        prefs.edit().putString("lyrics_" + track.uid, text).apply();
        applyLyrics(text);
    }

    private void loadLyricsFor(Track track) {
        applyLyrics(prefs.getString("lyrics_" + track.uid, ""));
    }

    private void applyLyrics(String raw) {
        lrcLines.clear();
        if (raw == null || raw.trim().isEmpty()) {
            if (lyricsText != null) lyricsText.setText("Текста пока нет.");
            return;
        }
        Pattern pattern = Pattern.compile("\\[(\\d{1,2}):(\\d{2})(?:[.:](\\d{1,3}))?]");
        StringBuilder plain = new StringBuilder();
        for (String line : raw.split("\\R")) {
            Matcher matcher = pattern.matcher(line);
            String text = matcher.replaceAll("").trim();
            boolean synced = false;
            matcher.reset();
            while (matcher.find()) {
                int minutes = Integer.parseInt(matcher.group(1));
                int seconds = Integer.parseInt(matcher.group(2));
                int millis = matcher.group(3) == null ? 0 : Integer.parseInt((matcher.group(3) + "000").substring(0, 3));
                lrcLines.add(new LrcLine(minutes * 60f + seconds + millis / 1000f, text));
                synced = true;
            }
            if (!synced) plain.append(line).append('\n');
        }
        if (lyricsText != null) lyricsText.setText(lrcLines.isEmpty() ? plain.toString().trim() : "LRC синхронизация включена");
    }

    private void updateLyrics(float seconds) {
        if (lyricsText == null || lrcLines.isEmpty()) return;
        String current = "";
        for (LrcLine line : lrcLines) {
            if (line.time <= seconds + 0.2f) current = line.text;
            else break;
        }
        if (!current.isEmpty()) lyricsText.setText(current);
    }

    private void toggleFavorite() {
        Track track = currentTrack();
        if (track == null) return;
        if (favorites.contains(track.uid)) favorites.remove(track.uid);
        else favorites.add(track.uid);
        saveState();
        toast(favorites.contains(track.uid) ? "В любимых" : "Убрано из любимых");
    }

    private void createAlbum() {
        String name = albumNameInput == null ? "" : albumNameInput.getText().toString().trim();
        if (name.isEmpty()) {
            toast("Название альбома пустое");
            return;
        }
        albums.putIfAbsent(name, new ArrayList<>());
        saveState();
        showAlbums();
    }

    private void addCurrentToAlbum() {
        Track track = currentTrack();
        if (track == null) {
            toast("Сначала выбери трек");
            return;
        }
        String name = albumNameInput == null ? "" : albumNameInput.getText().toString().trim();
        if (name.isEmpty()) name = "Мой альбом";
        ArrayList<String> list = albums.get(name);
        if (list == null) {
            list = new ArrayList<>();
            albums.put(name, list);
        }
        if (!list.contains(track.uid)) list.add(track.uid);
        saveState();
        toast("Добавлено в " + name);
    }

    private void playCollection(List<String> ids) {
        for (String id : ids) {
            for (int i = 0; i < tracks.size(); i++) {
                if (tracks.get(i).uid.equals(id)) {
                    playTrack(i);
                    return;
                }
            }
        }
        toast("В текущем скане нет этих треков");
    }

    private void startSleepTimer(int minutes) {
        cancelSleepTimer();
        sleepDeadlineMs = System.currentTimeMillis() + minutes * 60_000L;
        sleepRunnable = () -> {
            if (player != null && player.isPlaying()) player.pause();
            sleepDeadlineMs = 0L;
            toast("Sleep timer сработал");
            syncProgress();
        };
        mainHandler.postDelayed(sleepRunnable, minutes * 60_000L);
        syncProgress();
    }

    private void cancelSleepTimer() {
        if (sleepRunnable != null) mainHandler.removeCallbacks(sleepRunnable);
        sleepRunnable = null;
        sleepDeadlineMs = 0L;
        if (sleepText != null) sleepText.setText("Выключен");
    }

    private Track currentTrack() {
        if (currentIndex < 0 || currentIndex >= tracks.size()) return null;
        return tracks.get(currentIndex);
    }

    private void saveInputs() {
        prefs.edit()
                .putString("bot_token", botTokenInput.getText().toString().trim())
                .putString("string_session", sessionInput.getText().toString().trim())
                .putString("sources", sourcesInput.getText().toString().trim())
                .apply();
        toast("Сохранено");
    }

    private void loadState() {
        favorites.clear();
        favorites.addAll(prefs.getStringSet("favorites", new HashSet<>()));
        albums.clear();
        String albumsRaw = prefs.getString("albums", "{}");
        try {
            JSONObject object = new JSONObject(albumsRaw);
            JSONArray names = object.names();
            if (names != null) {
                for (int i = 0; i < names.length(); i++) {
                    String name = names.getString(i);
                    JSONArray ids = object.optJSONArray(name);
                    ArrayList<String> list = new ArrayList<>();
                    if (ids != null) {
                        for (int j = 0; j < ids.length(); j++) list.add(ids.getString(j));
                    }
                    albums.put(name, list);
                }
            }
        } catch (Exception ignored) {
        }
        loadTracks();
    }

    private void saveState() {
        JSONObject object = new JSONObject();
        try {
            for (Map.Entry<String, ArrayList<String>> entry : albums.entrySet()) {
                JSONArray ids = new JSONArray();
                for (String id : entry.getValue()) ids.put(id);
                object.put(entry.getKey(), ids);
            }
        } catch (Exception ignored) {
        }
        prefs.edit()
                .putStringSet("favorites", new HashSet<>(favorites))
                .putString("albums", object.toString())
                .apply();
    }

    private void saveTracks() {
        JSONArray array = new JSONArray();
        try {
            for (Track track : tracks) array.put(track.toJson());
        } catch (Exception ignored) {
        }
        prefs.edit().putString("tracks", array.toString()).apply();
        saveState();
    }

    private void loadTracks() {
        tracks.clear();
        try {
            JSONArray array = new JSONArray(prefs.getString("tracks", "[]"));
            for (int i = 0; i < array.length(); i++) tracks.add(Track.fromJson(array.getJSONObject(i)));
        } catch (Exception ignored) {
        }
    }

    private void setTheme(String name) {
        prefs.edit().putString("theme", name).apply();
        applyTheme(name);
        buildShell();
        if ("player".equals(screen)) showPlayer();
        else if ("albums".equals(screen)) showAlbums();
        else if ("settings".equals(screen)) showSettings();
        else showLibrary();
    }

    private void applyTheme(String name) {
        if ("ice".equals(name)) theme = Theme.ice();
        else if ("amber".equals(name)) theme = Theme.amber();
        else if ("ruby".equals(name)) theme = Theme.ruby();
        else if ("forest".equals(name)) theme = Theme.forest();
        else if ("mono".equals(name)) theme = Theme.mono();
        else theme = Theme.cyber();
    }

    private List<String> parseSources(String raw) {
        ArrayList<String> out = new ArrayList<>();
        for (String line : raw.split("[\\n,;]+")) {
            String value = line.trim().toLowerCase(Locale.ROOT);
            if (!value.isEmpty()) out.add(value);
        }
        return out;
    }

    private boolean matchesSource(JSONObject chat, String label, List<String> filters) {
        if (filters.isEmpty()) return true;
        String id = chat == null ? "" : chat.optString("id", "");
        String username = chat == null ? "" : chat.optString("username", "");
        String title = label.toLowerCase(Locale.ROOT);
        for (String filter : filters) {
            String cleaned = filter.replace("@", "");
            if (id.equals(filter) || username.equalsIgnoreCase(cleaned) || title.contains(cleaned)) return true;
        }
        return false;
    }

    private String chatLabel(JSONObject chat) {
        if (chat == null) return "Telegram";
        String title = chat.optString("title", "");
        if (!title.isEmpty()) return title;
        String username = chat.optString("username", "");
        if (!username.isEmpty()) return "@" + username;
        return chat.optString("id", "Telegram");
    }

    private void status(String message) {
        if (statusText != null) statusText.setText(message);
    }

    private void toast(String message) {
        status(message);
    }

    private String valueOr(String value, String fallback) {
        String trimmed = value == null ? "" : value.trim();
        return trimmed.isEmpty() ? fallback : trimmed;
    }

    private String formatMs(long ms) {
        long total = Math.max(0L, ms / 1000L);
        long minutes = total / 60L;
        long seconds = total % 60L;
        return String.format(Locale.ROOT, "%02d:%02d", minutes, seconds);
    }

    private void hero(String title, String subtitle) {
        LinearLayout hero = new LinearLayout(this);
        hero.setOrientation(LinearLayout.VERTICAL);
        hero.setPadding(dp(4), dp(18), dp(4), dp(10));

        LinearLayout top = new LinearLayout(this);
        top.setOrientation(LinearLayout.HORIZONTAL);
        top.setGravity(Gravity.CENTER_VERTICAL);

        LinearLayout copy = new LinearLayout(this);
        copy.setOrientation(LinearLayout.VERTICAL);
        TextView eyebrow = compact("qwulise music core", theme.accent, 11, true);
        TextView t = title(title);
        TextView s = small(subtitle);
        copy.addView(eyebrow);
        copy.addView(t);
        copy.addView(s);
        top.addView(copy, new LinearLayout.LayoutParams(0, -2, 1f));

        TextView action = compact("EQ", theme.buttonText, 12, true);
        action.setGravity(Gravity.CENTER);
        action.setBackground(round(theme.accent, dp(18), theme.accent, 0));
        action.setOnClickListener(v -> showSettings());
        top.addView(action, new LinearLayout.LayoutParams(dp(44), dp(36)));
        hero.addView(top);

        LinearLayout mood = new LinearLayout(this);
        mood.setOrientation(LinearLayout.HORIZONTAL);
        mood.setPadding(0, dp(10), 0, 0);
        mood.addView(infoChip("Quick picks"));
        mood.addView(infoChip("Songs"));
        mood.addView(infoChip("Albums"));
        hero.addView(mood);
        content.addView(hero, withBottomMargin(new LinearLayout.LayoutParams(-1, -2), dp(12)));
    }

    private LinearLayout card(String heading) {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(16), dp(16), dp(16), dp(16));
        card.setBackground(round(theme.card, dp(28), theme.line, 1));
        if (!heading.isEmpty()) card.addView(label(heading));
        card.setClipToOutline(false);
        LinearLayout.LayoutParams lp = withBottomMargin(new LinearLayout.LayoutParams(-1, -2), dp(12));
        card.setLayoutParams(lp);
        return card;
    }

    private View trackRow(int index) {
        Track track = tracks.get(index);
        String heart = favorites.contains(track.uid) ? "♥  " : "";
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(dp(10), dp(10), dp(12), dp(10));
        row.setBackground(round(theme.row, dp(24), theme.line, 1));
        row.addView(new ArtTile(this, track.title, theme.accent, theme.heroBottom), new LinearLayout.LayoutParams(dp(58), dp(58)));

        LinearLayout copy = new LinearLayout(this);
        copy.setOrientation(LinearLayout.VERTICAL);
        copy.setPadding(dp(12), 0, dp(8), 0);
        copy.addView(compact(heart + track.title, theme.text, 15, true));
        copy.addView(compact(track.artist + " • " + track.source, theme.muted, 12, false));
        copy.addView(compact((track.size > 0 ? (track.size / 1024 / 1024) + " MB • " : "") + (track.url.startsWith("http") ? "stream" : "local"), theme.hint, 11, false));
        row.addView(copy, new LinearLayout.LayoutParams(0, -2, 1f));

        TextView play = compact("▶", theme.buttonText, 15, true);
        play.setGravity(Gravity.CENTER);
        play.setBackground(round(theme.accent, dp(17), theme.accent, 0));
        row.addView(play, new LinearLayout.LayoutParams(dp(38), dp(38)));
        row.setOnClickListener(v -> playTrack(index));
        row.setLayoutParams(withBottomMargin(new LinearLayout.LayoutParams(-1, -2), dp(8)));
        return row;
    }

    private TextView rowText(String title, String subtitle) {
        TextView view = small(title + "\n" + subtitle);
        view.setTextSize(15);
        view.setPadding(dp(14), dp(12), dp(14), dp(12));
        view.setBackground(round(theme.row, dp(22), theme.line, 1));
        view.setGravity(Gravity.CENTER_VERTICAL);
        LinearLayout.LayoutParams lp = withBottomMargin(new LinearLayout.LayoutParams(-1, -2), dp(8));
        view.setLayoutParams(lp);
        return view;
    }

    private TextView compact(String text, int color, int sp, boolean bold) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setTextColor(color);
        view.setTextSize(sp);
        view.setSingleLine(true);
        view.setEllipsize(TextUtils.TruncateAt.END);
        view.setIncludeFontPadding(false);
        if (bold) view.setTypeface(Typeface.DEFAULT_BOLD);
        return view;
    }

    private TextView sectionTitle(String text) {
        TextView view = compact(text, theme.text, 22, true);
        view.setPadding(dp(2), dp(12), dp(2), dp(10));
        return view;
    }

    private View searchPanel() {
        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.HORIZONTAL);
        panel.setGravity(Gravity.CENTER_VERTICAL);
        panel.setPadding(dp(12), dp(8), dp(8), dp(8));
        panel.setBackground(round(theme.input, dp(22), theme.line, 1));

        TextView icon = compact("⌕", theme.accent, 20, true);
        icon.setGravity(Gravity.CENTER);
        panel.addView(icon, new LinearLayout.LayoutParams(dp(30), dp(42)));

        librarySearchInput = input("Поиск по трекам, артистам, источникам", false);
        librarySearchInput.setText(libraryFilter);
        librarySearchInput.setSingleLine(true);
        librarySearchInput.setBackgroundColor(Color.TRANSPARENT);
        librarySearchInput.setPadding(dp(4), 0, dp(4), 0);
        librarySearchInput.addTextChangedListener(new TextWatcher() {
            @Override
            public void beforeTextChanged(CharSequence s, int start, int count, int after) {
            }

            @Override
            public void onTextChanged(CharSequence s, int start, int before, int count) {
                libraryFilter = s == null ? "" : s.toString();
            }

            @Override
            public void afterTextChanged(Editable s) {
            }
        });
        panel.addView(librarySearchInput, new LinearLayout.LayoutParams(0, dp(42), 1f));

        TextView apply = compact("OK", theme.buttonText, 12, true);
        apply.setGravity(Gravity.CENTER);
        apply.setBackground(round(theme.accent, dp(17), theme.accent, 0));
        apply.setOnClickListener(v -> showLibrary());
        panel.addView(apply, new LinearLayout.LayoutParams(dp(44), dp(34)));

        panel.setLayoutParams(withBottomMargin(new LinearLayout.LayoutParams(-1, -2), dp(12)));
        return panel;
    }

    private boolean matchesFilter(Track track) {
        String filter = libraryFilter == null ? "" : libraryFilter.trim().toLowerCase(Locale.ROOT);
        if (filter.isEmpty()) return true;
        return track.title.toLowerCase(Locale.ROOT).contains(filter)
                || track.artist.toLowerCase(Locale.ROOT).contains(filter)
                || track.source.toLowerCase(Locale.ROOT).contains(filter)
                || track.url.toLowerCase(Locale.ROOT).contains(filter);
    }

    private LinearLayout quickStats() {
        LinearLayout stats = new LinearLayout(this);
        stats.setOrientation(LinearLayout.HORIZONTAL);
        stats.setGravity(Gravity.CENTER);
        addMetric(stats, metricPill("♪", String.valueOf(tracks.size()), "треков"));
        addMetric(stats, metricPill("♥", String.valueOf(favorites.size()), "любимых"));
        addMetric(stats, metricPill("▣", String.valueOf(albums.size()), "альбомов"));
        stats.setLayoutParams(withBottomMargin(new LinearLayout.LayoutParams(-1, -2), dp(12)));
        return stats;
    }

    private void addMetric(LinearLayout stats, View metric) {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, -2, 1f);
        lp.setMargins(dp(4), 0, dp(4), 0);
        stats.addView(metric, lp);
    }

    private View discoveryShelf() {
        HorizontalScrollView scroll = new HorizontalScrollView(this);
        scroll.setHorizontalScrollBarEnabled(false);
        scroll.setClipToPadding(false);

        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setPadding(0, 0, dp(2), 0);
        row.addView(featureCard("01", "Telegram radar", "Каналы, группы, bot updates", () -> {
            if (botTokenInput != null) botTokenInput.requestFocus();
        }));
        row.addView(featureCard("02", "Direct stream", "mp3, ogg, m4a по ссылке", () -> {
            if (manualUrlInput != null) manualUrlInput.requestFocus();
        }));
        row.addView(featureCard("03", "Lyrics", "LRCLIB и ручной LRC", () -> showPlayer()));
        row.addView(featureCard("04", "Sleep", "15/30 минут таймер", () -> showPlayer()));
        scroll.addView(row, new HorizontalScrollView.LayoutParams(-2, -2));
        scroll.setLayoutParams(withBottomMargin(new LinearLayout.LayoutParams(-1, -2), dp(12)));
        return scroll;
    }

    private View featureCard(String icon, String title, String subtitle, Runnable action) {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(14), dp(14), dp(14), dp(14));
        card.setBackground(round(theme.card, dp(24), theme.line, 1));
        card.setOnClickListener(v -> action.run());

        TextView badge = compact(icon, theme.buttonText, 12, true);
        badge.setGravity(Gravity.CENTER);
        badge.setBackground(round(theme.accent, dp(14), theme.accent, 0));
        card.addView(badge, new LinearLayout.LayoutParams(dp(36), dp(28)));
        card.addView(compact(title, theme.text, 16, true));

        TextView sub = small(subtitle);
        sub.setMaxLines(2);
        sub.setEllipsize(TextUtils.TruncateAt.END);
        card.addView(sub);

        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(dp(172), dp(116));
        lp.setMargins(0, 0, dp(10), 0);
        card.setLayoutParams(lp);
        return card;
    }

    private View emptyState() {
        LinearLayout empty = new LinearLayout(this);
        empty.setOrientation(LinearLayout.VERTICAL);
        empty.setGravity(Gravity.CENTER);
        empty.setPadding(dp(12), dp(24), dp(12), dp(20));
        empty.addView(compact("Пока пусто", theme.text, 22, true));
        TextView sub = small("Добавь Telegram bot token, источники или прямую ссылку. Потом тут будет нормальная медиатека, а не список из демо-затычек.");
        sub.setGravity(Gravity.CENTER);
        sub.setMaxLines(4);
        empty.addView(sub);
        return empty;
    }

    private View metricPill(String icon, String value, String label) {
        LinearLayout pill = new LinearLayout(this);
        pill.setOrientation(LinearLayout.VERTICAL);
        pill.setGravity(Gravity.CENTER);
        pill.setPadding(dp(8), dp(12), dp(8), dp(12));
        pill.setBackground(round(theme.row, dp(24), theme.line, 1));
        pill.addView(compact(icon, theme.accent, 19, true));
        TextView valueView = compact(value, theme.text, 20, true);
        valueView.setGravity(Gravity.CENTER);
        pill.addView(valueView);
        TextView labelView = compact(label, theme.muted, 11, false);
        labelView.setGravity(Gravity.CENTER);
        pill.addView(labelView);
        return pill;
    }

    private LinearLayout row(View... children) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER);
        row.setPadding(0, dp(8), 0, 0);
        for (View child : children) {
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, -2, 1f);
            lp.setMargins(dp(4), 0, dp(4), 0);
            row.addView(child, lp);
        }
        return row;
    }

    private TextView title(String text) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setTextColor(theme.text);
        view.setTextSize(32);
        view.setTypeface(Typeface.DEFAULT_BOLD);
        view.setIncludeFontPadding(false);
        return view;
    }

    private TextView label(String text) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setTextColor(theme.text);
        view.setTextSize(17);
        view.setTypeface(Typeface.DEFAULT_BOLD);
        view.setPadding(0, dp(5), 0, dp(6));
        return view;
    }

    private TextView small(String text) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setTextColor(theme.muted);
        view.setTextSize(14);
        view.setLineSpacing(dp(2), 1.0f);
        view.setPadding(0, dp(4), 0, dp(4));
        return view;
    }

    private EditText input(String hint, boolean multiline) {
        EditText view = new EditText(this);
        view.setHint(hint);
        view.setHintTextColor(theme.hint);
        view.setTextColor(theme.text);
        view.setTextSize(14);
        view.setSingleLine(!multiline);
        view.setMinLines(multiline ? 3 : 1);
        view.setGravity(multiline ? Gravity.TOP | Gravity.START : Gravity.CENTER_VERTICAL);
        view.setInputType(InputType.TYPE_CLASS_TEXT | (multiline ? InputType.TYPE_TEXT_FLAG_MULTI_LINE : 0));
        view.setPadding(dp(14), dp(10), dp(14), dp(10));
        view.setBackground(round(theme.input, dp(18), theme.line, 1));
        LinearLayout.LayoutParams lp = withBottomMargin(new LinearLayout.LayoutParams(-1, -2), dp(8));
        view.setLayoutParams(lp);
        return view;
    }

    private Button button(String text, View.OnClickListener listener) {
        Button button = new Button(this);
        button.setText(text);
        button.setTextColor(theme.buttonText);
        button.setTextSize(12);
        button.setAllCaps(false);
        button.setBackground(round(theme.accent, dp(18), theme.accent, 0));
        button.setOnClickListener(listener);
        return button;
    }

    private Button ghostButton(String text, View.OnClickListener listener) {
        Button button = new Button(this);
        button.setText(text);
        button.setTextColor(theme.text);
        button.setTextSize(18);
        button.setAllCaps(false);
        button.setBackground(round(theme.row, dp(18), theme.line, 1));
        button.setOnClickListener(listener);
        return button;
    }

    private Button iconButton(String text, View.OnClickListener listener) {
        Button button = button(text, listener);
        button.setTextSize(18);
        return button;
    }

    private TextView chip(String text, boolean selected) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setTextSize(12);
        view.setGravity(Gravity.CENTER);
        view.setTypeface(Typeface.DEFAULT_BOLD);
        view.setTextColor(selected ? theme.buttonText : theme.text);
        view.setBackground(round(selected ? theme.accent : Color.TRANSPARENT, dp(22), theme.line, 1));
        return view;
    }

    private TextView infoChip(String text) {
        TextView view = compact(text, theme.muted, 12, true);
        view.setGravity(Gravity.CENTER);
        view.setPadding(dp(12), 0, dp(12), 0);
        view.setBackground(round(theme.row, dp(16), theme.line, 1));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-2, dp(32));
        lp.setMargins(0, 0, dp(8), 0);
        view.setLayoutParams(lp);
        return view;
    }

    private GradientDrawable gradient(int top, int bottom, int radius) {
        GradientDrawable drawable = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[]{top, bottom});
        drawable.setCornerRadius(radius);
        return drawable;
    }

    private GradientDrawable round(int color, int radius, int strokeColor, int strokeWidth) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(color);
        drawable.setCornerRadius(radius);
        if (strokeWidth > 0) drawable.setStroke(dp(strokeWidth), strokeColor);
        return drawable;
    }

    private LinearLayout.LayoutParams withBottomMargin(LinearLayout.LayoutParams lp, int bottom) {
        lp.setMargins(0, 0, 0, bottom);
        return lp;
    }

    private int dp(int value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }

    private final class BackdropView extends View {
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);

        BackdropView(Activity context) {
            super(context);
        }

        @Override
        protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            canvas.drawColor(theme.bgBottom);
            int width = getWidth();
            int height = getHeight();
            paint.setStyle(Paint.Style.FILL);

            paint.setColor(withAlpha(theme.heroTop, 70));
            canvas.drawCircle(width * 0.12f, height * 0.03f, Math.max(width, height) * 0.22f, paint);

            paint.setColor(withAlpha(theme.accent, 36));
            canvas.drawCircle(width * 0.95f, height * 0.12f, Math.max(width, height) * 0.16f, paint);

            paint.setColor(withAlpha(theme.heroBottom, 72));
            canvas.drawCircle(width * 0.78f, height * 0.82f, Math.max(width, height) * 0.24f, paint);

            paint.setColor(withAlpha(theme.line, 42));
            paint.setStrokeWidth(dp(1));
            for (int i = 0; i < 8; i++) {
                float y = height * (0.2f + i * 0.09f);
                canvas.drawLine(dp(12), y, width - dp(12), y, paint);
            }
        }
    }

    private final class ArtTile extends View {
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final RectF rect = new RectF();
        private final String seed;
        private final int accent;
        private final int base;

        ArtTile(Activity context, String seed, int accent, int base) {
            super(context);
            this.seed = seed == null ? "ETGmusic" : seed;
            this.accent = accent;
            this.base = base;
        }

        @Override
        protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            float w = getWidth();
            float h = getHeight();
            float radius = Math.min(w, h) * 0.22f;
            rect.set(0, 0, w, h);

            paint.setStyle(Paint.Style.FILL);
            paint.setColor(base);
            canvas.drawRoundRect(rect, radius, radius, paint);

            int hash = seed.hashCode();
            paint.setColor(withAlpha(accent, 118));
            canvas.drawCircle(w * ((hash & 3) + 3) / 7f, h * 0.22f, w * 0.48f, paint);

            paint.setColor(withAlpha(theme.heroTop, 150));
            canvas.drawCircle(w * 0.1f, h * 0.95f, w * 0.62f, paint);

            paint.setColor(withAlpha(theme.text, 235));
            paint.setStrokeCap(Paint.Cap.ROUND);
            paint.setStrokeWidth(Math.max(dp(3), w * 0.055f));
            for (int i = 0; i < 5; i++) {
                float x = w * (0.22f + i * 0.14f);
                float top = h * (0.62f - (((hash >> i) & 7) / 32f));
                canvas.drawLine(x, h * 0.72f, x, top, paint);
            }

            paint.setStyle(Paint.Style.FILL);
            paint.setTypeface(Typeface.DEFAULT_BOLD);
            paint.setTextAlign(Paint.Align.CENTER);
            paint.setTextSize(Math.max(dp(18), w * 0.24f));
            String initial = seed.trim().isEmpty() ? "E" : seed.trim().substring(0, 1).toUpperCase(Locale.ROOT);
            canvas.drawText(initial, w * 0.5f, h * 0.45f, paint);
            paint.setTypeface(Typeface.DEFAULT);
        }
    }

    private int withAlpha(int color, int alpha) {
        return Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color));
    }

    private static final class Track {
        final String uid;
        final String title;
        final String artist;
        final String source;
        final String url;
        final int duration;
        final long size;

        Track(String uid, String title, String artist, String source, String url, int duration, long size) {
            this.uid = uid;
            this.title = title;
            this.artist = artist;
            this.source = source;
            this.url = url;
            this.duration = duration;
            this.size = size;
        }

        JSONObject toJson() throws Exception {
            JSONObject object = new JSONObject();
            object.put("uid", uid);
            object.put("title", title);
            object.put("artist", artist);
            object.put("source", source);
            object.put("url", url);
            object.put("duration", duration);
            object.put("size", size);
            return object;
        }

        static Track fromJson(JSONObject object) {
            return new Track(
                    object.optString("uid"),
                    object.optString("title", "Track"),
                    object.optString("artist", "Unknown"),
                    object.optString("source", "Local"),
                    object.optString("url"),
                    object.optInt("duration", 0),
                    object.optLong("size", 0L)
            );
        }
    }

    private static final class LrcLine {
        final float time;
        final String text;

        LrcLine(float time, String text) {
            this.time = time;
            this.text = text;
        }
    }

    private static final class Theme {
        final int bgTop;
        final int bgBottom;
        final int heroTop;
        final int heroBottom;
        final int card;
        final int row;
        final int input;
        final int nav;
        final int navStrong;
        final int text;
        final int muted;
        final int hint;
        final int accent;
        final int line;
        final int buttonText;

        Theme(int bgTop, int bgBottom, int heroTop, int heroBottom, int card, int row, int input, int nav, int navStrong, int text, int muted, int hint, int accent, int line, int buttonText) {
            this.bgTop = bgTop;
            this.bgBottom = bgBottom;
            this.heroTop = heroTop;
            this.heroBottom = heroBottom;
            this.card = card;
            this.row = row;
            this.input = input;
            this.nav = nav;
            this.navStrong = navStrong;
            this.text = text;
            this.muted = muted;
            this.hint = hint;
            this.accent = accent;
            this.line = line;
            this.buttonText = buttonText;
        }

        static Theme cyber() {
            return new Theme(c("#16171D"), c("#101116"), c("#222534"), c("#1F2029"), c("#1F2029"), c("#2B2D3B"), c("#242632"), c("#1F2029"), c("#16171D"), c("#E1E1E2"), c("#A3A4A6"), c("#6F6F73"), c("#7C83FF"), c("#333645"), c("#FFFFFF"));
        }

        static Theme ice() {
            return new Theme(c("#FDFDFE"), c("#F3F4FA"), c("#F8F8FC"), c("#EAEAF5"), c("#FFFFFF"), c("#F0F1F8"), c("#F7F7FC"), c("#FFFFFF"), c("#F8F8FC"), c("#212121"), c("#656566"), c("#9D9D9D"), c("#5055C0"), c("#DCDDFA"), c("#FFFFFF"));
        }

        static Theme amber() {
            return new Theme(c("#18130D"), c("#0E0B08"), c("#2C2417"), c("#21190F"), c("#211A12"), c("#302515"), c("#251C11"), c("#211A12"), c("#171008"), c("#FFF1DB"), c("#C8AF8C"), c("#857057"), c("#F4A949"), c("#4C3921"), c("#1C1105"));
        }

        static Theme ruby() {
            return new Theme(c("#191218"), c("#100B0F"), c("#30202B"), c("#251620"), c("#241820"), c("#34202B"), c("#271720"), c("#241820"), c("#170D13"), c("#FFF0F8"), c("#C9A2B7"), c("#866276"), c("#FF5C8A"), c("#523244"), c("#210711"));
        }

        static Theme forest() {
            return new Theme(c("#101812"), c("#090F0B"), c("#1D2C20"), c("#142018"), c("#162019"), c("#203227"), c("#18241C"), c("#162019"), c("#0E150F"), c("#EFFAF1"), c("#A4BDA8"), c("#687C6B"), c("#68D080"), c("#33513B"), c("#071308"));
        }

        static Theme mono() {
            return new Theme(c("#070708"), c("#000000"), c("#1B1B1E"), c("#101012"), c("#0E0E10"), c("#1B1B1F"), c("#151518"), c("#0E0E10"), c("#000000"), c("#F5F5F7"), c("#A0A0AA"), c("#707078"), c("#EDEDF2"), c("#333338"), c("#08080A"));
        }

        static int c(String hex) {
            return Color.parseColor(hex);
        }
    }
}
