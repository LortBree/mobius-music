package com.mobius.mobius

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Build
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Host side of the `mobius/usb` channel for Bit-perfect USB DAC support.
 *
 * Implements Phase 2 (§5.2):
 * - Discovers FiiO JadeAudio JA11 (VID 10610 / 0x2972, PID 258 / 0x0102).
 * - Manages runtime USB permission via [UsbManager.requestPermission].
 * - Opens the device via [UsbManager.openDevice] and passes the underlying file
 *   descriptor (fd) to Dart / native Rust.
 * - Manages lifecycle on attach/detach.
 * - Kotlin NEVER touches audio bytes.
 */
class UsbChannel(
    private val activity: Activity,
    private val channel: MethodChannel,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "mobius/usb"
        private const val TAG = "MobiusUsb"
        private const val ACTION_USB_PERMISSION = "com.mobius.mobius.USB_PERMISSION"

        // FiiO JadeAudio JA11:
        const val JA11_VID = 10610 // 0x2972
        const val JA11_PID = 258   // 0x0102

        // UAC2 Audio Streaming interface on JA11:
        const val JA11_STREAMING_INTERFACE = 2

        const val ACTION_RUN_SPIKE = "com.mobius.mobius.RUN_USB_SPIKE"
    }

    private val usbManager = activity.getSystemService(Context.USB_SERVICE) as UsbManager
    private var activeConnection: UsbDeviceConnection? = null
    private var activeDevice: UsbDevice? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    private val usbReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                ACTION_USB_PERMISSION -> {
                    val device = getParcelableDevice(intent)
                    val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                    Log.i(TAG, "USB permission result for device: $device, granted: $granted")
                    val result = pendingPermissionResult
                    pendingPermissionResult = null
                    if (device != null && isJa11(device)) {
                        if (granted) {
                            val openData = openDeviceInternal(1) ?: deviceMap(device, hasPermission = true)
                            result?.success(openData)
                            channel.invokeMethod("onPermissionGranted", openData)
                        } else {
                            result?.success(mapOf("status" to "permission_denied", "granted" to false))
                            channel.invokeMethod("onPermissionDenied", deviceMap(device, hasPermission = false))
                        }
                    } else {
                        result?.success(mapOf("status" to "unknown_device", "granted" to false))
                    }
                }
                UsbManager.ACTION_USB_DEVICE_ATTACHED -> {
                    val device = getParcelableDevice(intent)
                    Log.i(TAG, "USB device attached: $device")
                    if (device != null && isJa11(device)) {
                        val hasPerm = usbManager.hasPermission(device)
                        if (hasPerm) {
                            val openData = openDeviceInternal(1) ?: deviceMap(device, hasPermission = true)
                            channel.invokeMethod("onDeviceAttached", openData)
                        } else {
                            channel.invokeMethod("onDeviceAttached", deviceMap(device, hasPermission = false))
                            // Seamless: automatically prompt system permission immediately!
                            requestPermissionInternal(device)
                        }
                    }
                }
                UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                    val device = getParcelableDevice(intent)
                    Log.i(TAG, "USB device detached: $device")
                    if (device != null && isJa11(device)) {
                        closeDevice()
                        channel.invokeMethod("onDeviceDetached", deviceMap(device, hasPermission = false))
                    }
                }
                ACTION_RUN_SPIKE -> {
                    Log.i(TAG, "RUN_USB_SPIKE intent received, delegating to Dart")
                    channel.invokeMethod("onRunSpikeRequested", null)
                }
            }
        }
    }

    init {
        val filter = IntentFilter().apply {
            addAction(ACTION_USB_PERMISSION)
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
            addAction(ACTION_RUN_SPIKE)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.registerReceiver(usbReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            activity.registerReceiver(usbReceiver, filter)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getDeviceStatus" -> {
                val device = findJa11Device()
                if (device != null) {
                    val hasPerm = usbManager.hasPermission(device)
                    result.success(deviceMap(device, hasPermission = hasPerm))
                } else {
                    result.success(mapOf("attached" to false))
                }
            }
            "requestPermission" -> {
                val device = findJa11Device()
                if (device == null) {
                    result.error("NO_DEVICE", "FiiO JA11 USB DAC not attached", null)
                    return
                }
                if (usbManager.hasPermission(device)) {
                    val openData = openDeviceInternal(1) ?: deviceMap(device, hasPermission = true)
                    result.success(openData)
                    return
                }
                if (pendingPermissionResult != null) {
                    result.error("PENDING", "Permission request already in progress", null)
                    return
                }
                pendingPermissionResult = result
                requestPermissionInternal(device)
            }
            "openDevice" -> {
                val requestedAlt = call.argument<Int>("altSetting") ?: 1
                val openData = openDeviceInternal(requestedAlt)
                if (openData != null) {
                    result.success(openData)
                } else {
                    result.error("OPEN_FAILED", "Failed to open USB device", null)
                }
            }
            "setAltSetting" -> {
                val alt = call.argument<Int>("alt") ?: 1
                val ok = selectAltSetting(alt)
                result.success(ok)
            }
            "closeDevice" -> {
                closeDevice()
                result.success(mapOf("status" to "closed"))
            }
            else -> result.notImplemented()
        }
    }

    private fun requestPermissionInternal(device: UsbDevice) {
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val permissionIntent = PendingIntent.getBroadcast(
            activity,
            0,
            Intent(ACTION_USB_PERMISSION).apply {
                setPackage(activity.packageName)
            },
            flags,
        )
        usbManager.requestPermission(device, permissionIntent)
    }

    private fun openDeviceInternal(requestedAlt: Int = 1): Map<String, Any?>? {
        val device = findJa11Device() ?: return null
        if (!usbManager.hasPermission(device)) return null
        return try {
            closeDevice()
            val conn = usbManager.openDevice(device) ?: return null
            activeConnection = conn
            activeDevice = device
            val fd = conn.fileDescriptor

            for (i in 0 until device.interfaceCount) {
                val itf = device.getInterface(i)
                if (itf.id == 0 || itf.id == JA11_STREAMING_INTERFACE) {
                    val claimed = conn.claimInterface(itf, true)
                    Log.i(TAG, "conn.claimInterface(intf ${itf.id}, force=true) -> $claimed")
                }
            }
            selectAltSetting(requestedAlt)
            Log.i(TAG, "Opened USB device successfully: fd=$fd, VID=${device.vendorId}, PID=${device.productId}")
            mapOf(
                "status" to "opened",
                "attached" to true,
                "hasPermission" to true,
                "fd" to fd,
                "vid" to device.vendorId,
                "pid" to device.productId,
                "name" to (device.productName ?: "FiiO JadeAudio JA11"),
                "manufacturer" to (device.manufacturerName ?: "FIIO"),
                "interface" to JA11_STREAMING_INTERFACE,
                "altSetting" to requestedAlt,
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error opening USB device", e)
            null
        }
    }

    fun handleIntent(intent: Intent?) {
        if (intent == null) return
        when (intent.action) {
            UsbManager.ACTION_USB_DEVICE_ATTACHED -> {
                val device = getParcelableDevice(intent) ?: findJa11Device()
                Log.i(TAG, "handleIntent: USB device attached: $device")
                if (device != null && isJa11(device)) {
                    val hasPerm = usbManager.hasPermission(device)
                    if (hasPerm) {
                        val openData = openDeviceInternal(1) ?: deviceMap(device, hasPermission = true)
                        channel.invokeMethod("onDeviceAttached", openData)
                    } else {
                        channel.invokeMethod("onDeviceAttached", deviceMap(device, hasPermission = false))
                        requestPermissionInternal(device)
                    }
                }
            }
        }
    }

    private fun selectAltSetting(alt: Int): Boolean {
        val conn = activeConnection ?: return false
        val dev = activeDevice ?: return false
        for (i in 0 until dev.interfaceCount) {
            val itf = dev.getInterface(i)
            if (itf.id == JA11_STREAMING_INTERFACE && itf.alternateSetting == alt) {
                val ok = conn.setInterface(itf)
                Log.i(TAG, "conn.setInterface(alt $alt) returned $ok")
                return ok
            }
        }
        return false
    }

    private fun findJa11Device(): UsbDevice? {
        val list = usbManager.deviceList
        for (device in list.values) {
            if (isJa11(device)) {
                return device
            }
        }
        return null
    }

    private fun isJa11(device: UsbDevice): Boolean {
        return device.vendorId == JA11_VID && device.productId == JA11_PID
    }

    private fun deviceMap(device: UsbDevice, hasPermission: Boolean): Map<String, Any?> {
        return mapOf(
            "attached" to true,
            "hasPermission" to hasPermission,
            "vid" to device.vendorId,
            "pid" to device.productId,
            "name" to (device.productName ?: "FiiO JadeAudio JA11"),
            "manufacturer" to (device.manufacturerName ?: "FIIO"),
            "interface" to JA11_STREAMING_INTERFACE,
        )
    }

    private fun closeDevice() {
        try {
            activeConnection?.close()
        } catch (e: Exception) {
            Log.w(TAG, "Error closing USB connection", e)
        } finally {
            activeConnection = null
            activeDevice = null
        }
    }

    private fun getParcelableDevice(intent: Intent): UsbDevice? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
        }
    }

    fun dispose() {
        try {
            activity.unregisterReceiver(usbReceiver)
        } catch (_: Exception) {}
        closeDevice()
    }
}
