package lk.posex.posex_app

import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService

/**
 * Builds InboxStyle stacks natively so sales group when the app is backgrounded.
 * Still calls [super] so FlutterFire token / Dart handlers keep working.
 */
class PosexFirebaseMessagingService : FlutterFirebaseMessagingService() {
    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        val data = remoteMessage.data
        val title = (data["title"]
            ?: remoteMessage.notification?.title
            ?: "PosEx").trim()
        val body = (data["body"]
            ?: remoteMessage.notification?.body
            ?: "").trim()
        val type = (data["notification_type"] ?: "general").trim()

        if (body.isNotEmpty()) {
            PosexGroupedPush.show(applicationContext, title, body, type)
        }

        // Let FlutterFire deliver to Dart (foreground streams / background isolate).
        super.onMessageReceived(remoteMessage)
    }
}
