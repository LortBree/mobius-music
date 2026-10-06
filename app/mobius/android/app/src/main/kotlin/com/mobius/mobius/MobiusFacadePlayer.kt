package com.mobius.mobius

import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.common.SimpleBasePlayer
import androidx.media3.common.util.UnstableApi
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.Futures

/**
 * A media3 [SimpleBasePlayer] whose observable state is driven entirely by the
 * Flutter side (the real audio engine is Rust). It never produces audio; it
 * only mirrors "what is playing" into the MediaSession so the notification and
 * lock screen are correct, and forwards transport-control button presses back
 * out through [commands].
 *
 * Standard playback only: a single-item playlist describing the current track,
 * with duration/position/isPlaying pushed from Dart via [applyUpdate].
 */
@UnstableApi
class MobiusFacadePlayer(
    looper: Looper,
    /** Invoked on the application thread for every notification/lock-screen button. */
    private val onCommand: (action: String, positionMs: Long?) -> Unit,
) : SimpleBasePlayer(looper) {

    // --- State pushed from Dart -------------------------------------------------
    private var title: String = ""
    private var artist: String = ""
    private var album: String = ""
    private var durationMs: Long = C_TIME_UNSET
    private var positionMs: Long = 0L
    private var playing: Boolean = false
    private var artworkPath: String? = null
    private var artworkData: ByteArray? = null
    var hasTrack: Boolean = false
        private set

    companion object {
        // media3 uses C.TIME_UNSET (= Long.MIN_VALUE + 1) for unknown duration.
        private const val C_TIME_UNSET: Long = Long.MIN_VALUE + 1
        private const val MEDIA_ID = "mobius_current"
    }

    /** Push the current-track snapshot from the `update` channel call. */
    fun applyUpdate(
        title: String,
        artist: String,
        album: String,
        durationMs: Long,
        positionMs: Long,
        isPlaying: Boolean,
        artworkPath: String?,
        artworkData: ByteArray? = null,
    ) {
        this.title = title
        this.artist = artist
        this.album = album
        this.durationMs = if (durationMs > 0) durationMs else C_TIME_UNSET
        this.positionMs = if (positionMs >= 0) positionMs else 0L
        this.playing = isPlaying
        if (artworkPath != null) {
            this.artworkPath = artworkPath
        }
        if (artworkData != null) {
            this.artworkData = artworkData
        }
        this.hasTrack = title.isNotEmpty() || artist.isNotEmpty() || album.isNotEmpty()
        if (!this.hasTrack) {
            this.artworkData = null
            this.artworkPath = null
        }
        invalidateState()
    }

    /**
     * Reflect "paused" without discarding the current-track snapshot, so media3
     * demotes the notification to a dismissable paused one while title/artist/
     * artwork stay visible. Used by `stop` on the channel.
     */
    fun pausePreservingSnapshot() {
        if (!playing) return
        playing = false
        invalidateState()
    }

    override fun getState(): State {
        val availableCommands = Player.Commands.Builder()
            .addAll(
                Player.COMMAND_PLAY_PAUSE,
                Player.COMMAND_SEEK_TO_NEXT,
                Player.COMMAND_SEEK_TO_PREVIOUS,
                Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM,
                Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM,
                Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM,
                Player.COMMAND_SEEK_BACK,
                Player.COMMAND_SEEK_FORWARD,
                Player.COMMAND_GET_CURRENT_MEDIA_ITEM,
                Player.COMMAND_GET_METADATA,
                Player.COMMAND_GET_TIMELINE,
                Player.COMMAND_STOP,
            )
            .build()

        val builder = State.Builder()
            .setAvailableCommands(availableCommands)
            .setPlayWhenReady(playing, Player.PLAY_WHEN_READY_CHANGE_REASON_USER_REQUEST)
            .setPlaybackState(if (hasTrack) Player.STATE_READY else Player.STATE_IDLE)
            .setContentPositionMs(positionMs)

        if (hasTrack) {
            builder.setPlaylist(listOf(buildMediaItemData()))
            builder.setCurrentMediaItemIndex(0)
        }
        return builder.build()
    }

    private fun buildMediaItemData(): MediaItemData {
        val metadataBuilder = MediaMetadata.Builder()
            .setTitle(title.ifEmpty { null })
            .setArtist(artist.ifEmpty { null })
            .setAlbumTitle(album.ifEmpty { null })
        artworkPath?.let { path ->
            if (path.isNotEmpty()) {
                metadataBuilder.setArtworkUri(android.net.Uri.fromFile(java.io.File(path)))
            }
        }
        artworkData?.let { bytes ->
            if (bytes.isNotEmpty()) {
                metadataBuilder.setArtworkData(bytes, MediaMetadata.PICTURE_TYPE_FRONT_COVER)
            }
        }
        val metadata = metadataBuilder.build()
        val mediaItem = MediaItem.Builder()
            .setMediaId(MEDIA_ID)
            .setMediaMetadata(metadata)
            .build()
        return MediaItemData.Builder(MEDIA_ID)
            .setMediaItem(mediaItem)
            .setMediaMetadata(metadata)
            .setDurationUs(if (durationMs > 0) durationMs * 1_000L else C_TIME_UNSET)
            .build()
    }

    // --- Transport controls: forward to Dart, update visible state optimistically.

    override fun handleSetPlayWhenReady(playWhenReady: Boolean): ListenableFuture<*> {
        onCommand(if (playWhenReady) "play" else "pause", null)
        return Futures.immediateVoidFuture()
    }

    private var pendingSeekRunnable: Runnable? = null
    private val seekHandler = android.os.Handler(looper)

    override fun handleSeek(
        mediaItemIndex: Int,
        positionMs: Long,
        @Player.Command seekCommand: Int,
    ): ListenableFuture<*> {
        when (seekCommand) {
            Player.COMMAND_SEEK_TO_NEXT,
            Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM,
            -> {
                pendingSeekRunnable?.let { seekHandler.removeCallbacks(it) }
                onCommand("next", null)
            }
            Player.COMMAND_SEEK_TO_PREVIOUS,
            Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM,
            -> {
                pendingSeekRunnable?.let { seekHandler.removeCallbacks(it) }
                onCommand("previous", null)
            }
            else -> {
                val targetMs = if (positionMs >= 0) positionMs else 0L
                this.positionMs = targetMs
                invalidateState()
                pendingSeekRunnable?.let { seekHandler.removeCallbacks(it) }
                val r = Runnable {
                    onCommand("seek", targetMs)
                }
                pendingSeekRunnable = r
                seekHandler.postDelayed(r, 100)
            }
        }
        return Futures.immediateVoidFuture()
    }

    override fun handleStop(): ListenableFuture<*> {
        onCommand("pause", null)
        return Futures.immediateVoidFuture()
    }
}
