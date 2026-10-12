package com.mobius.mobius

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.os.Build
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService

/**
 * media3 [MediaSessionService] that owns the MediaSession notification and keeps
 * the process alive while music plays in the background. It carries NO audio —
 * audio is produced by the Rust engine. The session player is the
 * [MobiusFacadePlayer] created by [PlaybackChannel] and shared through
 * [PlaybackHolder].
 */
@UnstableApi
class MobiusPlaybackService : MediaSessionService() {

    companion object {
        const val CHANNEL_ID = "mobius_playback"
        const val NOTIFICATION_ID = 1001
    }

    private var mediaSession: MediaSession? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Mobius Playback",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }

        val player = PlaybackHolder.player ?: run {
            MobiusFacadePlayer(mainLooper) { action, positionMs ->
                PlaybackHolder.onCommand?.invoke(action, positionMs)
            }.also { PlaybackHolder.player = it }
        }

        val sessionIntent = packageManager
            .getLaunchIntentForPackage(packageName)
            ?.let { launch ->
                PendingIntent.getActivity(
                    this,
                    0,
                    launch,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                )
            }

        val session = MediaSession.Builder(this, player)
            .setCallback(MediaSessionCallback(packageName))
            .apply { sessionIntent?.let { setSessionActivity(it) } }
            .build()
        mediaSession = session
        PlaybackHolder.session = session
        addSession(session)

        val notificationProvider = androidx.media3.session.DefaultMediaNotificationProvider.Builder(this)
            .setChannelId(CHANNEL_ID)
            .build()
        notificationProvider.setSmallIcon(R.drawable.ic_mobius_notification)
        setMediaNotificationProvider(notificationProvider)

        registerReceiver(noisyReceiver, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY))

        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
        wakeLock = powerManager?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Mobius:PlaybackWakeLock")?.apply {
            setReferenceCounted(false)
        }
        PlaybackHolder.updateWakeLock = { isPlaying ->
            if (isPlaying) {
                if (wakeLock?.isHeld != true) {
                    wakeLock?.acquire(24 * 60 * 60 * 1000L)
                }
            } else {
                if (wakeLock?.isHeld == true) {
                    wakeLock?.release()
                }
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return super.onStartCommand(intent, flags, startId)
    }

    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY &&
                mediaSession?.player?.playWhenReady == true
            ) {
                PlaybackHolder.onCommand?.invoke("pause", null)
            }
        }
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? =
        mediaSession

    override fun onTaskRemoved(rootIntent: Intent?) {
        // When the user swipes the app away from recent tasks, stop playback completely,
        // dismiss notifications, stop the service, and terminate the process so
        // native Rust audio threads do not orphan.
        PlaybackHolder.updateWakeLock = null
        if (wakeLock?.isHeld == true) {
            wakeLock?.release()
        }
        runCatching { unregisterReceiver(noisyReceiver) }
        mediaSession?.run {
            removeSession(this)
            player.release()
            release()
        }
        mediaSession = null
        PlaybackHolder.session = null
        PlaybackHolder.player = null
        stopSelf()
        super.onTaskRemoved(rootIntent)
        android.os.Process.killProcess(android.os.Process.myPid())
    }

    override fun onDestroy() {
        PlaybackHolder.updateWakeLock = null
        if (wakeLock?.isHeld == true) {
            wakeLock?.release()
        }
        runCatching { unregisterReceiver(noisyReceiver) }
        mediaSession?.run {
            removeSession(this)
            player.release()
            release()
        }
        mediaSession = null
        PlaybackHolder.session = null
        PlaybackHolder.player = null
        super.onDestroy()
    }
}
