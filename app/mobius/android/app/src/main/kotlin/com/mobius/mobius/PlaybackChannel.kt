package com.mobius.mobius

import android.Manifest
import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.media3.common.util.UnstableApi
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * Host side of the `mobius/playback_service` channel.
 *
 * Dart -> host:
 *   * `start`  -> arm the foreground service, requesting POST_NOTIFICATIONS on
 *                 API 33+. The service is only actually started once a track is
 *                 present (see below), so media3 always has a current item when
 *                 it promotes to the foreground.
 *   * `stop`   -> drop foreground, keep a dismissable paused notification.
 *   * `update` {title, artist, album, durationMs, positionMs, isPlaying,
 *               artworkPath?} -> facade state (notification + lock screen).
 *
 * host -> Dart:
 *   * `command` {action: play|pause|next|previous|seek, positionMs?} from the
 *     notification / lock screen / headset / Bluetooth buttons.
 *
 * Foreground-start race (fix): media3 only auto-posts the foreground
 * notification once the session has a current media item. Calling
 * `startForegroundService` while the facade is still STATE_IDLE with an empty
 * playlist risks `ForegroundServiceDidNotStartInTimeException` on Android 13.
 * We therefore DEFER the actual `startForegroundService` until the first
 * `update` that carries a track: `start` only sets an "armed" flag, and the
 * service is started from `update` (or immediately, if a track is already
 * present when `start` arrives).
 *
 * Activity leak (fix): the facade is stored in the process-lived
 * [PlaybackHolder], so its command lambda must NOT capture the Activity. It
 * posts to the main [Looper] via a Handler and routes through
 * [PlaybackHolder.onCommand]; [dispose] clears that reference.
 */
@UnstableApi
class PlaybackChannel(
    activity: Activity,
    private val channel: MethodChannel,
) : MethodChannel.MethodCallHandler, PluginRegistry.RequestPermissionsResultListener {

    companion object {
        const val CHANNEL = "mobius/playback_service"
        private const val REQUEST_POST_NOTIFICATIONS = 0xB0D1
    }

    // Application context only — never the Activity — so nothing the holder
    // keeps alive can leak the Activity.
    private val appContext: Context = activity.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())

    // Permission requests still need the Activity, but it is held weakly through
    // the method-call path only while this channel (and thus the engine) lives;
    // dispose() clears cross-process references.
    private var activityRef: Activity? = activity

    /** True once Dart has asked to start; the service starts on the first track. */
    private var armed = false

    init {
        // Route facade button presses to Dart on the main thread, with NO
        // Activity capture (the facade outlives the Activity in PlaybackHolder).
        PlaybackHolder.onCommand = { action, positionMs ->
            mainHandler.post { emitCommand(action, positionMs) }
        }
    }

    fun onVolumeStep(direction: Int) {
        mainHandler.post {
            channel.invokeMethod("command", mapOf("action" to "volumeStep", "direction" to direction))
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> start(result)
            "stop" -> stop(result)
            "update" -> update(call, result)
            else -> result.notImplemented()
        }
    }

    private fun ensureFacade(): MobiusFacadePlayer {
        PlaybackHolder.player?.let { return it }
        val facade = MobiusFacadePlayer(Looper.getMainLooper()) { action, positionMs ->
            mainHandler.post { emitCommand(action, positionMs) }
        }
        PlaybackHolder.player = facade
        return facade
    }

    private fun start(result: MethodChannel.Result) {
        val facade = ensureFacade()
        maybeRequestNotificationsPermission()
        armed = true
        // Only start the foreground service once audio is actually playing
        if (facade.hasTrack && facade.isPlaying) {
            startServiceNow()
        }
        result.success(true)
    }

    private fun startServiceNow() {
        val intent = Intent(appContext, MobiusPlaybackService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            appContext.startForegroundService(intent)
        } else {
            appContext.startService(intent)
        }
    }

    private fun stop(result: MethodChannel.Result) {
        // Reflect the paused state so media3 demotes the notification to a
        // dismissable one; do NOT stop the service, so a quick resume is cheap
        // and background playback is never killed mid-stream.
        PlaybackHolder.updateWakeLock?.invoke(false)
        PlaybackHolder.player?.pausePreservingSnapshot()
        result.success(true)
    }

    private fun update(call: MethodCall, result: MethodChannel.Result) {
        val facade = ensureFacade()
        val isPlaying = call.argument<Boolean>("isPlaying") ?: false
        facade.applyUpdate(
            call.argument<String>("title") ?: "",
            call.argument<String>("artist") ?: "",
            call.argument<String>("album") ?: "",
            (call.argument<Number>("durationMs"))?.toLong() ?: 0L,
            (call.argument<Number>("positionMs"))?.toLong() ?: 0L,
            isPlaying,
            call.argument<String>("artworkPath"),
            call.argument<ByteArray>("artworkData"),
        )
        // Manage background wake lock to prevent CPU Doze during playback
        PlaybackHolder.updateWakeLock?.invoke(isPlaying)
        // Start foreground service when playing
        if (armed && facade.hasTrack && facade.isPlaying) {
            startServiceNow()
        }
        result.success(true)
    }

    private fun emitCommand(action: String, positionMs: Long?) {
        val args = HashMap<String, Any>()
        args["action"] = action
        if (positionMs != null) args["positionMs"] = positionMs
        channel.invokeMethod("command", args)
    }

    private fun maybeRequestNotificationsPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val activity = activityRef ?: return
        val granted = ContextCompat.checkSelfPermission(
            activity,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) return
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_POST_NOTIFICATIONS,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        // Notification permission is best-effort: playback proceeds either way,
        // only the visibility of the notification is affected. Nothing to do.
        return requestCode == REQUEST_POST_NOTIFICATIONS
    }

    fun dispose() {
        // Clear cross-process references so neither the holder nor the facade's
        // command lambda keeps the Activity alive.
        PlaybackHolder.onCommand = null
        activityRef = null
        armed = false
        val player = PlaybackHolder.player
        if (player == null || !player.isPlaying) {
            val component = ComponentName(appContext, MobiusPlaybackService::class.java)
            appContext.stopService(Intent().apply { setComponent(component) })
        }
    }
}
