package io.qwulise1.etgmusic;

import android.app.Activity;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.media.AudioAttributes;
import android.media.MediaPlayer;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.widget.Button;
import android.widget.EditText;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.ScrollView;
import android.widget.Space;
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
    private EditText albumNameInput;
    private EditText lyricsManualInput;

    private Theme theme = Theme.cyber();
    private String screen = "library";
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

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(14), dp(10), dp(14), dp(8));
        root.setBackground(gradient(theme.bgTop, theme.bgBottom, 0));

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(false);
        content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(0, 0, 0, dp(16));
        scroll.addView(content, new ScrollView.LayoutParams(-1, -2));

        nav = new LinearLayout(this);
        nav.setOrientation(LinearLayout.HORIZONTAL);
        nav.setGravity(Gravity.CENTER);
        nav.setPadding(dp(8), dp(8), dp(8), dp(8));
        nav.setBackground(round(theme.nav, dp(30), theme.line, 1));

        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1f));
        root.addView(nav, new LinearLayout.LayoutParams(-1, -2));
        setContentView(root);
        renderNav();
    }

    private void renderNav() {
        nav.removeAllViews();
        navButton("Радар", () -> showLibrary());
        navButton("Плеер", () -> showPlayer());
        navButton("Альбомы", () -> showAlbums());
        navButton("Настройки", () -> showSettings());
    }

    private void navButton(String label, Runnable action) {
        TextView view = chip(label, screen.equals(screenName(label)));
        view.setOnClickListener(v -> action.run());
        nav.addView(view, new LinearLayout.LayoutParams(0, dp(48), 1f));
    }

    private String screenName(String label) {
        if ("Плеер".equals(label)) return "player";
        if ("Альбомы".equals(label)) return "albums";
        if ("Настройки".equals(label)) return "settings";
        return "library";
    }

    private void clear(String nextScreen) {
        screen = nextScreen;
        content.removeAllViews();
        renderNav();
    }

    private void showLibrary() {
        clear("library");
        hero("ETGmusic", "Нативный Telegram-first плеер без Kivy: бот-источники, progressive streaming, альбомы, любимые и тексты.");

        statusText = small("Готов. Вставь bot token или прямую ссылку на трек.");
        content.addView(statusText);

        LinearLayout auth = card("Telegram");
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

        LinearLayout manual = card("Быстрый stream URL");
        manual.addView(label("Если хочешь сразу проверить плеер: вставь прямой mp3/ogg/m4a URL."));
        manualTitleInput = input("Название", false);
        manualArtistInput = input("Артист", false);
        manualUrlInput = input("https://...", false);
        manual.addView(manualTitleInput);
        manual.addView(manualArtistInput);
        manual.addView(manualUrlInput);
        manual.addView(button("Добавить URL в библиотеку", v -> addManualTrack()));
        content.addView(manual);

        LinearLayout list = card("Библиотека");
        if (tracks.isEmpty()) {
            list.addView(small("Пока пусто. Просканируй Telegram bot updates или добавь прямой URL."));
        } else {
            for (int i = 0; i < tracks.size(); i++) {
                list.addView(trackRow(i));
            }
        }
        content.addView(list);
    }

    private void showPlayer() {
        clear("player");
        hero("Сейчас играет", currentTrack() == null ? "Выбери трек из библиотеки." : "Streaming deck");

        LinearLayout deck = card("");
        TextView art = new TextView(this);
        art.setText("≋");
        art.setTextSize(86);
        art.setGravity(Gravity.CENTER);
        art.setTypeface(Typeface.DEFAULT_BOLD);
        art.setTextColor(theme.accent);
        deck.addView(art, new LinearLayout.LayoutParams(-1, dp(150)));

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
                iconButton("⏮", v -> playOffset(-1)),
                iconButton("▶ / ⏸", v -> togglePlayback()),
                iconButton("⏭", v -> playOffset(1))
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
        hero("Коллекции", "Любимые и локальные альбомы. Хранятся на устройстве, треки берутся из текущей библиотеки.");

        LinearLayout create = card("Новый альбом");
        albumNameInput = input("Название альбома", false);
        create.addView(albumNameInput);
        create.addView(row(button("Создать", v -> createAlbum()), button("Добавить текущий", v -> addCurrentToAlbum())));
        content.addView(create);

        LinearLayout fav = card("Любимые");
        fav.addView(small(favorites.size() + " треков"));
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
        hero("Настройки", "Темы, proxy и будущий MTProto core без мусорного Python runtime.");

        LinearLayout themes = card("Темы");
        themes.addView(row(button("Cyber", v -> setTheme("cyber")), button("Ice", v -> setTheme("ice")), button("Amber", v -> setTheme("amber"))));
        themes.addView(row(button("Ruby", v -> setTheme("ruby")), button("Forest", v -> setTheme("forest")), button("Mono", v -> setTheme("mono"))));
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
        if (playerTitle != null && track != null) {
            playerTitle.setText(track.title);
            playerArtist.setText(track.artist + " • " + track.source);
        }
        if (playerState != null) {
            playerState.setText(player != null && player.isPlaying() ? "Playing" : "Paused/Stopped");
        }
        if (player != null && progressBar != null && timeText != null) {
            try {
                int duration = Math.max(player.getDuration(), 1);
                int position = Math.max(player.getCurrentPosition(), 0);
                progressBar.setProgress((int) ((position / (float) duration) * 1000f));
                timeText.setText(formatMs(position) + " / " + formatMs(duration));
                updateLyrics(position / 1000f);
            } catch (IllegalStateException ignored) {
                progressBar.setProgress(0);
                timeText.setText("00:00 / 00:00");
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
        hero.setPadding(dp(18), dp(18), dp(18), dp(18));
        hero.setBackground(gradient(theme.heroTop, theme.heroBottom, dp(34)));
        TextView t = title(title);
        TextView s = small(subtitle);
        hero.addView(t);
        hero.addView(s);
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

    private TextView trackRow(int index) {
        Track track = tracks.get(index);
        String heart = favorites.contains(track.uid) ? "♥  " : "";
        TextView row = rowText(heart + track.title, track.artist + " • " + track.source + " • " + (track.size / 1024 / 1024) + " MB");
        row.setOnClickListener(v -> playTrack(index));
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
        final int text;
        final int muted;
        final int hint;
        final int accent;
        final int line;
        final int buttonText;

        Theme(int bgTop, int bgBottom, int heroTop, int heroBottom, int card, int row, int input, int nav, int text, int muted, int hint, int accent, int line, int buttonText) {
            this.bgTop = bgTop;
            this.bgBottom = bgBottom;
            this.heroTop = heroTop;
            this.heroBottom = heroBottom;
            this.card = card;
            this.row = row;
            this.input = input;
            this.nav = nav;
            this.text = text;
            this.muted = muted;
            this.hint = hint;
            this.accent = accent;
            this.line = line;
            this.buttonText = buttonText;
        }

        static Theme cyber() {
            return new Theme(c("#061018"), c("#02040A"), c("#07333B"), c("#0A1326"), c("#141A24"), c("#101722"), c("#0B111A"), c("#0C1119"), c("#F1FBFF"), c("#9AA8B7"), c("#607080"), c("#00E0A4"), c("#335B58"), c("#03100D"));
        }

        static Theme ice() {
            return new Theme(c("#EAF7FF"), c("#D7E8FF"), c("#BFE5FF"), c("#F7FCFF"), c("#FFFFFF"), c("#EFF7FF"), c("#F7FBFF"), c("#F7FBFF"), c("#07111E"), c("#46586A"), c("#7A8FA3"), c("#136DFF"), c("#B8D6FF"), c("#FFFFFF"));
        }

        static Theme amber() {
            return new Theme(c("#170B04"), c("#070402"), c("#4B2508"), c("#1F0E04"), c("#21130A"), c("#2A180B"), c("#160C06"), c("#1A0F08"), c("#FFF4E3"), c("#C4A88B"), c("#8B715A"), c("#FF9D2E"), c("#69401B"), c("#190B02"));
        }

        static Theme ruby() {
            return new Theme(c("#170412"), c("#070209"), c("#4A0A2B"), c("#1B0615"), c("#21101B"), c("#2A1021"), c("#160812"), c("#1A0A15"), c("#FFF1FA"), c("#C49AAC"), c("#86596B"), c("#FF3366"), c("#6A2340"), c("#20020B"));
        }

        static Theme forest() {
            return new Theme(c("#06140C"), c("#020705"), c("#0F3D22"), c("#092015"), c("#102019"), c("#10291B"), c("#0A160F"), c("#0B1710"), c("#F0FFF4"), c("#9CC1A5"), c("#5E8068"), c("#55EE73"), c("#2E5F3C"), c("#061207"));
        }

        static Theme mono() {
            return new Theme(c("#070709"), c("#020203"), c("#2A2A30"), c("#111116"), c("#17171D"), c("#202027"), c("#0F0F13"), c("#111116"), c("#F5F5F7"), c("#A0A0AA"), c("#707078"), c("#EDEDF2"), c("#4A4A52"), c("#08080A"));
        }

        static int c(String hex) {
            return Color.parseColor(hex);
        }
    }
}
