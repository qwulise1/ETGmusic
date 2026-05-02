package io.qwulise1.etgmusic

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: AudioServiceActivity() {
    companion object {
        private const val METHOD_CHANNEL = "io.qwulise1.etgmusic/telegram_sync"
        private const val NOTIFICATION_CHANNEL_ID = "telegram_sync"
        private const val NOTIFICATION_ID = 64026
        private const val NOTIFICATION_PERMISSION_REQUEST = 64027
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestNotificationPermission" -> {
                        result.success(requestNotificationPermission())
                    }
                    "show" -> {
                        showTelegramSyncNotification(
                            title = call.argument<String>("title") ?: "ETGmusic",
                            text = call.argument<String>("text") ?: "",
                            progress = call.argument<Int>("progress") ?: 0,
                            max = call.argument<Int>("max") ?: 0,
                            indeterminate = call.argument<Boolean>("indeterminate") ?: false,
                            done = call.argument<Boolean>("done") ?: false,
                        )
                        result.success(null)
                    }
                    "cancel" -> {
                        notificationManager().cancel(NOTIFICATION_ID)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            return true
        }

        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST,
        )
        return false
    }

    private fun showTelegramSyncNotification(
        title: String,
        text: String,
        progress: Int,
        max: Int,
        indeterminate: Boolean,
        done: Boolean,
    ) {
        createNotificationChannel()

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

        notificationManager().notify(NOTIFICATION_ID, builder.build())
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
