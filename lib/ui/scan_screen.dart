import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../ble/bms_connection.dart';
import 'dashboard_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  List<ScanResult> _results = [];
  bool _scanning = false;
  BluetoothAdapterState _adapter = BluetoothAdapterState.unknown;
  String? _error;
  final _subs = <StreamSubscription<dynamic>>[];

  @override
  void initState() {
    super.initState();
    _subs
      ..add(BmsScanner.results.listen((r) => setState(() => _results = r)))
      ..add(BmsScanner.isScanning.listen((s) => setState(() => _scanning = s)))
      ..add(BmsScanner.adapterState.listen((s) {
        final wasOff = _adapter != BluetoothAdapterState.on;
        setState(() => _adapter = s);
        if (s == BluetoothAdapterState.on && wasOff) _scan();
      }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    BmsScanner.stop();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() => _error = null);
    try {
      await BmsScanner.start();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _open(ScanResult r) async {
    await BmsScanner.stop();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DashboardScreen(connection: BmsConnection(r.device)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hero BMS'),
        bottom: _scanning
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3), child: LinearProgressIndicator(minHeight: 3))
            : null,
      ),
      floatingActionButton: _adapter == BluetoothAdapterState.on
          ? FloatingActionButton.extended(
              onPressed: _scanning ? BmsScanner.stop : _scan,
              icon: Icon(_scanning ? Icons.stop : Icons.bluetooth_searching),
              label: Text(_scanning ? 'Stop' : 'Scan'),
            )
          : null,
      body: switch (_adapter) {
        BluetoothAdapterState.on => RefreshIndicator(
            onRefresh: _scan,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                if (_error != null)
                  ListTile(
                    leading: const Icon(Icons.error_outline, color: Colors.redAccent),
                    title: Text(_error!),
                  ),
                if (_results.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      _scanning
                          ? 'Looking for packs…'
                          : 'No packs found. Make sure the BMS is powered and in range, then scan again.',
                      textAlign: TextAlign.center,
                      style: t.textTheme.bodyLarge
                          ?.copyWith(color: t.colorScheme.onSurfaceVariant),
                    ),
                  ),
                for (final r in _results)
                  Card(
                    margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.battery_charging_full)),
                      title: Text(r.device.advName.isNotEmpty
                          ? r.device.advName
                          : r.advertisementData.advName.isNotEmpty
                              ? r.advertisementData.advName
                              : 'Unnamed BMS'),
                      subtitle: Text(r.device.remoteId.str),
                      trailing: _Rssi(r.rssi),
                      onTap: () => _open(r),
                    ),
                  ),
              ],
            ),
          ),
        BluetoothAdapterState.unknown => const Center(child: CircularProgressIndicator()),
        _ => _AdapterOff(state: _adapter),
      },
    );
  }
}

class _Rssi extends StatelessWidget {
  const _Rssi(this.rssi);
  final int rssi;

  @override
  Widget build(BuildContext context) {
    final bars = rssi > -60 ? 3 : rssi > -75 ? 2 : 1;
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(switch (bars) {
        3 => Icons.signal_cellular_alt,
        2 => Icons.signal_cellular_alt_2_bar,
        _ => Icons.signal_cellular_alt_1_bar,
      }),
      Text('$rssi dBm', style: Theme.of(context).textTheme.labelSmall),
    ]);
  }
}

class _AdapterOff extends StatelessWidget {
  const _AdapterOff({required this.state});
  final BluetoothAdapterState state;

  @override
  Widget build(BuildContext context) {
    final unauthorized = state == BluetoothAdapterState.unauthorized;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.bluetooth_disabled, size: 64),
          const SizedBox(height: 16),
          Text(
            unauthorized
                ? 'Bluetooth permission was denied. Allow it in system settings.'
                : 'Bluetooth is off.',
            textAlign: TextAlign.center,
          ),
          if (!unauthorized) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: BmsScanner.turnOnAdapter, child: const Text('Turn on')),
          ],
        ]),
      ),
    );
  }
}
