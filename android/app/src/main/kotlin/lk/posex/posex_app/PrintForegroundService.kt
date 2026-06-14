package lk.posex.posex_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/// Keeps the Flutter process alive so the embedded :9753 print server keeps
/// accepting remote print jobs while the app is in the background.
class PrintForegroundService : Service() {
    companion object {
        const val CHANNEL_ID = "posex_print_server"
        const val NOTIFICATION_ID = 9753
        const val EXTRA_CONNECTED_COUNT = "connected_count"
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val connected = intent?.getIntExtra(EXTRA_CONNECTED_COUNT, 0) ?: 0
        if (connected <= 0) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        val notification = buildNotification(connected)
        startForeground(NOTIFICATION_ID, notification)
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildNotification(connectedCount: Int): Notification {
        val printerLabel = if (connectedCount == 1) {
            "1 printer connected"
        } else {
            "$connectedCount printers connected"
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("PosEx Print Server")
            .setContentText("Remote printing active — $printerLabel")
            .setSmallIcon(R.drawable.ic_stat_print)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Print Server",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Keeps PosEx remote printing active in the background"
            setShowBadge(false)
        }
        getSystemService(NotificationManager::class.java)
            ?.createNotificationChannel(channel)
    }
}
