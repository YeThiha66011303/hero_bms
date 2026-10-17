import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ble/bms_connection.dart';
import '../ble/bms_protocol.dart';
import '../ble/bms_settings.dart';
import 'widgets.dart';

/// Reads and writes the whitelisted data flash settings (firmware
/// main/df_settings.cpp). Every change goes value dialog -> confirm -> write
/// -> firmware read-back -> settings re-read.
class SettingsTab extends StatefulWidget {
  const SettingsTab(this.c, {super.key});
  final BmsConnection c;

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  BmsConnection get c => widget.c;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (c.settings == null) _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    await c.refreshSettings();
    if (mounted) setState(() => _loading = false);
  }

  bool get _sealed => c.live?.securityMode == 3;

  @override
  Widget build(BuildContext context) {
    if (!c.settingsSupported) {
      return const _Message('This ESP32 firmware has no settings support. '
          'Flash the latest firmware to change data flash values from the app.');
    }
    final s = c.settings;
    if (s == null) {
      return _loading
          ? const Center(child: CircularProgressIndicator())
          : _Message('Could not read the settings.', action: ('Retry', _refresh));
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
        SectionCard(
          title: 'Data flash',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Changes are written straight to the gauge and stay after a reset. '
                'Before your first change, save a backup in BQStudio '
                '(Data Memory → Export).'),
            if (_sealed) ...[
              const SizedBox(height: 8),
              const Text('The gauge is SEALED: it will refuse writes until it is unsealed.',
                  style: TextStyle(color: BmsColors.bad)),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _copy(s),
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy current values'),
              ),
            ),
          ]),
        ),
        for (final group in settingGroups)
          SectionCard(
            title: group,
            child: Column(children: [
              for (final d in settingDefs.where((d) => d.group == group))
                _row(context, d, s.values[d.id]),
            ]),
          ),
      ]),
    );
  }

  Widget _row(BuildContext context, SettingDef d, int? raw) {
    final t = Theme.of(context);
    final value = raw == null ? 'unreadable' : '${d.format(raw)} ${d.unit}'.trim();
    return InkWell(
      onTap: raw == null ? null : () => _edit(d, raw),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Expanded(child: Text(d.name, style: t.textTheme.bodyMedium)),
          Text(value,
              style: t.textTheme.bodyMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: raw == null ? BmsColors.bad : null)),
          const SizedBox(width: 6),
          Icon(Icons.edit, size: 16, color: t.colorScheme.onSurfaceVariant),
        ]),
      ),
    );
  }

  Future<void> _copy(SettingsData s) async {
    final lines = [
      'Hero BMS data flash settings, ${DateTime.now().toIso8601String()}',
      for (final d in settingDefs)
        '${d.name}: ${s.values[d.id] == null ? 'unreadable' : '${d.format(s.values[d.id]!)} ${d.unit}'.trim()}',
    ];
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Settings copied to the clipboard')));
    }
  }

  Future<void> _edit(SettingDef d, int current) async {
    final Map<int, int?> values = c.settings?.values ?? const {};
    final next = d.kind == SettingKind.bits
        ? await showDialog<int>(
            context: context, builder: (_) => _BitsDialog(def: d, current: current))
        : await showDialog<int>(
            context: context,
            builder: (_) => _NumberDialog(def: d, current: current, values: values));
    if (next == null || next == current || !mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Write ${d.name}?'),
        content: Text('${d.format(current)} → ${d.format(next)} ${d.unit}\n\n'
            'The gauge stores this in data flash and uses it immediately.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Write')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text('Writing ${d.name}…')));
    try {
      await c.writeSetting(d.id, next);
      messenger.showSnackBar(SnackBar(
          content: Text('${d.name} set to ${d.format(next)} ${d.unit}, verified.'.trim())));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          backgroundColor: BmsColors.bad,
          content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
    if (mounted) setState(() {});
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.action});
  final String text;
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(text, textAlign: TextAlign.center),
            if (action != null)
              TextButton(onPressed: action!.$2, child: Text(action!.$1)),
          ]),
        ),
      );
}

class _NumberDialog extends StatefulWidget {
  const _NumberDialog({required this.def, required this.current, required this.values});
  final SettingDef def;
  final int current;
  final Map<int, int?> values;

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  late final _text = TextEditingController(text: widget.def.format(widget.current));
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final d = widget.def;
    final raw = d.parse(_text.text);
    final err = raw == null ? 'Enter a number' : validateSetting(d, raw, widget.values);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    Navigator.pop(context, raw);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.def;
    return AlertDialog(
      title: Text(d.name),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (d.help != null) ...[Text(d.help!), const SizedBox(height: 12)],
        TextField(
          controller: _text,
          autofocus: true,
          keyboardType: TextInputType.numberWithOptions(
              signed: d.kind == SettingKind.tempK, decimal: d.kind == SettingKind.tempK),
          decoration: InputDecoration(
            suffixText: d.unit,
            helperText: 'Allowed: ${d.limitText}',
            errorText: _error,
          ),
          onSubmitted: (_) => _submit(),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Next')),
      ],
    );
  }
}

class _BitsDialog extends StatefulWidget {
  const _BitsDialog({required this.def, required this.current});
  final SettingDef def;
  final int current;

  @override
  State<_BitsDialog> createState() => _BitsDialogState();
}

class _BitsDialogState extends State<_BitsDialog> {
  late int _value = widget.current;

  @override
  Widget build(BuildContext context) {
    final d = widget.def;
    final protections = d.group == 'Enabled protections';
    final turnedOff = [
      for (var b = 0; b < 8; b++)
        if (protections && (d.mask >> b) & 1 == 1 && (widget.current >> b) & 1 == 1 &&
            (_value >> b) & 1 == 0)
          d.bits[b]!,
    ];

    return AlertDialog(
      title: Text(d.name),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(shrinkWrap: true, children: [
          if (d.help != null) Text(d.help!),
          for (var b = 0; b < 8; b++)
            if ((d.mask >> b) & 1 == 1 && d.bits[b] != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(d.bits[b]!),
                subtitle: Text(_describe(d.bits[b]!)),
                value: (_value >> b) & 1 == 1,
                onChanged: (on) => setState(() => _value = on ? _value | (1 << b) : _value & ~(1 << b)),
              ),
          if (turnedOff.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Turning off ${turnedOff.join(', ')} removes that protection. '
                  'The pack will no longer stop for it.',
                  style: const TextStyle(color: BmsColors.bad)),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _value), child: const Text('Next')),
      ],
    );
  }

  static String _describe(String bit) =>
      balancingBitDescriptions[bit] ?? flagDescriptions[bit] ?? '';
}
