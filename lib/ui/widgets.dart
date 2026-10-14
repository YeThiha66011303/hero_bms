import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ble/bms_protocol.dart';

/// Status colours used across the app.
class BmsColors {
  static const ok = Color(0xFF2ECC71);
  static const warn = Color(0xFFF5A623);
  static const bad = Color(0xFFE74C3C);
  static const charge = Color(0xFF2ECC71);
  static const discharge = Color(0xFFF5A623);
  static const cellHigh = Color(0xFFE74C3C);
  static const cellLow = Color(0xFF3498DB);
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: Text(title.toUpperCase(),
                    style: t.textTheme.labelMedium?.copyWith(
                        letterSpacing: 1.1, color: t.colorScheme.onSurfaceVariant)),
              ),
              ?trailing,
            ]),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

/// Label / value rows. A null value shows a dash.
class KvList extends StatelessWidget {
  const KvList(this.rows, {super.key});

  final List<(String, String?)> rows;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      children: [
        for (final (k, v) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Expanded(
                  child: Text(k,
                      style: t.textTheme.bodyMedium
                          ?.copyWith(color: t.colorScheme.onSurfaceVariant))),
              Text(v ?? '—',
                  style: t.textTheme.bodyMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ),
      ],
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.unit = '', this.color});

  final String label;
  final String value;
  final String unit;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: t.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(value,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.titleLarge?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 3),
                Text(unit,
                    style: t.textTheme.labelMedium
                        ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Lays children out in a fixed number of equal columns.
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.children, this.columns = 3});

  final List<Widget> children;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      rows.add(Row(children: [
        for (var j = i; j < i + columns; j++) ...[
          if (j > i) const SizedBox(width: 8),
          Expanded(child: j < children.length ? children[j] : const SizedBox()),
        ],
      ]));
      if (i + columns < children.length) rows.add(const SizedBox(height: 8));
    }
    return Column(children: rows);
  }
}

/// On/off indicator, used for FETs and flags.
class StateChip extends StatelessWidget {
  const StateChip(this.label, this.on, {super.key, this.onColor = BmsColors.ok});

  final String label;
  final bool on;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = on ? onColor : t.colorScheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: on ? 0.18 : 0.08),
        border: Border.all(color: c.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(on ? Icons.circle : Icons.circle_outlined, size: 9, color: c),
        const SizedBox(width: 6),
        Text(label, style: t.textTheme.labelMedium?.copyWith(color: on ? c : null)),
      ]),
    );
  }
}

/// State of charge ring.
class SocRing extends StatelessWidget {
  const SocRing({super.key, required this.percent, required this.color, this.size = 150, this.caption});

  final int percent;
  final Color color;
  final double size;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _RingPainter(percent.clamp(0, 100) / 100,
            color, t.colorScheme.surfaceContainerHighest),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$percent%',
                style: t.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700)),
            if (caption != null)
              Text(caption!,
                  style: t.textTheme.labelMedium?.copyWith(color: color)),
          ]),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.fraction, this.color, this.track);

  final double fraction;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arc, math.pi * 0.75, math.pi * 1.5, false, base..color = track);
    if (fraction > 0) {
      canvas.drawArc(arc, math.pi * 0.75, math.pi * 1.5 * fraction, false, base..color = color);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.color != color || old.track != track;
}

/// BQStudio-style bit table, matching the web dashboard: one row per byte,
/// high byte first, Bit7..Bit0 left to right. Red = set, green = clear,
/// grey = reserved.
///
/// Draws [bytes] bytes of [reg] starting at bit [from], so one 32-bit
/// register can be split into the A/B and C/D halves BQStudio shows.
class BitGrid extends StatelessWidget {
  const BitGrid({
    super.key,
    required this.title,
    required this.reg,
    required this.value,
    this.from = 0,
    this.bytes = 2,
  });

  final String title;
  final BitRegister reg;
  final int value;
  final int from, bytes;

  static const _set = Color(0xFFC0392B);
  static const _clear = Color(0xFF1E8449);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final part = (value >> from) & ((1 << (bytes * 8)) - 1);
    return SectionCard(
      title: title,
      trailing: Text(hex(part, bytes * 2),
          style: t.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
      child: Column(children: [
        for (var byte = bytes - 1; byte >= 0; byte--)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(children: [
              for (var b = 7; b >= 0; b--) _cell(t, from + byte * 8 + b),
            ]),
          ),
      ]),
    );
  }

  Widget _cell(ThemeData t, int bit) {
    final name = reg.names[bit];
    final on = (value >> bit) & 1 == 1;
    final bg = name == null ? t.colorScheme.surfaceContainerHighest : (on ? _set : _clear);
    final fg = name == null ? t.colorScheme.outline : Colors.white;
    return Expanded(
      child: Container(
        height: 30,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        alignment: Alignment.center,
        color: bg,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(name ?? 'RSVD',
              style: TextStyle(
                  fontSize: 11,
                  color: fg,
                  fontWeight: on && name != null ? FontWeight.w700 : FontWeight.w400)),
        ),
      ),
    );
  }
}

String fmtDuration(int minutes) {
  // SBS uses 65535 for "not applicable".
  if (minutes >= 65535) return '—';
  final h = minutes ~/ 60, m = minutes % 60;
  return h > 0 ? '${h}h ${m}m' : '${m}m';
}

String fmtUptime(int s) {
  final d = s ~/ 86400, h = (s ~/ 3600) % 24, m = (s ~/ 60) % 60;
  if (d > 0) return '${d}d ${h}h';
  if (h > 0) return '${h}h ${m}m';
  return '${m}m ${s % 60}s';
}

String hex(int v, int digits) => '0x${v.toRadixString(16).toUpperCase().padLeft(digits, '0')}';
