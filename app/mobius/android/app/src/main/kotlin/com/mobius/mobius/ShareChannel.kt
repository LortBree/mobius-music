package com.mobius.mobius

import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class ShareChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "mobius/share"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "shareImage" -> {
                val bytes = call.argument<ByteArray>("bytes")
                val title = call.argument<String>("title") ?: "Share Music"
                if (bytes == null || bytes.isEmpty()) {
                    result.error("INVALID_ARGUMENT", "Bytes must not be empty", null)
                    return
                }

                try {
                    val cacheDir = File(activity.cacheDir, "shared")
                    if (!cacheDir.exists()) cacheDir.mkdirs()
                    val file = File(cacheDir, "mobius_card_${System.currentTimeMillis()}.png")
                    FileOutputStream(file).use { it.write(bytes) }

                    val uri: Uri = FileProvider.getUriForFile(
                        activity,
                        "${activity.packageName}.fileprovider",
                        file
                    )

                    val shareIntent = Intent(Intent.ACTION_SEND).apply {
                        type = "image/png"
                        putExtra(Intent.EXTRA_STREAM, uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }

                    activity.startActivity(Intent.createChooser(shareIntent, title))
                    result.success(true)
                } catch (e: Exception) {
                    result.error("SHARE_ERROR", e.localizedMessage, null)
                }
            }
            "saveImage" -> {
                val bytes = call.argument<ByteArray>("bytes")
                val fileName = call.argument<String>("fileName") ?: "mobius_music_card_${System.currentTimeMillis()}.png"
                if (bytes == null || bytes.isEmpty()) {
                    result.error("INVALID_ARGUMENT", "Bytes must not be empty", null)
                    return
                }

                try {
                    val resolver = activity.contentResolver
                    val contentValues = ContentValues().apply {
                        put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                        put(MediaStore.MediaColumns.MIME_TYPE, "image/png")
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/Mobius")
                            put(MediaStore.MediaColumns.IS_PENDING, 1)
                        }
                    }

                    val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, contentValues)
                    if (uri != null) {
                        resolver.openOutputStream(uri)?.use { it.write(bytes) }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            contentValues.clear()
                            contentValues.put(MediaStore.MediaColumns.IS_PENDING, 0)
                            resolver.update(uri, contentValues, null, null)
                        }
                        result.success(true)
                    } else {
                        result.error("SAVE_FAILED", "Failed to create MediaStore entry", null)
                    }
                } catch (e: Exception) {
                    result.error("SAVE_ERROR", e.localizedMessage, null)
                }
            }
            else -> result.notImplemented()
        }
    }
}
