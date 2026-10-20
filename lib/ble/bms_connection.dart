// Talks to one BQ40Z80 monitor over BLE. This is the only file that uses
// flutter_blue_plus, so swapping BLE libraries stays a one-file change.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'bms_protocol.dart';

/// 9a1b000X-5f3c-4e8a-b7d2-1c6e4f8a2b30 -- must match main/ble_server.cpp.
class BmsUuids {
  static Guid _u(int x) => Guid('9a1b000$x-5f3c-4e8a-b7d2-1c6e4f8a2b30');
  static final service = _u(1);
  static final live = _u(2);
  static final info = _u(3);
  static final detail = _u(4);
  static final cmd = _u(5);
  static final settings = _u(6);
  static final dfRead = _u(7);
}

/// Personal / hobby use. A for-profit product needs License.commercial from
/// the FlutterBluePlus author -- see the package's LICENSE.
const _fbpLicense = License.nonprofit;

enum BmsLinkState { disconnected, connecting, connected }

class BmsConnection extends ChangeNotifier {
  BmsConnection(this.device);

  final BluetoothDevice device;

  BmsLinkState _state = BmsLinkState.disconnected;
  BmsLinkState get state => _state;

  LiveData? live;
  InfoData? info;
  DetailData? detail;
  SettingsData? settings;
  DateTime? liveAt;

  /// False on firmware older than the settings feature.
  bool settingsSupported = false;

  /// False on firmware without whole-data-memory access (DFREAD).
  bool dataMemorySupported = false;
  String? error;
  bool _disposed = false;

  BluetoothCharacteristic? _live, _info, _detail, _cmd, _settings, _dfRead;
  StreamSubscription<List<int>>? _liveSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  Timer? _ticker;
  int _tick = 0;

  String get name =>
      device.advName.isNotEmpty ? device.advName : device.remoteId.str;

  bool get stale =>
      liveAt == null || DateTime.now().difference(liveAt!) > const Duration(seconds: 4);

  Future<void> connect() async {
    if (_state != BmsLinkState.disconnected) return;
    _set(BmsLinkState.connecting, clearError: true);
    try {
      // connect() asks Android for MTU 512; the ESP32 settles on 256, which
      // fits the 152-byte LIVE notification. iOS negotiates on its own.
      await device.connect(license: _fbpLicense, timeout: const Duration(seconds: 15));
      _connSub = device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) _onLinkLost();
      });

      final services = await device.discoverServices();
      final svc = services.where((s) => s.uuid == BmsUuids.service).firstOrNull;
      if (svc == null) throw StateError('BMS service not found -- wrong firmware?');
      BluetoothCharacteristic chr(Guid id) =>
          svc.characteristics.firstWhere((c) => c.uuid == id);
      _live = chr(BmsUuids.live);
      _info = chr(BmsUuids.info);
      _detail = chr(BmsUuids.detail);
      _cmd = chr(BmsUuids.cmd);
      _settings = svc.characteristics.where((c) => c.uuid == BmsUuids.settings).firstOrNull;
      settingsSupported = _settings != null;
      _dfRead = svc.characteristics.where((c) => c.uuid == BmsUuids.dfRead).firstOrNull;
      dataMemorySupported = _dfRead != null;

      _liveSub = _live!.onValueReceived.listen(_onLive);
      await _live!.setNotifyValue(true);

      _set(BmsLinkState.connected);
      await Future.wait([_readLive(), refreshInfo(), refreshDetail()]);
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    } catch (e) {
      error = _describe(e);
      await _teardown();
      try {
        await device.disconnect();
      } catch (_) {}
      _set(BmsLinkState.disconnected);
    }
  }

  Future<void> disconnect() async {
    await _teardown();
    try {
      await device.disconnect();
    } catch (_) {}
    _set(BmsLinkState.disconnected);
  }

  Future<void> refreshInfo() async {
    final c = _info;
    if (c == null) return;
    try {
      info = InfoData.parse(await c.read());
      _notify();
    } catch (e) {
      error = _describe(e);
      _notify();
    }
  }

  Future<void> refreshDetail() async {
    final c = _detail;
    if (c == null) return;
    try {
      detail = DetailData.parse(await c.read());
      _notify();
    } catch (e) {
      error = _describe(e);
      _notify();
    }
  }

  /// Reads the writable data flash settings. The firmware reads each one from
  /// the gauge, so this takes a moment; it is only done on request.
  Future<void> refreshSettings() async {
    final c = _settings;
    if (c == null) return;
    try {
      settings = SettingsData.parse(await c.read());
      _notify();
    } catch (e) {
      error = _describe(e);
      _notify();
    }
  }

  /// Writes one data flash setting ([raw] in the gauge's own units) and reads
  /// the settings back. The firmware range-checks it, writes it and verifies
  /// it by reading it back. The first write triggers pairing.
  Future<void> writeSetting(int id, int raw) async {
    final c = _cmd;
    if (c == null) throw StateError('not connected');
    final v = raw & 0xFFFFFFFF;
    try {
      await c.write([0x02, id, v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF],
          timeout: 60);
    } on FlutterBluePlusException catch (e) {
      throw Exception(_cmdError(e));
    } finally {
      await refreshSettings();
    }
  }

  /// Raw data flash bytes, [len] at most 480. DFREAD is select-then-read, so
  /// requests are queued: two screens must not interleave their selections.
  Future<List<int>> readDataFlash(int addr, int len) {
    final run = _dfQueue.then((_) async {
      final c = _dfRead;
      if (c == null) throw StateError('not connected');
      await c.write([addr & 0xFF, addr >> 8, len & 0xFF, len >> 8]);
      final r = await c.read();
      if (r.length != 5 + len || r[0] != 1 || (r[1] | r[2] << 8) != addr) {
        throw ProtocolException('DFREAD returned ${r.length} bytes for 0x${addr.toRadixString(16)}');
      }
      return r.sublist(5);
    });
    _dfQueue = run.catchError((_) => const <int>[]);
    return run;
  }

  Future<void> _dfQueue = Future.value();

  /// Writes one data flash parameter by address ([raw] as stored). The
  /// firmware only accepts addresses in its generated catalog, checks TI's
  /// limits (and the curated limits where they apply) and verifies the write.
  Future<void> writeDataFlash(int addr, int raw) async {
    final c = _cmd;
    if (c == null) throw StateError('not connected');
    final v = raw & 0xFFFFFFFF;
    try {
      await c.write([0x03, addr & 0xFF, addr >> 8, v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF,
          (v >> 24) & 0xFF], timeout: 60);
    } on FlutterBluePlusException catch (e) {
      throw Exception(_cmdError(e));
    }
    if (settingsSupported) await refreshSettings();
  }

  static String _cmdError(FlutterBluePlusException e) => switch (e.code) {
        0x83 => 'The firmware does not allow changing this parameter.',
        0x84 => 'Value is outside the allowed range.',
        0x85 => 'Value would cross its threshold or recovery partner.',
        0x86 => 'The gauge is SEALED. Unseal it in BQStudio first.',
        0x87 => 'The SMBus is busy. Try again.',
        0x88 => 'SMBus error while writing. Nothing was verified.',
        0x89 => 'Write did not verify: the gauge reads back a different value.',
        5 || 15 => 'Pairing is required. Enter the PIN set in the firmware.',
        _ => e.description ?? e.toString(),
      };

  /// Sends DeviceReset. [unsafe] must reflect what the user was warned about:
  /// the firmware only accepts CONFIRM-UNSAFE when a reset would clear FET_EN,
  /// and only CONFIRM when it would not. The first write triggers pairing.
  Future<void> resetGauge({required bool unsafe}) async {
    final c = _cmd;
    if (c == null) throw StateError('not connected');
    final token = unsafe ? 'CONFIRM-UNSAFE' : 'CONFIRM';
    try {
      // Long timeout: the user may be typing the pairing PIN.
      await c.write([0x01, ...ascii.encode(token)], timeout: 60);
    } on FlutterBluePlusException catch (e) {
      throw Exception(switch (e.code) {
        0x80 => 'Rejected: the reset hazard changed. Re-check and try again.',
        0x81 => 'The gauge did not accept DeviceReset (SMBus error).',
        5 || 15 => 'Pairing is required. Enter the PIN set in the firmware.',
        _ => e.description ?? e.toString(),
      });
    }
  }

  // ---------------------------------------------------------------------------

  void _onLive(List<int> value) {
    try {
      live = LiveData.parse(value);
      liveAt = DateTime.now();
      error = null;
    } catch (e) {
      error = _describe(e);
    }
    _notify();
  }

  Future<void> _readLive() async {
    final c = _live;
    if (c == null) return;
    try {
      _onLive(await c.read());
    } catch (_) {}
  }

  void _onTick() {
    if (_state != BmsLinkState.connected) return;
    _tick++;
    // Notifications are the normal path. If they stop -- a phone stuck at a
    // small MTU, say -- fall back to reading LIVE directly.
    if (stale) _readLive();
    // The pack may be plugged in after the ESP32 booted.
    if (_tick % 10 == 0 && (info == null || !info!.valid) && (live?.staticValid ?? false)) {
      refreshInfo();
    }
    // The firmware refreshes the slow tier every 30 s.
    if (_tick % 30 == 0) refreshDetail();
    _notify(); // keeps the "stale" indicator honest
  }

  void _onLinkLost() {
    if (_state == BmsLinkState.disconnected) return;
    error ??= 'Connection lost';
    _teardown();
    _set(BmsLinkState.disconnected);
  }

  Future<void> _teardown() async {
    _ticker?.cancel();
    _ticker = null;
    await _liveSub?.cancel();
    _liveSub = null;
    await _connSub?.cancel();
    _connSub = null;
    _live = _info = _detail = _cmd = _settings = _dfRead = null;
  }

  void _set(BmsLinkState s, {bool clearError = false}) {
    _state = s;
    if (clearError) error = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  static String _describe(Object e) =>
      e is FlutterBluePlusException ? (e.description ?? e.toString()) : e.toString();

  @override
  void dispose() {
    _disposed = true;
    _teardown();
    device.disconnect().catchError((_) {});
    super.dispose();
  }
}

/// Scanning, filtered to devices advertising the BMS service.
class BmsScanner {
  static Stream<List<ScanResult>> get results => FlutterBluePlus.scanResults;
  static Stream<bool> get isScanning => FlutterBluePlus.isScanning;
  static Stream<BluetoothAdapterState> get adapterState => FlutterBluePlus.adapterState;

  static Future<void> start() => FlutterBluePlus.startScan(
        withServices: [BmsUuids.service],
        timeout: const Duration(seconds: 10),
      );

  static Future<void> stop() => FlutterBluePlus.stopScan();

  static Future<void> turnOnAdapter() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      await FlutterBluePlus.turnOn();
    }
  }
}
