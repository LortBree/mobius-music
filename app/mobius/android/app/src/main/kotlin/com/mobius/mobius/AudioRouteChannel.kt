package com.mobius.mobius

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * `mobius/audio_route` — tells the Signal path UI where media audio is going.
 *
 * AAudio (in the Rust engine) cannot name the output device, so the host
 * answers `current` -> `{type, name}` with type one of
 * speaker | wired | bluetooth | usb | unknown.
 *
 * API 33+: asks the audio policy which device MEDIA is actually routed to
 * ([AudioManager.getAudioDevicesForAttributes]) — ground truth.
 * Below 33: falls back to the platform's media priority (USB > Bluetooth >
 * wired > speaker) over the connected outputs, which matches default routing
 * but is an estimate.
 */
class AudioRouteChannel(context: Context) : MethodChannel.MethodCallHandler {

    private val audioManager =
        context.applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "current" -> result.success(currentRoute())
            else -> result.notImplemented()
        }
    }

    private fun currentRoute(): Map<String, String> {
        val device = routedMediaDevice() ?: return mapOf("type" to "unknown", "name" to "")
        val type = classify(device.type)
        val name = when (type) {
            "speaker" -> "Built-in speaker"
            else -> device.productName?.toString()?.takeIf { it.isNotBlank() } ?: ""
        }
        return mapOf("type" to type, "name" to name)
    }

    private fun routedMediaDevice(): AudioDeviceInfo? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val attributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build()
            val routed = runCatching { audioManager.getAudioDevicesForAttributes(attributes) }
                .getOrNull()
                ?.firstOrNull()
            if (routed != null) return routed
        }
        val outputs = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        val priority = listOf("usb", "bluetooth", "wired", "speaker")
        return outputs
            .filter { classify(it.type) != "unknown" }
            .minByOrNull { priority.indexOf(classify(it.type)) }
    }

    private fun classify(type: Int): String = when (type) {
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER_SAFE,
        AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "speaker"

        AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
        AudioDeviceInfo.TYPE_LINE_ANALOG,
        AudioDeviceInfo.TYPE_AUX_LINE -> "wired"

        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
        AudioDeviceInfo.TYPE_BLE_HEADSET,
        AudioDeviceInfo.TYPE_BLE_SPEAKER,
        AudioDeviceInfo.TYPE_BLE_BROADCAST -> "bluetooth"

        AudioDeviceInfo.TYPE_USB_DEVICE,
        AudioDeviceInfo.TYPE_USB_HEADSET,
        AudioDeviceInfo.TYPE_USB_ACCESSORY -> "usb"

        else -> "unknown"
    }

    companion object {
        const val CHANNEL = "mobius/audio_route"
    }
}
