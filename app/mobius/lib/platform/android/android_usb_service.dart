import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/ffi/offline_player.dart';

class UsbDeviceStatus {
  const UsbDeviceStatus({
    required this.attached,
    this.hasPermission = false,
    this.vid = 0,
    this.pid = 0,
    this.name = '',
    this.manufacturer = '',
    this.interfaceIndex = 2,
  });

  final bool attached;
  final bool hasPermission;
  final int vid;
  final int pid;
  final String name;
  final String manufacturer;
  final int interfaceIndex;

  factory UsbDeviceStatus.fromMap(Map<dynamic, dynamic> map) {
    return UsbDeviceStatus(
      attached: map['attached'] as bool? ?? false,
      hasPermission: map['hasPermission'] as bool? ?? false,
      vid: map['vid'] as int? ?? 0,
      pid: map['pid'] as int? ?? 0,
      name: map['name'] as String? ?? '',
      manufacturer: map['manufacturer'] as String? ?? '',
      interfaceIndex: map['interface'] as int? ?? 2,
    );
  }
}

/// Android USB Host DAC manager communicating with Android `UsbManager`
/// via the `mobius/usb` channel and managing native file descriptor pass-through.
class UsbDacService extends ChangeNotifier {
  UsbDacService(this._player) {
    if (Platform.isAndroid) {
      _channel.setMethodCallHandler(_handleMethodCall);
      checkDevice();
    }
  }

  static const _channel = MethodChannel('mobius/usb');
  final OfflinePlayer _player;

  UsbDeviceStatus _status = const UsbDeviceStatus(attached: false);
  UsbDeviceStatus get status => _status;

  UsbSpikeReport? _lastSpikeReport;
  UsbSpikeReport? get lastSpikeReport => _lastSpikeReport;

  bool _isSpikeRunning = false;
  bool get isSpikeRunning => _isSpikeRunning;

  int? _activeFd;

  Future<void> attachDacToPlayer() async {
    if (!Platform.isAndroid) return;
    try {
      final openRes = await _channel.invokeMethod<Map<dynamic, dynamic>>('openDevice');
      if (openRes != null && openRes['status'] == 'opened') {
        final fd = openRes['fd'] as int;
        final vid = openRes['vid'] as int;
        final pid = openRes['pid'] as int;
        _activeFd = fd;
        debugPrint('[MobiusUsb] Attaching USB DAC to player: fd=$fd, VID=$vid, PID=$pid');
        _player.setUsbDac(fd: fd, vid: vid, pid: pid);
        _player.setBitPerfectMode(true);
        _player.switchOutputRoute();
      }
    } catch (e) {
      debugPrint('[MobiusUsb] attachDacToPlayer error: $e');
    }
  }

  void detachDacFromPlayer() {
    if (!Platform.isAndroid) return;
    try {
      debugPrint('[MobiusUsb] Detaching USB DAC from player');
      _player.setUsbDac(fd: -1, vid: 0, pid: 0);
      _player.switchOutputRoute();
      _activeFd = null;
    } catch (e) {
      debugPrint('[MobiusUsb] detachDacFromPlayer error: $e');
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    debugPrint('[MobiusUsb] MethodCall received: ${call.method}');
    switch (call.method) {
      case 'onDeviceAttached':
      case 'onPermissionGranted':
      case 'onPermissionDenied':
        if (call.arguments is Map) {
          final argMap = call.arguments as Map;
          _status = UsbDeviceStatus.fromMap(argMap);
          notifyListeners();
          if (argMap['status'] == 'opened' && argMap['fd'] is int) {
            final fd = argMap['fd'] as int;
            final vid = argMap['vid'] as int? ?? 10610;
            final pid = argMap['pid'] as int? ?? 258;
            _activeFd = fd;
            debugPrint('[MobiusUsb] Auto-attached DAC from platform event: fd=$fd, VID=$vid, PID=$pid');
            _player.setUsbDac(fd: fd, vid: vid, pid: pid);
            _player.setBitPerfectMode(true);
            _player.switchOutputRoute();
            break;
          }
        } else {
          await checkDevice();
        }
        if (_status.attached && _status.hasPermission) {
          await attachDacToPlayer();
        }
        break;
      case 'onDeviceDetached':
        _status = const UsbDeviceStatus(attached: false);
        detachDacFromPlayer();
        notifyListeners();
        break;
      case 'onRunSpikeRequested':
        unawaited(runSpike());
        break;
    }
  }

  Future<UsbDeviceStatus> checkDevice() async {
    if (!Platform.isAndroid) return _status;
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('getDeviceStatus');
      if (res != null) {
        _status = UsbDeviceStatus.fromMap(res);
        notifyListeners();
        if (_status.attached && _status.hasPermission && _activeFd == null) {
          await attachDacToPlayer();
        }
      }
    } catch (e) {
      debugPrint('[MobiusUsb] checkDevice error: $e');
    }
    return _status;
  }

  Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('requestPermission');
      final granted = res?['granted'] as bool? ?? false;
      await checkDevice();
      return granted;
    } catch (e) {
      debugPrint('[MobiusUsb] requestPermission error: $e');
      return false;
    }
  }

  Future<UsbSpikeReport?> runSpike({int durationSecs = 10}) async {
    if (!Platform.isAndroid) return null;
    if (_isSpikeRunning) return _lastSpikeReport;

    _isSpikeRunning = true;
    notifyListeners();

    debugPrint('[MOBIUS_SPIKE] Starting Phase 2 USB Isochronous Gate Spike (duration: ${durationSecs}s)...');

    try {
      await checkDevice();
      if (!_status.attached) {
        debugPrint('[MOBIUS_SPIKE] Abort: JA11 not attached');
        return null;
      }
      if (!_status.hasPermission) {
        debugPrint('[MOBIUS_SPIKE] Requesting permission first...');
        final granted = await requestPermission();
        if (!granted) {
          debugPrint('[MOBIUS_SPIKE] Abort: permission denied');
          return null;
        }
      }

      final openRes = await _channel.invokeMethod<Map<dynamic, dynamic>>('openDevice');
      if (openRes == null || openRes['status'] != 'opened') {
        debugPrint('[MOBIUS_SPIKE] Failed to open device: $openRes');
        return null;
      }

      final fd = openRes['fd'] as int;
      final vid = openRes['vid'] as int;
      final pid = openRes['pid'] as int;
      final iface = openRes['interface'] as int;

      debugPrint('[MOBIUS_SPIKE] Device opened: fd=$fd, VID=$vid, PID=$pid, iface=$iface. Executing native spike...');
      final report = _player.runUsbSpike(
        fd: fd,
        vid: vid,
        pid: pid,
        targetInterface: iface,
        durationSecs: durationSecs,
      );

      _lastSpikeReport = report;
      debugPrint('====================================================');
      debugPrint('[MOBIUS_SPIKE] SPIKE RESULT:');
      debugPrint(report.toString());
      debugPrint('Descriptor Summary:\n${report?.descriptorSummary}');
      debugPrint('====================================================');

      return report;
    } catch (e, st) {
      debugPrint('[MOBIUS_SPIKE] Error running spike: $e\n$st');
      return null;
    } finally {
      _isSpikeRunning = false;
      notifyListeners();
      if (_status.attached && _status.hasPermission) {
        await attachDacToPlayer();
      }
    }
  }
}
