package com.musync.musync_mimo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

/// Foreground service that keeps the app alive in background.
///
/// This prevents Android from killing the app during active sessions,
/// especially on Xiaomi, Samsung, Huawei devices with aggressive battery optimization.
class MusyncForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "musync_playback"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START = "com.musync.START"
        const val ACTION_STOP = "com.musync.STOP"

        private var wakeLock: PowerManager.WakeLock? = null

        fun start(context: Context, title: String = "MusyncMIMO") {
            val intent = Intent(context, MusyncForegroundService::class.java).apply {
                action = ACTION_START
                putExtra("title", title)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, MusyncForegroundService::class.java).apply {
                action = ACTION_STOP
            }
            context.stopService(intent)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val title = intent.getStringExtra("title") ?: "MusyncMIMO"
                val notification = buildNotification(title)
                startForeground(NOTIFICATION_ID, notification)
                acquireWakeLock()
            }
            ACTION_STOP -> {
                stopSelf()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Lecture musicale",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Notification affichée pendant la lecture musicale synchronisée"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(title: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText("Synchronisation musicale en cours")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setSilent(true)
            .build()
    }

    private fun acquireWakeLock() {
        if (wakeLock == null) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "MusyncMIMO::PlaybackWakeLock"
            ).apply {
                acquire(60 * 60 * 1000L) // 1 hour max
            }
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
            }
        }
        wakeLock = null
    }
}
