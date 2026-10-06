package com.mobius.mobius

import androidx.media3.common.util.UnstableApi
import androidx.media3.session.MediaSession

/**
 * Process-wide handle to the single active playback facade/session.
 *
 * The [MobiusPlaybackService] (created by the OS) and the [PlaybackChannel]
 * (created with the Flutter engine) both need to reach the same
 * [MobiusFacadePlayer]: the channel pushes `update`s and reads commands, the
 * service hosts the [MediaSession] that renders the notification. They are
 * created on the same application main thread, so a plain nullable field with
 * no locking is sufficient; all access is from that thread.
 */
@UnstableApi
object PlaybackHolder {
    /** Set by the channel on first `start`, cleared on service destroy. */
    @Volatile
    var player: MobiusFacadePlayer? = null

    /** Set by the service in onCreate, used by onGetSession. */
    @Volatile
    var session: MediaSession? = null

    /**
     * Routes a transport-control button from the facade back to Dart. Set by the
     * channel while the engine is wired; null once disposed, in which case the
     * button is a no-op (the Rust engine is the source of truth either way).
     */
    @Volatile
    var onCommand: ((action: String, positionMs: Long?) -> Unit)? = null
}
