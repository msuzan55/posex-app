package lk.posex.posex_app

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
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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
                            shareFile(base64, fileName, mimeType, title, text)
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
                            val savedName = saveFileToDownloads(base64, fileName, mimeType)
                            Toast.makeText(
                                this,
                                "Saved to Downloads: $savedName",
                                Toast.LENGTH_LONG,
                            ).show()
                            result.success(
                                mapOf(
                                    "ok" to true,
                                    "fileName" to savedName,
                                ),
                            )
                        } catch (e: Exception) {
                            result.error("SAVE_FAILED", e.message, null)
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

        // Grant read permission to every app that can handle the install intent
        // (required on Samsung/Xiaomi and Android 11+ package visibility).
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

    private fun shareFile(
        base64: String,
        fileName: String,
        mimeType: String,
        title: String,
        text: String,
    ) {
        val intent = Intent(Intent.ACTION_SEND)
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
            intent.type = mimeType.ifBlank { "application/octet-stream" }
            intent.putExtra(Intent.EXTRA_STREAM, uri)
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            intent.clipData = android.content.ClipData.newUri(contentResolver, fileName, uri)

            val handlers = packageManager.queryIntentActivities(
                intent,
                PackageManager.MATCH_DEFAULT_ONLY,
            )
            for (resolveInfo in handlers) {
                grantUriPermission(
                    resolveInfo.activityInfo.packageName,
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            }
        } else {
            intent.type = "text/plain"
        }

        if (title.isNotBlank()) {
            intent.putExtra(Intent.EXTRA_SUBJECT, title)
        }
        if (text.isNotBlank()) {
            intent.putExtra(Intent.EXTRA_TEXT, text)
        }

        val chooser = Intent.createChooser(
            intent,
            if (title.isNotBlank()) title else "Share",
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(chooser)
    }

    private fun saveFileToDownloads(
        base64: String,
        fileName: String,
        mimeType: String,
    ): String {
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
            return fileName
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
        return target.name
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
