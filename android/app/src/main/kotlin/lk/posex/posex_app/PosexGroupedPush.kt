package lk.posex.posex_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.json.JSONArray

/**
 * InboxStyle grouped tray notifications (one stack per type, newest on top).
 * Used by [PosexFirebaseMessagingService] so grouping works when the app is
 * backgrounded/killed — not only while Flutter is in the foreground.
 */
object PosexGroupedPush {
    const val CHANNEL_ID = "posex_push"
    const val PREFS = "posex_push_groups"
    const val EXTRA_GROUP_KEY = "posex_group_key"
    const val ACTION_OPEN = "lk.posex.posex_app.OPEN_FROM_PUSH"

    private const val MAX_LINES = 8
    private const val KEY_PREFIX = "lines_"

    private val labels = mapOf(
        "sales" to "Sales",
        "edited_bills" to "Edited bills",
        "exchange_tokens" to "Exchange tokens",
        "refunds" to "Refunds",
        "supplier_bills" to "Supplier bills",
        "new_suppliers" to "New suppliers",
        "expenses" to "Expenses",
        "cash_register_closed" to "Cash register closed",
        "cash_register_opened" to "Cash register opened",
        "daily_totals" to "Daily totals",
        "employee_clock" to "Employee clock",
        "new_employees" to "New employees",
        "employee_loans" to "Employee loans",
        "employee_dayoffs" to "Employee day-offs",
        "salary_paid" to "Salary paid",
        "new_customers" to "New customers",
        "credit_payments" to "Credit payments",
        "held_bills" to "Held bills",
        "general" to "PosEx",
    )

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val mgr = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val existing = mgr.getNotificationChannel(CHANNEL_ID)
        if (existing != null) return
        mgr.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "PosEx notifications",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Sales, refunds, register and employee alerts"
            },
        )
    }

    fun notificationIdFor(groupKey: String): Int = groupKey.hashCode() and 0x7fffffff

    fun show(context: Context, title: String, body: String, notificationType: String) {
        val groupKey = notificationType.trim().ifEmpty { "general" }
        val cleaned = body.trim()
        if (cleaned.isEmpty()) return

        ensureChannel(context)
        val lines = appendLine(context, groupKey, cleaned)
        if (lines.isEmpty()) return

        val newestFirst = lines.asReversed()
        val latest = newestFirst.first()
        val label = labels[groupKey] ?: title.ifBlank { "PosEx" }
        val count = newestFirst.size
        val showTitle = if (count > 1) "$label ($count)" else title.ifBlank { label }
        val summary = if (count > 1) "Latest: $latest" else latest

        val openIntent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_OPEN
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_GROUP_KEY, groupKey)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        val contentPi = PendingIntent.getActivity(
            context,
            notificationIdFor(groupKey),
            openIntent,
            flags,
        )

        val inbox = NotificationCompat.InboxStyle()
            .setBigContentTitle(showTitle)
            .setSummaryText(summary)
        newestFirst.forEach { inbox.addLine(it) }

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(showTitle)
            .setContentText(latest)
            .setStyle(inbox)
            .setColor(Color.parseColor("#0F6B52"))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setAutoCancel(true)
            .setContentIntent(contentPi)
            .setGroup("posex_$groupKey")
            .setOnlyAlertOnce(false)

        appIconBitmap(context)?.let { builder.setLargeIcon(it) }

        NotificationManagerCompat.from(context)
            .notify(notificationIdFor(groupKey), builder.build())
    }

    private fun appIconBitmap(context: Context): Bitmap? {
        return try {
            val drawable = context.packageManager.getApplicationIcon(context.applicationInfo)
            val w = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else 192
            val h = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 192
            val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bmp)
            drawable.setBounds(0, 0, canvas.width, canvas.height)
            drawable.draw(canvas)
            bmp
        } catch (_: Exception) {
            null
        }
    }

    fun clearGroup(context: Context, groupKey: String?) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val nm = NotificationManagerCompat.from(context)
        if (!groupKey.isNullOrBlank()) {
            val key = groupKey.trim()
            prefs.edit().remove(KEY_PREFIX + key).apply()
            nm.cancel(notificationIdFor(key))
            return
        }
        val editor = prefs.edit()
        prefs.all.keys.filter { it.startsWith(KEY_PREFIX) }.forEach { stored ->
            val gk = stored.removePrefix(KEY_PREFIX)
            editor.remove(stored)
            nm.cancel(notificationIdFor(gk))
        }
        editor.apply()
    }

    private fun appendLine(context: Context, groupKey: String, line: String): List<String> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val key = KEY_PREFIX + groupKey
        val existing = readLines(prefs.getString(key, null))
        if (existing.isNotEmpty() && existing.last() == line) {
            return existing
        }
        existing.add(line)
        val trimmed = if (existing.size > MAX_LINES) {
            existing.subList(existing.size - MAX_LINES, existing.size).toMutableList()
        } else {
            existing
        }
        prefs.edit().putString(key, JSONArray(trimmed).toString()).apply()
        return trimmed
    }

    private fun readLines(raw: String?): MutableList<String> {
        if (raw.isNullOrBlank()) return mutableListOf()
        return try {
            val arr = JSONArray(raw)
            MutableList(arr.length()) { i -> arr.getString(i) }
        } catch (_: Exception) {
            mutableListOf()
        }
    }
}
