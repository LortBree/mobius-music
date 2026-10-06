package com.mobius.mobius

import androidx.media3.common.util.UnstableApi
import androidx.media3.session.MediaSession

/**
 * Connection gate for [MobiusPlaybackService]'s session.
 *
 * The service is `exported` because the media3 intent filter demands it, which
 * means ANY app on the device could otherwise bind and drive transport. media3's
 * default [MediaSession.Callback.onConnect] accepts everyone, so we replace it
 * with one that accepts ONLY:
 *   * this app's own package (the Flutter UI's own MediaController, if any);
 *   * trusted controllers — the platform media session, SystemUI's notification
 *     and lock-screen controls, and holders of MEDIA_CONTENT_CONTROL — which
 *     media3 flags via [MediaSession.ControllerInfo.isTrusted];
 *   * the media-notification controller media3 itself uses to render the
 *     notification ([MediaSession.isMediaNotificationController]).
 * Everything else is rejected.
 *
 * Headset / Bluetooth media buttons are NOT affected: they arrive through the
 * platform `MediaSession` / media-button receiver as a trusted system route,
 * not as a third-party [MediaController] connection, so they still reach the
 * player.
 *
 * Android Auto / Wear are explicitly out of scope and are not special-cased.
 */
@UnstableApi
class MediaSessionCallback(private val ownPackageName: String) : MediaSession.Callback {

    override fun onConnect(
        session: MediaSession,
        controller: MediaSession.ControllerInfo,
    ): MediaSession.ConnectionResult {
        val allowed = controller.packageName == ownPackageName ||
            controller.isTrusted ||
            session.isMediaNotificationController(controller)
        return if (allowed) {
            // Default accept: the available session/player commands are media3's
            // standard set, which the facade further constrains via getState().
            super.onConnect(session, controller)
        } else {
            MediaSession.ConnectionResult.reject()
        }
    }
}
