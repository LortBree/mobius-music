package com.mobius.mobius

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import androidx.annotation.RequiresApi
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * Host side of the `mobius/android_storage` channel.
 *
 * Contract (see docs/handoffs/android-build-contracts.md, Section A):
 *   * `ensureAudioPermission` -> Boolean  runtime READ_MEDIA_AUDIO (API 33+) /
 *                                READ_EXTERNAL_STORAGE below, resolved with the
 *                                grant result.
 *   * `pickFolder`            -> String?  ACTION_OPEN_DOCUMENT_TREE, tree id
 *                                mapped to a real path, null if cancelled or
 *                                unmappable.
 *   * `appDataDirectory`      -> String   `context.filesDir.absolutePath`.
 *
 * One async request (permission or folder pick) is in flight at a time; a
 * second call while one is pending is rejected with a `pending` error rather
 * than silently dropping the first result.
 */
class StorageChannel(private val activity: Activity) :
    MethodChannel.MethodCallHandler,
    PluginRegistry.RequestPermissionsResultListener,
    PluginRegistry.ActivityResultListener {

    companion object {
        const val CHANNEL = "mobius/android_storage"
        private const val REQUEST_AUDIO_PERMISSION = 0xA0D1
        private const val REQUEST_OPEN_DOCUMENT_TREE = 0xA0D2

        // Removable-volume ids are either the short FAT serial `XXXX-XXXX`
        // (hex) or a full lowercase UUID. Anything else is rejected.
        private val VOLUME_ID = Regex(
            "^[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}$|" +
                "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-" +
                "[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$",
        )

        private fun audioPermission(): String =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                Manifest.permission.READ_MEDIA_AUDIO
            } else {
                Manifest.permission.READ_EXTERNAL_STORAGE
            }
    }

    private var permissionResult: MethodChannel.Result? = null
    private var pickResult: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "ensureAudioPermission" -> ensureAudioPermission(result)
            "pickFolder" -> pickFolder(result)
            "appDataDirectory" -> result.success(activity.filesDir.absolutePath)
            else -> result.notImplemented()
        }
    }

    private fun ensureAudioPermission(result: MethodChannel.Result) {
        val permission = audioPermission()
        val granted = ContextCompat.checkSelfPermission(activity, permission) ==
            PackageManager.PERMISSION_GRANTED
        if (granted) {
            result.success(true)
            return
        }
        if (permissionResult != null) {
            result.error("pending", "A permission request is already in flight.", null)
            return
        }
        permissionResult = result
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(permission),
            REQUEST_AUDIO_PERMISSION,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST_AUDIO_PERMISSION) return false
        val pending = permissionResult ?: return true
        permissionResult = null
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pending.success(granted)
        return true
    }

    private fun pickFolder(result: MethodChannel.Result) {
        if (pickResult != null) {
            result.error("pending", "A folder pick is already in flight.", null)
            return
        }
        pickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
        }
        try {
            activity.startActivityForResult(intent, REQUEST_OPEN_DOCUMENT_TREE)
        } catch (e: android.content.ActivityNotFoundException) {
            pickResult = null
            result.error("unavailable", "No document tree picker available.", e.message)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_OPEN_DOCUMENT_TREE) return false
        val pending = pickResult ?: return true
        pickResult = null

        val treeUri = data?.data
        if (resultCode != Activity.RESULT_OK || treeUri == null) {
            pending.success(null) // cancelled
            return true
        }

        // Persist the read grant so the folder is still reachable next launch.
        try {
            activity.contentResolver.takePersistableUriPermission(
                treeUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        } catch (_: SecurityException) {
            // Not fatal: the scan this launch still works with the granted uri.
        }

        pending.success(mapTreeUriToPath(treeUri))
        return true
    }

    /**
     * Maps a Storage Access Framework tree Uri to a real filesystem path the
     * Rust scanner can read:
     *   `primary:Music/Rock`  -> `/storage/emulated/0/Music/Rock`
     *   `<UUID>:path`         -> `/storage/<UUID>/path`
     *
     * Hardened against traversal: `relative` is rejected if it is absolute or
     * contains a `..` segment, `volume` is accepted only when it is `primary`
     * or a removable-volume UUID (`XXXX-XXXX` hex) or a full UUID, and the final
     * path is canonicalized and required to stay under `/storage/`. Returns null
     * for anything that fails these checks or a tree id that cannot be mapped
     * (e.g. a cloud-provider document tree).
     */
    @RequiresApi(Build.VERSION_CODES.LOLLIPOP)
    private fun mapTreeUriToPath(treeUri: Uri): String? {
        val docId = try {
            DocumentsContract.getTreeDocumentId(treeUri)
        } catch (_: IllegalArgumentException) {
            return null
        }
        val parts = docId.split(':', limit = 2)
        if (parts.isEmpty()) return null
        val volume = parts[0]
        val relative = if (parts.size > 1) parts[1] else ""

        // Reject path traversal: no absolute path, no `..` segment, no NUL.
        if (relative.startsWith('/') || relative.contains('\u0000')) return null
        if (relative.split('/').any { it == ".." }) return null

        // Accept only the primary volume or a UUID-shaped removable volume id.
        val isPrimary = volume.equals("primary", ignoreCase = true)
        if (!isPrimary && !VOLUME_ID.matches(volume)) return null

        val base = if (isPrimary) "/storage/emulated/0" else "/storage/$volume"
        val candidate = if (relative.isEmpty()) base else "$base/$relative"

        // Canonicalize and require the result to stay under /storage/.
        val canonical = try {
            java.io.File(candidate).canonicalPath
        } catch (_: java.io.IOException) {
            return null
        }
        if (canonical != "/storage" && !canonical.startsWith("/storage/")) return null
        return canonical
    }
}
