package com.example.travibe

import android.content.Intent
import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import java.io.File

import android.content.pm.ApplicationInfo
import android.util.Log
import android.net.Uri
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingShare: MethodChannel.Result? = null
    private val shareRequest = 7401

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "travibe/chat_media")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "networkStatus" -> {
                        val connectivity = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
                        val network = connectivity.activeNetwork
                        val capabilities = network?.let { connectivity.getNetworkCapabilities(it) }
                        result.success(if (network == null) false else capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET))
                    }
                    "microphoneStatus" -> result.success(microphoneStatus())
                    "requestMicrophone" -> {
                        val status = microphoneStatus()
                        if (status == "granted" || status == "permanentlyDenied" || status == "restricted") result.success(status)
                        else if (pendingPermission != null) result.error("busy", "Permission request already open.", null)
                        else {
                            pendingPermission = result
                            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 7402)
                        }
                    }
                    "openSettings" -> {
                        try { startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))); result.success(null) }
                        catch (_: Exception) { result.error("unavailable", "Settings unavailable.", null) }
                    }
                    "saveVideo" -> {
                        val path = call.argument<String>("path")
                        val mime = call.argument<String>("mime")
                        if (path == null || mime == null) result.error("invalid_video", "Unable to save video.", null)
                        else if (Build.VERSION.SDK_INT <= 28 && checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
                            if (pendingPermission != null) result.error("busy", "Permission request already open.", null)
                            else { pendingPermission = result; pendingVideo = Pair(path, mime); requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 7403) }
                        } else saveChatVideo(path, mime, result)
                    }
                    "saveImage" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        if (bytes == null || bytes.isEmpty() || bytes.size > 20 * 1024 * 1024) result.error("invalid_image", "Unable to save image.", null)
                        else if (Build.VERSION.SDK_INT <= 28 && checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
                            if (pendingPermission != null) result.error("busy", "Permission request already open.", null)
                            else { pendingPermission = result; pendingImage = bytes; requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 7403) }
                        } else saveChatImage(bytes, result)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "travibe/post_sharing")
            .setMethodCallHandler { call, result ->
                if (call.method != "share") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingShare != null) {
                    result.error("busy", "Sharing options are already open.", null)
                    return@setMethodCallHandler
                }
                val url = call.argument<String>("url")
                val text = call.argument<String>("text")?.trim()
                val uri = url?.let(Uri::parse)
                if (url != null && (uri == null || uri.scheme != "https" || uri.host.isNullOrEmpty() || !uri.userInfo.isNullOrEmpty())) {
                    result.error("invalid_url", "A verified public post link is required.", null)
                    return@setMethodCallHandler
                }
                val content = url ?: text
                if (content.isNullOrBlank()) {
                    result.error("empty_content", "No post text or link is available.", null)
                    return@setMethodCallHandler
                }
                if (isFinishing || isDestroyed) {
                    result.error("unavailable", "Unable to open sharing options.", "Activity is not attached")
                    return@setMethodCallHandler
                }
                try {
                    val send = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, content)
                        putExtra(Intent.EXTRA_SUBJECT, "Travibe post")
                    }
                    pendingShare = result
                    // Completion only means returning from the chooser, not delivery.
                    @Suppress("DEPRECATION")
                    startActivityForResult(Intent.createChooser(send, "Send Post"), shareRequest)
                } catch (error: Exception) {
                    pendingShare = null
                    if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
                        Log.e("TravibePostSharing", "Unable to launch ACTION_SEND chooser", error)
                    }
                    result.error("unavailable", "Unable to open sharing options.",
                        mapOf("type" to error.javaClass.name, "message" to error.message))
                }
            }
    }

    private var pendingPermission: MethodChannel.Result? = null
    private var pendingImage: ByteArray? = null
    private var pendingVideo: Pair<String, String>? = null
    private fun microphoneStatus(): String {
        try {
            val flags = packageManager.getPermissionFlags(Manifest.permission.RECORD_AUDIO, packageName, android.os.Process.myUserHandle())
            if (flags and (PackageManager.FLAG_PERMISSION_POLICY_FIXED or PackageManager.FLAG_PERMISSION_SYSTEM_FIXED) != 0 && checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) return "restricted"
        } catch (_: Exception) {}
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) return "granted"
        val asked = getPreferences(0).getBoolean("chat_microphone_asked", false)
        return if (!asked) "notDetermined" else if (shouldShowRequestPermissionRationale(Manifest.permission.RECORD_AUDIO)) "denied" else "permanentlyDenied"
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != 7402 && requestCode != 7403) return
        val result = pendingPermission ?: return
        pendingPermission = null
        if (requestCode == 7402) {
            getPreferences(0).edit().putBoolean("chat_microphone_asked", true).apply()
            result.success(microphoneStatus())
        } else {
            val bytes = pendingImage; pendingImage = null
            val video = pendingVideo; pendingVideo = null
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED && video != null) saveChatVideo(video.first, video.second, result)
            else if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED && bytes != null) saveChatImage(bytes, result)
            else result.error("permission_denied", "Allow saving photos in Settings.", null)
        }
    }
    private fun saveChatVideo(path: String, mime: String, result: MethodChannel.Result) {
        Thread {
            var uri: Uri? = null
            var legacy: File? = null
            try {
                val source = File(path).canonicalFile
                if (!source.path.startsWith(cacheDir.canonicalPath + File.separator) || !source.isFile || source.length() <= 0 || source.length() > 100L * 1024 * 1024) throw IllegalArgumentException()
                val extension = when (mime) { "video/mp4" -> "mp4"; "video/quicktime" -> "mov"; "video/webm" -> "webm"; else -> throw IllegalArgumentException() }
                val retriever = MediaMetadataRetriever()
                try {
                    retriever.setDataSource(source.path)
                    if ((retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0) <= 0) throw IllegalArgumentException()
                } finally { retriever.release() }
                val name = "Travibe-${java.util.UUID.randomUUID()}.$extension"
                val values = ContentValues().apply { put(MediaStore.Video.Media.DISPLAY_NAME, name); put(MediaStore.Video.Media.MIME_TYPE, mime) }
                if (Build.VERSION.SDK_INT >= 29) {
                    values.put(MediaStore.Video.Media.RELATIVE_PATH, Environment.DIRECTORY_MOVIES + "/Travibe")
                    values.put(MediaStore.Video.Media.IS_PENDING, 1)
                } else {
                    val directory = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES), "Travibe")
                    if (!directory.exists() && !directory.mkdirs()) throw java.io.IOException()
                    legacy = File(directory, name)
                    values.put(MediaStore.Video.Media.DATA, legacy!!.absolutePath)
                }
                uri = contentResolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values) ?: throw java.io.IOException()
                contentResolver.openOutputStream(uri!!)?.use { output -> source.inputStream().use { it.copyTo(output) } } ?: throw java.io.IOException()
                if (Build.VERSION.SDK_INT >= 29 && contentResolver.update(uri!!, ContentValues().apply { put(MediaStore.Video.Media.IS_PENDING, 0) }, null, null) <= 0) throw java.io.IOException()
                runOnUiThread { result.success(null) }
            } catch (_: Exception) {
                try { uri?.let { contentResolver.delete(it, null, null) }; legacy?.delete() } catch (_: Exception) {}
                runOnUiThread { result.error("save_failed", "Unable to save video. Check available storage and try again.", null) }
            }
        }.start()
    }

    private fun saveChatImage(bytes: ByteArray, result: MethodChannel.Result) {
        Thread {
            var uri: Uri? = null
            var legacy: File? = null
            try {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                if (bounds.outWidth <= 0 || bounds.outHeight <= 0) throw IllegalArgumentException()
                val mime = bounds.outMimeType ?: throw IllegalArgumentException()
                val extension = when (mime) { "image/jpeg" -> "jpg"; "image/png" -> "png"; "image/webp" -> "webp"; "image/gif" -> "gif"; else -> throw IllegalArgumentException() }
                val name = "Travibe-${java.util.UUID.randomUUID()}.$extension"
                val values = ContentValues().apply { put(MediaStore.Images.Media.DISPLAY_NAME, name); put(MediaStore.Images.Media.MIME_TYPE, mime) }
                if (Build.VERSION.SDK_INT >= 29) {
                    values.put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/Travibe")
                    values.put(MediaStore.Images.Media.IS_PENDING, 1)
                } else {
                    val directory = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "Travibe")
                    if (!directory.exists() && !directory.mkdirs()) throw java.io.IOException()
                    legacy = File(directory, name)
                    values.put(MediaStore.Images.Media.DATA, legacy!!.absolutePath)
                }
                uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: throw java.io.IOException()
                contentResolver.openOutputStream(uri!!)?.use { it.write(bytes) } ?: throw java.io.IOException()
                if (Build.VERSION.SDK_INT >= 29 && contentResolver.update(uri!!, ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }, null, null) <= 0) throw java.io.IOException()
                runOnUiThread { result.success(null) }
            } catch (_: Exception) {
                try { uri?.let { contentResolver.delete(it, null, null) }; legacy?.delete() } catch (_: Exception) {}
                runOnUiThread { result.error("save_failed", "Unable to save image. Check available storage and try again.", null) }
            }
        }.start()
    }

    @Deprecated("Required for the FlutterActivity chooser result callback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == shareRequest) {
            pendingShare?.success(null)
            pendingShare = null
        }
    }

    override fun onDestroy() {
        pendingShare?.error("interrupted", "Sharing was interrupted.", null)
        pendingShare = null
        pendingPermission?.error("interrupted", "Permission request interrupted.", null)
        pendingPermission = null
        pendingImage = null
        pendingVideo = null
        super.onDestroy()
    }
}
