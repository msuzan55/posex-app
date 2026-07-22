package lk.posex.posex_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import android.util.Base64
import android.widget.Toast
import androidx.core.app.NotificationCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    companion object {
        private const val PRINT_CHANNEL = "lk.posex.posex_app/print_service"
        private const val INSTALL_CHANNEL = "lk.posex.posex_app/apk_install"
        private const val FILE_CHANNEL = "lk.posex.posex_app/file_actions"

        private const val DOWNLOAD_CHANNEL_ID = "posex_downloads"
        private const val DOWNLOAD_NOTIFICATION_BASE = 9200

        private const val PKG_WHATSAPP = "com.whatsapp"
        private const val PKG_WHATSAPP_BUSINESS = "com.whatsapp.w4b"
    }

    private var downloadNotifySeq = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ensureDownloadNotificationChannel()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PRINT_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startForeground" -> {
                        try {
                            val count = call.argument<Int>("connectedCount") ?: 0
                            if (count <= 0) {
                                stopService(Intent(this, PrintForegroundService::class.java))
                                result.success(false)
                            } else {
                                startPrintForegroundService(count)
                                result.success(true)
                            }
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "stopForeground" -> {
                        stopService(Intent(this, PrintForegroundService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INSTALL_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canRequestPackageInstalls" -> {
                        result.success(canRequestPackageInstalls())
                    }
                    "openInstallPermissionSettings" -> {
                        openInstallPermissionSettings()
                        result.success(null)
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("INVALID_PATH", "APK path is missing", null)
                            return@setMethodCallHandler
                        }
                        try {
                            installApk(path)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INSTALL_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "shareFile" -> {
                        try {
                            val base64 = call.argument<String>("base64") ?: ""
                            val fileName = sanitizeFileName(
                                call.argument<String>("fileName") ?: "share.bin",
                            )
                            val mimeType = call.argument<String>("mimeType")
                                ?: "application/octet-stream"
                            val title = call.argument<String>("title") ?: ""
                            val text = call.argument<String>("text") ?: ""
                            val target = call.argument<String>("target") ?: ""
                            shareFile(base64, fileName, mimeType, title, text, target)
                            result.success(mapOf("ok" to true))
                        } catch (e: Exception) {
                            result.error("SHARE_FAILED", e.message, null)
                        }
                    }
                    "saveFile" -> {
                        try {
                            val base64 = call.argument<String>("base64")
                            if (base64.isNullOrBlank()) {
                                result.error("INVALID_DATA", "File data is missing", null)
                                return@setMethodCallHandler
                            }
                            val fileName = sanitizeFileName(
                                call.argument<String>("fileName") ?: "download.bin",
                            )
                            val mimeType = call.argument<String>("mimeType")
                                ?: "application/octet-stream"
                            val saved = saveFileToDownloads(base64, fileName, mimeType)
                            showDownloadCompleteNotification(
                                saved.displayName,
                                saved.uri,
                                saved.mimeType,
                            )
                            result.success(
                                mapOf(
                                    "ok" to true,
                                    "fileName" to saved.displayName,
                                    "uri" to saved.uri.toString(),
                                ),
                            )
                        } catch (e: Exception) {
                            result.error("SAVE_FAILED", e.message, null)
                        }
                    }
                    "openWhatsApp" -> {
                        try {
                            val phone = call.argument<String>("phone") ?: ""
                            val text = call.argument<String>("text") ?: ""
                            val variant = call.argument<String>("variant") ?: "whatsapp"
                            openWhatsApp(phone, text, variant)
                            result.success(mapOf("ok" to true))
                        } catch (e: Exception) {
                            result.error("WHATSAPP_FAILED", e.message, null)
                        }
                    }
                    "openExternalUrl" -> {
                        try {
                            val url = call.argument<String>("url") ?: ""
                            if (url.isBlank()) {
                                result.error("INVALID_URL", "URL is missing", null)
                                return@setMethodCallHandler
                            }
                            openExternalUrl(url)
                            result.success(mapOf("ok" to true))
                        } catch (e: Exception) {
                            result.error("OPEN_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun canRequestPackageInstalls(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }
    }

    private fun openInstallPermissionSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val intent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName"),
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        }
    }

    private fun installApk(path: String) {
        val file = File(path)
        if (!file.exists() || file.length() < 4096) {
            throw IllegalStateException("Update file not found or incomplete")
        }

        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            file,
        )

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        val handlers = packageManager.queryIntentActivities(
            intent,
            PackageManager.MATCH_DEFAULT_ONLY,
        )
        if (handlers.isEmpty()) {
            throw IllegalStateException("No app can install APK on this device")
        }
        for (resolveInfo in handlers) {
            grantUriPermission(
                resolveInfo.activityInfo.packageName,
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        }

        startActivity(intent)
    }

    private fun resolveWhatsAppPackage(targetOrVariant: String): String? {
        val t = targetOrVariant.trim().lowercase()
        return when {
            t == "whatsapp_business" || t == "w4b" || t == PKG_WHATSAPP_BUSINESS ->
                PKG_WHATSAPP_BUSINESS
            t == "whatsapp" || t == "wa" || t == PKG_WHATSAPP ->
                PKG_WHATSAPP
            t.isBlank() -> null
            else -> targetOrVariant.trim()
        }
    }

    private fun isPackageInstalled(pkg: String): Boolean {
        return try {
            packageManager.getPackageInfo(pkg, 0)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun shareFile(
        base64: String,
        fileName: String,
        mimeType: String,
        title: String,
        text: String,
        target: String,
    ) {
        val intent = Intent(Intent.ACTION_SEND)
        var shareUri: Uri? = null

        if (base64.isNotBlank()) {
            val bytes = decodeBase64(base64)
            if (bytes.isEmpty()) {
                throw IllegalStateException("Empty file data")
            }
            val dir = File(cacheDir, "share").apply { mkdirs() }
            val file = File(dir, fileName)
            FileOutputStream(file).use { it.write(bytes) }

            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                file,
            )
            shareUri = uri
            intent.type = mimeType.ifBlank { "application/octet-stream" }
            intent.putExtra(Intent.EXTRA_STREAM, uri)
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            intent.clipData = android.content.ClipData.newUri(contentResolver, fileName, uri)
        } else {
            intent.type = "text/plain"
        }

        if (title.isNotBlank()) {
            intent.putExtra(Intent.EXTRA_SUBJECT, title)
        }
        if (text.isNotBlank()) {
            intent.putExtra(Intent.EXTRA_TEXT, text)
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

        val preferredPkg = resolveWhatsAppPackage(target)
        if (!preferredPkg.isNullOrBlank() && isPackageInstalled(preferredPkg)) {
            shareUri?.let {
                grantUriPermission(
                    preferredPkg,
                    it,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            }
            intent.setPackage(preferredPkg)
            try {
                startActivity(intent)
                return
            } catch (_: ActivityNotFoundException) {
                intent.setPackage(null)
            }
        }

        // Prefer WhatsApp in chooser when no explicit target (bill share).
        if (preferredPkg.isNullOrBlank()) {
            for (pkg in listOf(PKG_WHATSAPP, PKG_WHATSAPP_BUSINESS)) {
                if (!isPackageInstalled(pkg)) continue
                shareUri?.let {
                    grantUriPermission(pkg, it, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            }
        } else {
            val handlers = packageManager.queryIntentActivities(
                intent,
                PackageManager.MATCH_DEFAULT_ONLY,
            )
            for (resolveInfo in handlers) {
                shareUri?.let {
                    grantUriPermission(
                        resolveInfo.activityInfo.packageName,
                        it,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION,
                    )
                }
            }
        }

        val chooser = Intent.createChooser(
            intent,
            if (title.isNotBlank()) title else "Share",
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(chooser)
    }

    private fun openWhatsApp(phone: String, text: String, variant: String) {
        val digits = phone.replace(Regex("\\D"), "")
        val preferred = resolveWhatsAppPackage(variant) ?: PKG_WHATSAPP
        val fallbackPkg = if (preferred == PKG_WHATSAPP_BUSINESS) PKG_WHATSAPP else PKG_WHATSAPP_BUSINESS
        val packages = listOf(preferred, fallbackPkg).distinct().filter { isPackageInstalled(it) }

        val apiUri = if (digits.isNotBlank()) {
            Uri.parse(
                "https://api.whatsapp.com/send?phone=$digits&text=${Uri.encode(text)}",
            )
        } else {
            Uri.parse("https://api.whatsapp.com/send?text=${Uri.encode(text)}")
        }
        val schemeUri = if (digits.isNotBlank()) {
            Uri.parse("whatsapp://send?phone=$digits&text=${Uri.encode(text)}")
        } else {
            Uri.parse("whatsapp://send?text=${Uri.encode(text)}")
        }

        for (pkg in packages) {
            try {
                startActivity(
                    Intent(Intent.ACTION_VIEW, apiUri)
                        .setPackage(pkg)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                return
            } catch (_: Exception) {
                // try next
            }
            try {
                startActivity(
                    Intent(Intent.ACTION_VIEW, schemeUri)
                        .setPackage(pkg)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                return
            } catch (_: Exception) {
                // try next
            }
        }

        try {
            startActivity(
                Intent(Intent.ACTION_VIEW, schemeUri)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            return
        } catch (_: Exception) {
            // fall through
        }

        try {
            startActivity(
                Intent(Intent.ACTION_VIEW, apiUri)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            return
        } catch (_: Exception) {
            // fall through
        }

        throw IllegalStateException("WhatsApp is not installed on this device")
    }

    private fun openExternalUrl(url: String) {
        val trimmed = url.trim()
        if (trimmed.startsWith("intent:", ignoreCase = true)) {
            val intent = Intent.parseUri(trimmed, Intent.URI_INTENT_SCHEME)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                startActivity(intent)
                return
            } catch (_: ActivityNotFoundException) {
                val fallback = intent.getStringExtra("browser_fallback_url")
                if (!fallback.isNullOrBlank()) {
                    startActivity(
                        Intent(Intent.ACTION_VIEW, Uri.parse(fallback))
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                    return
                }
                throw IllegalStateException("No app can open this link")
            }
        }

        val lower = trimmed.lowercase()
        if (lower.startsWith("whatsapp:") ||
            lower.contains("api.whatsapp.com") ||
            lower.contains("wa.me") ||
            lower.contains("web.whatsapp.com")
        ) {
            val uri = Uri.parse(trimmed)
            val phone = uri.getQueryParameter("phone") ?: ""
            val text = uri.getQueryParameter("text") ?: ""
            openWhatsApp(phone, text, "whatsapp")
            return
        }

        startActivity(
            Intent(Intent.ACTION_VIEW, Uri.parse(trimmed))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }

    private data class SavedDownload(
        val displayName: String,
        val uri: Uri,
        val mimeType: String,
    )

    private fun saveFileToDownloads(
        base64: String,
        fileName: String,
        mimeType: String,
    ): SavedDownload {
        val bytes = decodeBase64(base64)
        if (bytes.isEmpty()) {
            throw IllegalStateException("Empty file data")
        }
        val safeMime = mimeType.ifBlank { "application/octet-stream" }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, safeMime)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val resolver = contentResolver
            val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            val uri = resolver.insert(collection, values)
                ?: throw IllegalStateException("Could not create download entry")
            resolver.openOutputStream(uri)?.use { out ->
                out.write(bytes)
            } ?: throw IllegalStateException("Could not write download")
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return SavedDownload(fileName, uri, safeMime)
        }

        @Suppress("DEPRECATION")
        val downloads = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOWNLOADS,
        )
        if (!downloads.exists() && !downloads.mkdirs()) {
            throw IllegalStateException("Downloads folder unavailable")
        }
        var target = File(downloads, fileName)
        if (target.exists()) {
            val stem = fileName.substringBeforeLast('.', fileName)
            val ext = if (fileName.contains('.')) ".${fileName.substringAfterLast('.')}" else ""
            var i = 1
            while (target.exists()) {
                target = File(downloads, "${stem}_$i$ext")
                i++
            }
        }
        FileOutputStream(target).use { it.write(bytes) }
        MediaScannerConnection.scanFile(
            this,
            arrayOf(target.absolutePath),
            arrayOf(safeMime),
            null,
        )
        val uri = try {
            FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                target,
            )
        } catch (_: Exception) {
            @Suppress("DEPRECATION")
            Uri.fromFile(target)
        }
        return SavedDownload(target.name, uri, safeMime)
    }

    private fun ensureDownloadNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val existing = manager.getNotificationChannel(DOWNLOAD_CHANNEL_ID)
        if (existing != null) return
        val channel = NotificationChannel(
            DOWNLOAD_CHANNEL_ID,
            "Downloads",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "PDF and file download completed"
        }
        manager.createNotificationChannel(channel)
    }

    private fun showDownloadCompleteNotification(
        fileName: String,
        uri: Uri,
        mimeType: String,
    ) {
        ensureDownloadNotificationChannel()

        val viewIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mimeType)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        // Grant read to potential viewers (PDF apps, Files, etc.).
        val handlers = packageManager.queryIntentActivities(
            viewIntent,
            PackageManager.MATCH_DEFAULT_ONLY,
        )
        for (resolveInfo in handlers) {
            grantUriPermission(
                resolveInfo.activityInfo.packageName,
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        }

        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        val contentIntent = PendingIntent.getActivity(
            this,
            downloadNotifySeq,
            viewIntent,
            flags,
        )

        val notification = NotificationCompat.Builder(this, DOWNLOAD_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("Download complete")
            .setContentText(fileName)
            .setStyle(
                NotificationCompat.BigTextStyle()
                    .bigText("$fileName saved to Downloads. Tap to open."),
            )
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .build()

        val manager = getSystemService(NotificationManager::class.java) ?: return
        val id = DOWNLOAD_NOTIFICATION_BASE + (downloadNotifySeq++ % 1000)
        manager.notify(id, notification)

        Toast.makeText(this, "Saved: $fileName", Toast.LENGTH_SHORT).show()
    }

    private fun decodeBase64(value: String): ByteArray {
        var raw = value.trim()
        val comma = raw.indexOf(',')
        if (raw.startsWith("data:", ignoreCase = true) && comma >= 0) {
            raw = raw.substring(comma + 1)
        }
        return Base64.decode(raw, Base64.DEFAULT)
    }

    private fun sanitizeFileName(name: String): String {
        val cleaned = name.trim()
            .replace(Regex("[\\\\/:*?\"<>|]"), "_")
            .replace(Regex("\\s+"), "_")
        return if (cleaned.isBlank()) "download.bin" else cleaned.take(120)
    }

    private fun startPrintForegroundService(connectedCount: Int) {
        val intent = Intent(this, PrintForegroundService::class.java).apply {
            putExtra(PrintForegroundService.EXTRA_CONNECTED_COUNT, connectedCount)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }
}
