package io.qwulise1.etgmusic

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

class TelegramSyncService : Service() {
    companion object {
        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"
        const val EXTRA_PROGRESS = "progress"
        const val EXTRA_MAX = "max"
        const val EXTRA_INDETERMINATE = "indeterminate"
        const val EXTRA_DONE = "done"

        private const val NOTIFICATION_CHANNEL_ID = "telegram_sync"
        private const val NOTIFICATION_ID = 64026
        private const val WAKE_LOCK_TAG = "ETGmusic:TelegramSync"
        private const val WAKE_LOCK_TIMEOUT_MS = 30L * 60L * 1000L
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) {
            stopSelf(startId)
            return START_NOT_STICKY
        }

        createNotificationChannel()

        val done = intent.getBooleanExtra(EXTRA_DONE, false)
        val title = intent.getStringExtra(EXTRA_TITLE) ?: "ETGmusic"
        val text = intent.getStringExtra(EXTRA_TEXT) ?: ""
        val progress = intent.getIntExtra(EXTRA_PROGRESS, 0)
        val max = intent.getIntExtra(EXTRA_MAX, 0)
        val indeterminate = intent.getBooleanExtra(EXTRA_INDETERMINATE, false)

        val notification = buildNotification(
            title = title,
            text = text,
            progress = progress,
            max = max,
            indeterminate = indeterminate,
            done = done,
        )

        if (done) {
            notificationManager().notify(NOTIFICATION_ID, notification)
            releaseWakeLock()
            stopForegroundCompat(detachNotification = true)
            stopSelf(startId)
            return START_NOT_STICKY
        }

        acquireWakeLock()
        startForeground(NOTIFICATION_ID, notification)
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    private fun buildNotification(
        title: String,
        text: String,
        progress: Int,
        max: Int,
        indeterminate: Boolean,
        done: Boolean,
    ): Notification {
        val openAppIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val icon = if (done) {
            android.R.drawable.stat_sys_download_done
        } else {
            android.R.drawable.stat_sys_download
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder
            .setSmallIcon(icon)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setContentIntent(pendingIntent)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setOngoing(!done)
            .setAutoCancel(done)

        if (!done) {
            if (max > 0) {
                builder.setProgress(max, progress.coerceIn(0, max), indeterminate)
            } else {
                builder.setProgress(0, 0, true)
            }
        }

        return builder.build()
    }

    private fun acquireWakeLock() {
        val current = wakeLock
        if (current?.isHeld == true) return

        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG)
            .apply {
                setReferenceCounted(false)
                acquire(WAKE_LOCK_TIMEOUT_MS)
            }
    }

    private fun releaseWakeLock() {
        val current = wakeLock
        if (current?.isHeld == true) {
            current.release()
        }
        wakeLock = null
    }

    private fun stopForegroundCompat(detachNotification: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(
                if (detachNotification) {
                    STOP_FOREGROUND_DETACH
                } else {
                    STOP_FOREGROUND_REMOVE
                },
            )
        } else {
            @Suppress("DEPRECATION")
            stopForeground(!detachNotification)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            "ETGmusic Telegram sync",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Telegram sync and cache progress"
            setSound(null, null)
        }
        notificationManager().createNotificationChannel(channel)
    }

    private fun notificationManager(): NotificationManager {
        return getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    }
}
