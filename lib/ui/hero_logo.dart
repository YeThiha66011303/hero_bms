import 'package:flutter/material.dart';

/// Hero BMS brand colours (H1 "Bolt H").
class HeroColors {
  static const navy = Color(0xFF0F1C2B);
  static const navyRaised = Color(0xFF1A2B3F);
  static const green = Color(0xFF2ED47A);
}

/// The H1 "Bolt H" mark: two white bars, green bolt for the crossbar.
///
/// Geometry is in 0..1 tile units and must match tool/make_icons.py, which
/// draws the launcher icons from the same numbers.
class HeroLogo extends StatelessWidget {
  const HeroLogo({super.key, this.size = 96, this.tile = HeroColors.navyRaised});

  final double size;
  final Color tile;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _HeroLogoPainter(tile));
}

class _HeroLogoPainter extends CustomPainter {
  _HeroLogoPainter(this.tile);
  final Color tile;

  static const _bars = [
    Rect.fromLTRB(0.236, 0.196, 0.389, 0.804),
    Rect.fromLTRB(0.611, 0.196, 0.764, 0.804),
  ];
  static const _barRadius = 0.045;
  static const _bolt = [
    [Offset(0.389, 0.418), Offset(0.565, 0.418), Offset(0.525, 0.492), Offset(0.389, 0.492)],
    [Offset(0.475, 0.492), Offset(0.611, 0.492), Offset(0.611, 0.566), Offset(0.435, 0.566)],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(0.22 * s)),
      Paint()..color = tile,
    );
    final white = Paint()..color = Colors.white;
    for (final r in _bars) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTRB(r.left * s, r.top * s, r.right * s, r.bottom * s),
            Radius.circular(_barRadius * s)),
        white,
      );
    }
    final green = Paint()..color = HeroColors.green;
    for (final poly in _bolt) {
      canvas.drawPath(Path()..addPolygon([for (final p in poly) p * s], true), green);
    }
  }

  @override
  bool shouldRepaint(_HeroLogoPainter old) => old.tile != tile;
}
