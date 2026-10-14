import 'package:flutter/material.dart';

import '../ble/bms_connection.dart';
import '../ble/bms_protocol.dart';
import 'widgets.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.connection});

  /// Owned by this screen: connected on open, disposed on close.
  final BmsConnection connection;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  BmsConnection get c => widget.connection;

  @override
  void initState() {
    super.initState();
    c.connect();
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final live = c.live;
        return DefaultTabController(
          length: 4,
          child: Scaffold(
            appBar: AppBar(
              title: Text(c.info?.deviceName.isNotEmpty == true ? c.info!.deviceName : c.name),
              actions: [_LinkBadge(c)],
              bottom: const TabBar(tabs: [
                Tab(text: 'Overview'),
                Tab(text: 'Cells'),
                Tab(text: 'Status'),
                Tab(text: 'Details'),
              ]),
            ),
            body: Column(children: [
              _Banner(c),
              Expanded(
                child: live == null
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(children: [
                        _OverviewTab(live),
                        _CellsTab(live, c.info),
                        _StatusTab(live, c),
                        _DetailsTab(c),
                      ]),
              ),
            ]),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Connection chrome
// -----------------------------------------------------------------------------
class _LinkBadge extends StatelessWidget {
  const _LinkBadge(this.c);
  final BmsConnection c;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (c.state) {
      BmsLinkState.connected when !c.stale => (Icons.bluetooth_connected, BmsColors.ok),
      BmsLinkState.connected => (Icons.bluetooth_connected, BmsColors.warn),
      BmsLinkState.connecting => (Icons.bluetooth_searching, BmsColors.warn),
      BmsLinkState.disconnected => (Icons.bluetooth_disabled, BmsColors.bad),
    };
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Icon(icon, color: color),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner(this.c);
  final BmsConnection c;

  @override
  Widget build(BuildContext context) {
    final live = c.live;
    String? text;
    Color color = BmsColors.warn;
    Widget? action;

    if (c.state == BmsLinkState.disconnected) {
      text = c.error ?? 'Disconnected';
      color = BmsColors.bad;
      action = TextButton(onPressed: c.connect, child: const Text('RECONNECT'));
    } else if (c.state == BmsLinkState.connecting) {
      text = 'Connecting…';
    } else if (live != null && !live.online) {
      text = 'ESP32 connected, but the BQ40Z80 is not answering on SMBus.';
      color = BmsColors.bad;
    } else if (c.stale && live != null) {
      text = 'No fresh data for a few seconds…';
    }
    if (text == null) return const SizedBox.shrink();

    return Material(
      color: color.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: Row(children: [
          Expanded(child: Text(text, style: TextStyle(color: color))),
          ?action,
        ]),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Overview
// -----------------------------------------------------------------------------
class _OverviewTab extends StatelessWidget {
  const _OverviewTab(this.d);
  final LiveData d;

  @override
  Widget build(BuildContext context) {
    final charging = d.currentMa > 50;
    final discharging = d.currentMa < -50;
    final flowColor = charging
        ? BmsColors.charge
        : discharging
            ? BmsColors.discharge
            : Theme.of(context).colorScheme.onSurfaceVariant;
    final socColor = d.rsoc <= 15 ? BmsColors.bad : d.rsoc <= 30 ? BmsColors.warn : BmsColors.ok;
    final temp = d.temperatureC;

    return ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
      SectionCard(
        title: 'Pack',
        child: Row(children: [
          SocRing(percent: d.rsoc, color: socColor, caption: d.gaugingState),
          const SizedBox(width: 16),
          Expanded(
            child: KvList([
              ('Remaining', '${d.remainingMah} mAh'),
              ('Full charge', d.fullChargeMah == 0 ? 'not learned' : '${d.fullChargeMah} mAh'),
              if (charging) ('Time to full', fmtDuration(d.avgTimeToFullMin)),
              if (!charging) ('Time to empty', fmtDuration(d.avgTimeToEmptyMin)),
              ('Cycles', '${d.cycleCount}'),
              ('Health', '${d.sohPct}%'),
            ]),
          ),
        ]),
      ),
      SectionCard(
        title: 'Live',
        child: TileGrid(columns: 2, children: [
          StatTile(label: 'Voltage', value: d.voltage.toStringAsFixed(2), unit: 'V'),
          StatTile(
              label: 'Current',
              value: d.current.toStringAsFixed(2),
              unit: 'A',
              color: flowColor),
          StatTile(
              label: 'Power', value: d.powerW.toStringAsFixed(1), unit: 'W', color: flowColor),
          StatTile(
              label: 'Temperature',
              value: temp?.toStringAsFixed(1) ?? '—',
              unit: '°C',
              color: temp != null && temp > 50 ? BmsColors.bad : null),
          StatTile(
              label: 'Cell spread',
              value: '${d.cellSpread}',
              unit: 'mV',
              color: d.cellSpread > 50 ? BmsColors.warn : null),
          StatTile(label: 'Avg current', value: (d.avgCurrentMa / 1000).toStringAsFixed(2), unit: 'A'),
        ]),
      ),
      SectionCard(
        title: 'Switches',
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          StateChip('Charge', d.chgFet),
          StateChip('Discharge', d.dsgFet),
          StateChip('Precharge', d.pchgFet),
          StateChip('Predischarge', d.pdsgFet),
          StateChip('Balancing', d.balancing, onColor: BmsColors.cellLow),
          if (d.chargeDisabled) const StateChip('Charge blocked', true, onColor: BmsColors.bad),
          if (d.dischargeDisabled)
            const StateChip('Discharge blocked', true, onColor: BmsColors.bad),
        ]),
      ),
      _AlarmCard(d),
    ]);
  }
}

class _AlarmCard extends StatelessWidget {
  const _AlarmCard(this.d);
  final LiveData d;

  @override
  Widget build(BuildContext context) {
    final items = <(String, String, Color)>[
      for (final n in pfBits.setBits(d.pfStatus)) ('PF $n', 'Permanent failure', BmsColors.bad),
      for (final n in safetyBits.setBits(d.safetyStatus))
        (n, flagDescriptions[n] ?? 'Safety fault', BmsColors.bad),
      for (final n in safetyBits.setBits(d.safetyAlert))
        (n, '${flagDescriptions[n] ?? 'Safety'} (alert)', BmsColors.warn),
      for (final n in pfBits.setBits(d.pfAlert)) ('PF $n', 'Permanent failure alert', BmsColors.warn),
      if (!d.fetEnabled) ('FET_EN', 'Gauge is not driving the FETs', BmsColors.bad),
      if (!d.gaugeEnabled) ('GAUGE_EN', 'Impedance Track gauging disabled', BmsColors.warn),
    ];

    return SectionCard(
      title: 'Protection',
      child: items.isEmpty
          ? const Row(children: [
              Icon(Icons.verified_user, color: BmsColors.ok),
              SizedBox(width: 8),
              Text('All clear'),
            ])
          : Column(children: [
              for (final (code, text, color) in items)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.warning_amber_rounded, color: color),
                  title: Text(text),
                  trailing: Text(code, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
                ),
            ]),
    );
  }
}

// -----------------------------------------------------------------------------
// Cells
// -----------------------------------------------------------------------------
class _CellsTab extends StatelessWidget {
  const _CellsTab(this.d, this.info);
  final LiveData d;
  final InfoData? info;

  @override
  Widget build(BuildContext context) {
    final cells = d.cells;
    final sum = cells.fold<int>(0, (a, b) => a + b);
    final avg = sum / cells.length;
    // Bar scale follows the chemistry; LFP sits much lower than Li-ion.
    final lfp = info?.isLfpChemId ?? true;
    final (lo, hi) = lfp ? (2500, 3650) : (3000, 4250);

    return ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
      SectionCard(
        title: 'Summary',
        child: TileGrid(columns: 3, children: [
          StatTile(label: 'Max (#${d.cellMaxIndex + 1})', value: '${d.cellMax}', unit: 'mV',
              color: BmsColors.cellHigh),
          StatTile(label: 'Min (#${d.cellMinIndex + 1})', value: '${d.cellMin}', unit: 'mV',
              color: BmsColors.cellLow),
          StatTile(label: 'Spread', value: '${d.cellSpread}', unit: 'mV'),
          StatTile(label: 'Average', value: avg.toStringAsFixed(0), unit: 'mV'),
          StatTile(label: 'Sum', value: (sum / 1000).toStringAsFixed(2), unit: 'V'),
          StatTile(label: 'BAT pin', value: (d.batMv / 1000).toStringAsFixed(2), unit: 'V'),
        ]),
      ),
      SectionCard(
        title: 'Cell voltages',
        trailing: d.balancing
            ? const StateChip('Balancing', true, onColor: BmsColors.cellLow)
            : null,
        child: Column(children: [
          for (var i = 0; i < cells.length; i++)
            _CellBar(
              index: i,
              mv: cells[i],
              ma: d.cellMa[i],
              fraction: ((cells[i] - lo) / (hi - lo)).clamp(0.0, 1.0),
              color: cells.length > 1 && i == d.cellMaxIndex && d.cellSpread > 0
                  ? BmsColors.cellHigh
                  : cells.length > 1 && i == d.cellMinIndex && d.cellSpread > 0
                      ? BmsColors.cellLow
                      : BmsColors.ok,
            ),
        ]),
      ),
      SectionCard(
        title: 'Temperatures',
        child: KvList([
          for (var i = 0; i < 7; i++) (tempSensorNames[i], _tempText(d.tempsDk[i])),
        ]),
      ),
    ]);
  }

  static String _tempText(int dK) {
    final c = dKToC(dK);
    return c == null ? 'not fitted' : '${c.toStringAsFixed(1)} °C';
  }
}

class _CellBar extends StatelessWidget {
  const _CellBar({
    required this.index,
    required this.mv,
    required this.ma,
    required this.fraction,
    required this.color,
  });

  final int index, mv, ma;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(
          width: 28,
          child: Text('${index + 1}',
              style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 14,
              color: color,
              backgroundColor: t.colorScheme.surfaceContainerHighest,
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 92,
          child: Text('${(mv / 1000).toStringAsFixed(3)} V',
              textAlign: TextAlign.right,
              style: t.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: color == BmsColors.ok ? null : color,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ),
      ]),
    );
  }
}

// -----------------------------------------------------------------------------
// Status
// -----------------------------------------------------------------------------
class _StatusTab extends StatelessWidget {
  const _StatusTab(this.d, this.c);
  final LiveData d;
  final BmsConnection c;

  @override
  Widget build(BuildContext context) {
    final registers = <(BitRegister, int)>[
      (operationBits, d.operationStatus),
      (batteryStatusBits, d.batteryStatus),
      (chargingStatusBits, d.chargingStatus),
      (gaugingStatusBits, d.gaugingStatus),
      (mfgStatusBits, d.mfgStatus),
      (safetyBits, d.safetyStatus),
      (pfBits, d.pfStatus),
    ];

    return ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
      SectionCard(
        title: 'Gauge',
        child: KvList([
          ('State', d.gaugingState),
          ('Security', securityModeNames[d.securityMode]),
          ('FET_EN / GAUGE_EN', '${d.fetEnabled ? 'on' : 'OFF'} / ${d.gaugeEnabled ? 'on' : 'OFF'}'),
          ('Charger request', '${d.chargingCurrentMa} mA @ ${d.chargingVoltageMv} mV'),
          ('BAT / PACK pin', '${d.batMv} / ${d.packMv} mV'),
          ('ASOC', '${d.asoc}%'),
          ('Max error', '${d.maxError}%'),
        ]),
      ),
      SectionCard(
        title: 'Registers',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (reg, value) in registers) _RegisterRow(reg, value),
        ]),
      ),
      SectionCard(
        title: 'Monitor',
        child: KvList([
          ('ESP32 uptime', fmtUptime(d.uptimeS)),
          ('Polls / read errors', '${d.pollCount} / ${d.errorCount}'),
          ('Resets since boot', '${d.resetCount}'),
          ('Last update', c.liveAt == null ? null : _ago(c.liveAt!)),
        ]),
      ),
      _ResetCard(d, c),
    ]);
  }

  static String _ago(DateTime t) {
    final s = DateTime.now().difference(t).inSeconds;
    return s < 2 ? 'just now' : '${s}s ago';
  }
}

class _RegisterRow extends StatelessWidget {
  const _RegisterRow(this.reg, this.value);
  final BitRegister reg;
  final int value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final set = reg.setBits(value);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(reg.title, style: t.textTheme.bodyMedium)),
          Text(hex(value, reg.width ~/ 4),
              style: t.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
        ]),
        const SizedBox(height: 4),
        set.isEmpty
            ? Text('no bits set',
                style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant))
            : Wrap(spacing: 4, runSpacing: 4, children: [
                for (final n in set)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: t.colorScheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(n, style: t.textTheme.labelSmall),
                  ),
              ]),
      ]),
    );
  }
}

class _ResetCard extends StatelessWidget {
  const _ResetCard(this.d, this.c);
  final LiveData d;
  final BmsConnection c;

  Future<void> _confirm(BuildContext context) async {
    // Captured now: this is what the user is warned about, and the firmware
    // rejects the token if the hazard has changed by the time it arrives.
    final unsafe = !d.resetSafe;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => _ResetDialog(unsafe: unsafe),
    );
    if (ok != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Sending DeviceReset…')));
    try {
      await c.resetGauge(unsafe: unsafe);
      messenger.showSnackBar(const SnackBar(
          content: Text('Reset sent. The gauge will be unresponsive for a moment.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          backgroundColor: BmsColors.bad,
          content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Maintenance',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          d.resetSafe
              ? 'DeviceReset clears latched protection faults. FET control survives the reset.'
              : 'DeviceReset would leave FET_EN clear: the pack will not charge or discharge '
                  'until FET_EN is restored in BQStudio.',
          style: TextStyle(color: d.resetSafe ? null : BmsColors.bad),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: BmsColors.bad),
          onPressed: c.state == BmsLinkState.connected ? () => _confirm(context) : null,
          icon: const Icon(Icons.restart_alt),
          label: const Text('Reset gauge'),
        ),
      ]),
    );
  }
}

class _ResetDialog extends StatefulWidget {
  const _ResetDialog({required this.unsafe});
  final bool unsafe;

  @override
  State<_ResetDialog> createState() => _ResetDialogState();
}

class _ResetDialogState extends State<_ResetDialog> {
  bool _ack = false;

  @override
  Widget build(BuildContext context) {
    final mayProceed = !widget.unsafe || _ack;
    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded,
          color: widget.unsafe ? BmsColors.bad : BmsColors.warn, size: 36),
      title: const Text('Reset the gauge?'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('DeviceReset (MAC 0x0041) will:\n'
            '• reboot the BQ40Z80 and clear latched safety faults\n'
            '• increment the lifetime reset counters\n'
            '• reload Manufacturing Status from data flash'),
        if (widget.unsafe) ...[
          const SizedBox(height: 12),
          const Text(
            'Mfg Status Init has FET_EN clear (or could not be read). After the reset the '
            'gauge stops driving the CHG, DSG and PCHG FETs.',
            style: TextStyle(color: BmsColors.bad),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _ack,
            onChanged: (v) => setState(() => _ack = v ?? false),
            title: const Text('I understand the pack will stop working until FET_EN is restored'),
          ),
        ],
        const SizedBox(height: 8),
        Text('Your phone may ask for the BMS pairing PIN.',
            style: Theme.of(context).textTheme.bodySmall),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: BmsColors.bad),
          onPressed: mayProceed ? () => Navigator.pop(context, true) : null,
          child: const Text('Reset'),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Details
// -----------------------------------------------------------------------------
class _DetailsTab extends StatelessWidget {
  const _DetailsTab(this.c);
  final BmsConnection c;

  @override
  Widget build(BuildContext context) {
    final info = c.info;
    final x = c.detail;
    final n = c.live?.cellCount ?? 7;

    String perCell(List<int> v) => v.take(n).join(' / ');

    return RefreshIndicator(
      onRefresh: () => Future.wait([c.refreshDetail(), c.refreshInfo()]),
      child: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
        SectionCard(
          title: 'Device',
          child: info == null
              ? const Text('Not read yet')
              : KvList([
                  ('Manufacturer', info.manufacturer),
                  ('Device', info.deviceName),
                  ('Chemistry', '${info.chemistry} (ID ${hex(info.chemId, 4)})'),
                  ('Device type', hex(info.deviceType, 4)),
                  ('Serial', '${info.serialNumber}'),
                  ('Design', '${info.designCapacityMah} mAh @ ${info.designVoltageMv} mV'),
                  ('Manufactured', info.manufactureDateText),
                  ('Cells', '${info.cellCount}S'),
                  ('Mfg Status Init',
                      info.mfgStatusInitValid ? hex(info.mfgStatusInit, 4) : 'unreadable'),
                  ('Enabled Protections C',
                      info.protCValid ? hex(info.enabledProtectionsC, 2) : 'unreadable'),
                ]),
        ),
        if (x == null)
          const SectionCard(title: 'Impedance Track', child: Text('Not read yet'))
        else ...[
          SectionCard(
            title: 'Impedance Track',
            child: KvList([
              ('QMax mAh', perCell(x.qmaxMah)),
              ('RaScale', perCell(x.raScale)),
              ('DOD0', perCell(x.dod0)),
              ('DOD at EOC', perCell(x.dodEoc)),
              ('Cell grid', perCell(x.cellGrid)),
              ('True rem Q / FCC Q', '${x.trueRemQMah} / ${x.trueFccQMah} mAh'),
              ('Filtered rem / FCC', '${x.filtRemainingMah} / ${x.filtFullChargeMah} mAh'),
              ('No-load rem cap', '${x.noLoadRemCapMah} mAh'),
              ('SOH FCC', '${x.sohFccMah} mAh'),
              ('State time', fmtUptime(x.stateTimeS)),
              ('QMax passed Q', '${x.qmaxPassedQMah} mAh'),
            ]),
          ),
          SectionCard(
            title: 'Turbo',
            child: KvList([
              ('Max / sustained power', '${x.maxTurboPowerCw / 100} / ${x.susTurboPowerCw / 100} W'),
              ('Max / sustained current', '${x.maxTurboCurrentMa} / ${x.susTurboCurrentMa} mA'),
              ('Pack / system R', '${x.turboPackRmOhm} / ${x.turboSysRmOhm} mΩ'),
              ('Turbo EDV', '${x.turboEdvMv} mV'),
            ]),
          ),
          SectionCard(
            title: 'Lifetime',
            child: KvList([
              ('Cell max mV', perCell(x.ltCellMaxMv)),
              ('Cell min mV', perCell(x.ltCellMinMv)),
              ('Max Δ cell', '${x.ltMaxDeltaCellMv} mV'),
              ('Max charge / discharge', '${x.ltMaxChargeMa} / ${x.ltMaxDischargeMa} mA'),
              ('Cell temp range', '${x.ltMinTempCellC} … ${x.ltMaxTempCellC} °C'),
              ('Max FET temp', '${x.ltMaxTempFetC} °C'),
              ('Balance time h', perCell(x.ltCbTimeCellH)),
              ('Shutdowns', '${x.ltShutdowns}'),
              ('Resets partial / full / WDT',
                  '${x.ltPartialResets} / ${x.ltFullResets} / ${x.ltWdtResets}'),
            ]),
          ),
        ],
      ]),
    );
  }
}
