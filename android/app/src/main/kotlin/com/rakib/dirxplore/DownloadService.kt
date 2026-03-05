package com.rakib.dirxplore

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class DownloadService : Service() {
    companion object {
        const val CHANNEL_ID = "DownloadServiceChannel"
        const val ACTION_PAUSE = "com.rakib.dirxplore.PAUSE"
        const val ACTION_RESUME = "com.rakib.dirxplore.RESUME"
        const val ACTION_CANCEL = "com.rakib.dirxplore.CANCEL"
        
        // Broadcast actions for MainActivity
        const val NOTIFICATION_ACTION_BROADCAST = "com.rakib.dirxplore.NOTIFICATION_ACTION"
    }

    private val notificationManager: NotificationManager by lazy {
        getSystemService(NOTIFICATION_SERVICE) as NotificationManager
    }

    private var lastFilename: String = "Downloading..."
    private var isPaused: Boolean = false

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        val id = intent?.getIntExtra("id", 1001) ?: 1001

        when (action) {
            "START_DOWNLOAD" -> {
                lastFilename = intent.getStringExtra("filename") ?: "Unknown File"
                isPaused = false
                startForeground(id, createNotification(lastFilename, 0, "Starting...", false))
            }
            "UPDATE_PROGRESS" -> {
                val progress = intent.getIntExtra("progress", 0)
                val speed = intent.getStringExtra("speed") ?: ""
                isPaused = false
                notificationManager.notify(id, createNotification(lastFilename, progress, speed, false))
            }
            "STOP_DOWNLOAD" -> {
                stopForeground(true)
                stopSelf()
            }
            ACTION_PAUSE, ACTION_RESUME, ACTION_CANCEL -> {
                // Forward action to MainActivity via broadcast
                val broadcastIntent = Intent(NOTIFICATION_ACTION_BROADCAST).apply {
                    putExtra("action", action)
                    putExtra("id", id)
                    setPackage(packageName)
                }
                sendBroadcast(broadcastIntent)
                
                // Update notification state toggle if it's pause/resume
                if (action == ACTION_PAUSE) {
                    isPaused = true
                    notificationManager.notify(id, createNotification(lastFilename, -1, "Paused", true))
                } else if (action == ACTION_RESUME) {
                    isPaused = false
                    notificationManager.notify(id, createNotification(lastFilename, -1, "Resuming...", false))
                }
            }
        }
        return START_NOT_STICKY
    }

    private fun createNotification(title: String, progress: Int, contentText: String, paused: Boolean): android.app.Notification {
        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val contentPendingIntent = PendingIntent.getActivity(this, 0, notificationIntent, pendingIntentFlags)

        // Pause/Resume Action
        val actionIntent = Intent(this, DownloadService::class.java).apply {
            action = if (paused) ACTION_RESUME else ACTION_PAUSE
            putExtra("id", 1001) // Using 1001 as default
        }
        val actionPendingIntent = PendingIntent.getService(this, 1, actionIntent, pendingIntentFlags)
        val actionLabel = if (paused) "Resume" else "Pause"
        val actionIcon = if (paused) android.R.drawable.ic_media_play else android.R.drawable.ic_media_pause

        // Cancel Action
        val cancelIntent = Intent(this, DownloadService::class.java).apply {
            action = ACTION_CANCEL
            putExtra("id", 1001)
        }
        val cancelPendingIntent = PendingIntent.getService(this, 2, cancelIntent, pendingIntentFlags)

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentIntent(contentPendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .addAction(actionIcon, actionLabel, actionPendingIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Cancel", cancelPendingIntent)

        if (progress >= 0) {
            builder.setProgress(100, progress, progress == 0)
        }

        return builder.build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "Download Service Channel",
                NotificationManager.IMPORTANCE_LOW 
            )
            notificationManager.createNotificationChannel(serviceChannel)
        }
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }
}
