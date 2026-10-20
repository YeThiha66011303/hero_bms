import 'package:flutter/material.dart';

import '../ble/bms_connection.dart';
import '../ble/df_catalog.dart';
import '../ble/df_param.dart';
import 'widgets.dart';

/// Every BQStudio Data Memory parameter, by class, read straight from the
/// gauge's data flash. Writable rows open an editor; the firmware rechecks the
/// limits, writes and verifies. Locked rows are view only (see
/// tools/gen_df_catalog.py in the firmware repo for why).
class DataMemoryScreen extends StatefulWidget {
  const DataMemoryScreen(this.c, {super.key});
  final BmsConnection c;

  @override
  State<DataMemoryScreen> createState() => _DataMemoryScreenState();
}

class _DataMemoryScreenState extends State<DataMemoryScreen> {
  BmsConnection get c => widget.c;

  String _class = 'Settings';
  String _filter = '';
  final Map<int, int> _bytes = {}; // data flash address -> byte
  final Set<String> _loaded = {};
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(_class);
  }

  List<DfParam> _params(String cls) => [for (final p in dfParams) if (p.cls == cls) p];

  /// Groups a class's parameters into reads of at most 480 bytes, splitting
  /// where the addresses jump so sparse classes do not drag in big holes.
  static List<(int, int)> _spans(List<DfParam> params) {
    final sorted = [...params]..sort((a, b) => a.addr.compareTo(b.addr));
    final spans = <(int, int)>[];
    var start = -1, end = -1;
    for (final p in sorted) {
      final pEnd = p.addr + p.size;
      if (start < 0 || pEnd - start > 480 || p.addr - end > 64) {
        if (start >= 0) spans.add((start, end - start));
        start = p.addr;
        end = pEnd;
      } else if (pEnd > end) {
        end = pEnd;
      }
    }
    if (start >= 0) spans.add((start, end - start));
    return spans;
  }

  Future<void> _load(String cls, {bool force = false}) async {
    if (!force && _loaded.contains(cls)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      for (final (addr, len) in _spans(_params(cls))) {
        final data = await c.readDataFlash(addr, len);
        for (var i = 0; i < data.length; i++) {
          _bytes[addr + i] = data[i];
        }
      }
      _loaded.add(cls);
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  List<int>? _raw(DfParam p) {
    final out = <int>[];
    for (var i = 0; i < p.size; i++) {
      final b = _bytes[p.addr + i];
      if (b == null) return null;
      out.add(b);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final params = _params(_class)
        .where((p) => _filter.isEmpty || p.name.toLowerCase().contains(_filter.toLowerCase()))
        .toList();
    final subs = <String>[];
    for (final p in params) {
      if (!subs.contains(p.sub)) subs.add(p.sub);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Memory'),
        actions: [
          IconButton(
            tooltip: 'Read again',
            onPressed: _loading ? null : () => _load(_class, force: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              for (final cls in dfClasses)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: ChoiceChip(
                    label: Text(cls),
                    selected: cls == _class,
                    onSelected: (_) {
                      setState(() => _class = cls);
                      _load(cls);
                    },
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: TextField(
            decoration: const InputDecoration(
                isDense: true, prefixIcon: Icon(Icons.search), hintText: 'Filter by name'),
            onChanged: (v) => setState(() => _filter = v),
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_error!, style: const TextStyle(color: BmsColors.bad)),
          ),
        Expanded(
          child: ListView(padding: const EdgeInsets.only(bottom: 16), children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Advanced. Apart from the curated Settings, the firmware only enforces TI\'s '
                'limits, which for most parameters is the full range of the number. '
                'Save a BQStudio export before changing anything here.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            for (final sub in subs)
              SectionCard(
                title: sub,
                child: Column(children: [
                  for (final p in params.where((p) => p.sub == sub)) _row(context, p),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _row(BuildContext context, DfParam p) {
    final t = Theme.of(context);
    final raw = _raw(p);
    final value = raw == null ? '…' : '${p.format(raw)} ${p.displayUnit}'.trim();
    final editable = p.writable && raw != null;
    return InkWell(
      onTap: editable ? () => _edit(p, p.decode(raw!)) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Expanded(child: Text(p.name, style: t.textTheme.bodyMedium)),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: t.textTheme.bodyMedium
                    ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          const SizedBox(width: 6),
          Icon(p.writable ? Icons.edit : Icons.lock_outline,
              size: 16, color: t.colorScheme.onSurfaceVariant),
        ]),
      ),
    );
  }

  Future<void> _edit(DfParam p, int current) async {
    final next = await showDialog<int>(
      context: context,
      builder: (_) => _DfEditDialog(param: p, current: current),
    );
    if (next == null || next == current || !mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Write ${p.name}?'),
        content: Text('${p.cls} / ${p.sub}\n'
            '${p.formatRaw(current)} → ${p.formatRaw(next)} ${p.displayUnit}\n\n'
            'The gauge stores this in data flash and uses it immediately.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Write')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await c.writeDataFlash(p.addr, next);
      final data = await c.readDataFlash(p.addr, p.size);
      for (var i = 0; i < data.length; i++) {
        _bytes[p.addr + i] = data[i];
      }
      messenger.showSnackBar(SnackBar(content: Text('${p.name} written and verified.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          backgroundColor: BmsColors.bad,
          content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
    if (mounted) setState(() {});
  }
}

class _DfEditDialog extends StatefulWidget {
  const _DfEditDialog({required this.param, required this.current});
  final DfParam param;
  final int current;

  @override
  State<_DfEditDialog> createState() => _DfEditDialogState();
}

class _DfEditDialogState extends State<_DfEditDialog> {
  late final _text = TextEditingController(text: widget.param.formatRaw(widget.current));
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final p = widget.param;
    final raw = p.parse(_text.text);
    String? err;
    if (raw == null) {
      err = p.isHex ? 'Enter a hex value, e.g. 0x2D' : 'Enter a number';
    } else if (p.min != null && p.max != null && (raw < p.min! || raw > p.max!)) {
      err = 'Allowed: ${p.limitText}';
    }
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    Navigator.pop(context, raw);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.param;
    return AlertDialog(
      title: Text(p.name),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${p.cls} / ${p.sub} · 0x${p.addr.toRadixString(16).toUpperCase()} · ${p.type}'),
        if (p.defaultText.isNotEmpty) Text('TI default: ${p.defaultText} ${p.unit}'.trim()),
        const SizedBox(height: 12),
        TextField(
          controller: _text,
          autofocus: true,
          keyboardType: p.isHex
              ? TextInputType.text
              : TextInputType.numberWithOptions(signed: p.isSigned || p.isKelvin, decimal: p.isKelvin),
          decoration: InputDecoration(
            suffixText: p.displayUnit,
            helperText: p.limitText.isEmpty ? null : 'Allowed: ${p.limitText}',
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
