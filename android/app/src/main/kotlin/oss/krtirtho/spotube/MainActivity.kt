package io.qwulise1.etgmusic

import android.Manifest
import android.app.NotificationManager
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
                        stopService(Intent(this, TelegramSyncService::class.java))
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
        val intent = Intent(this, TelegramSyncService::class.java).apply {
            putExtra(TelegramSyncService.EXTRA_TITLE, title)
            putExtra(TelegramSyncService.EXTRA_TEXT, text)
            putExtra(TelegramSyncService.EXTRA_PROGRESS, progress)
            putExtra(TelegramSyncService.EXTRA_MAX, max)
            putExtra(TelegramSyncService.EXTRA_INDETERMINATE, indeterminate)
            putExtra(TelegramSyncService.EXTRA_DONE, done)
        }

        try {
            if (done || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                startService(intent)
            } else {
                startForegroundService(intent)
            }
        } catch (error: IllegalStateException) {
            stopService(Intent(this, TelegramSyncService::class.java))
        }
    }

    private fun notificationManager(): NotificationManager {
        return getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    }
}
