package com.mobius.mobius

import android.os.Bundle
import android.view.KeyEvent
import androidx.annotation.OptIn
import androidx.core.view.WindowCompat
import androidx.media3.common.util.UnstableApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var storageChannel: StorageChannel? = null
    private var playbackChannel: PlaybackChannel? = null
    private var usbChannel: UsbChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
    }

    @OptIn(UnstableApi::class)
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        val storage = StorageChannel(this)
        MethodChannel(messenger, StorageChannel.CHANNEL).setMethodCallHandler(storage)
        // Permission + activity results reach the registered listeners on the
        // FlutterActivity; forwarded via the overrides below.
        storageChannel = storage

        val playbackMethodChannel = MethodChannel(messenger, PlaybackChannel.CHANNEL)
        val playback = PlaybackChannel(this, playbackMethodChannel)
        playbackMethodChannel.setMethodCallHandler(playback)
        playbackChannel = playback

        val usbMethodChannel = MethodChannel(messenger, UsbChannel.CHANNEL)
        val usb = UsbChannel(this, usbMethodChannel)
        usbMethodChannel.setMethodCallHandler(usb)
        usbChannel = usb
        usb.handleIntent(intent)

        MethodChannel(messenger, "mobius/app_lifecycle").setMethodCallHandler { call, result ->
            if (call.method == "moveTaskToBack") {
                moveTaskToBack(true)
                result.success(true)
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(messenger, AudioRouteChannel.CHANNEL)
            .setMethodCallHandler(AudioRouteChannel(this))

        MethodChannel(messenger, ShareChannel.CHANNEL)
            .setMethodCallHandler(ShareChannel(this))
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP || event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
            if (event.action == KeyEvent.ACTION_DOWN) {
                val direction = if (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP) 1 else -1
                playbackChannel?.onVolumeStep(direction)
            }
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        storageChannel?.onRequestPermissionsResult(requestCode, permissions, grantResults)
        playbackChannel?.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        storageChannel?.onActivityResult(requestCode, resultCode, data)
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        usbChannel?.handleIntent(intent)
    }

    @OptIn(UnstableApi::class)
    override fun onDestroy() {
        playbackChannel?.dispose()
        usbChannel?.dispose()
        storageChannel = null
        playbackChannel = null
        usbChannel = null
        super.onDestroy()
    }
}
