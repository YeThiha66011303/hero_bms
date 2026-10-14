import 'package:flutter/material.dart';

import 'hero_logo.dart';

/// Start-up animation:
///   1. "Health / Estimated / Resistance / Optimized / BMS" fade in, one line
///      at a time, with the initials H E R O in green.
///   2. Everything except H, E, R, O and BMS fades away.
///   3. The remaining letters slide together into "HERO BMS" and the logo
///      appears above it.
/// Then it fades into [next]. A tap skips straight there.
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key, required this.next});

  final WidgetBuilder next;

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> with SingleTickerProviderStateMixin {
  static const _words = [
    ('H', 'ealth'),
    ('E', 'stimated'),
    ('R', 'esistance'),
    ('O', 'ptimized'),
  ];
  static const _fontSize = 30.0;
  static const _lineHeight = _fontSize * 1.35;
  static const _endScale = 1.3;
  static const _logoSize = 96.0;
  static const _gapW = _fontSize * 0.4;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3800),
  )..forward().whenComplete(_go);

  bool _left = false;

  void _go() {
    if (_left || !mounted) return;
    _left = true;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 500),
      pageBuilder: (context, _, _) => widget.next(context),
      transitionsBuilder: (context, a, _, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static TextStyle _style(double scale, Color color) => TextStyle(
        fontSize: _fontSize * scale,
        height: 1.0,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5 * scale,
        color: color,
      );

  static double _width(String s) => (TextPainter(
        text: TextSpan(text: s, style: _style(1, Colors.white)),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      )..layout())
          .width;

  // Measured once; the font does not change while the intro runs.
  late final List<double> _initialW = [for (final (i, _) in _words) _width(i)];
  late final List<double> _restW = [for (final (_, r) in _words) _width(r)];
  late final double _bmsW = _width('BMS');

  /// 0..1 progress of [t] through the window [a, b].
  static double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HeroColors.navy,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _go,
        child: LayoutBuilder(
          builder: (context, box) => AnimatedBuilder(
            animation: _c,
            builder: (context, _) => _frame(box.biggest, _c.value),
          ),
        ),
      ),
    );
  }

  Widget _frame(Size size, double t) {
    // Timeline (fractions of the whole run).
    double enter(int line) => Curves.easeOut.transform(_seg(t, 0.03 + line * 0.06, 0.20 + line * 0.06));
    final fade = Curves.easeIn.transform(_seg(t, 0.46, 0.58));
    final move = Curves.easeInOutCubic.transform(_seg(t, 0.58, 0.80));
    final logo = _seg(t, 0.78, 0.92);
    final scale = 1 + (_endScale - 1) * move;

    // Start: five left-aligned lines, the block centred on screen.
    var blockW = _bmsW;
    for (var i = 0; i < _words.length; i++) {
      blockW = blockW > _initialW[i] + _restW[i] ? blockW : _initialW[i] + _restW[i];
    }
    final startLeft = (size.width - blockW) / 2;
    final startTop = (size.height - 5 * _lineHeight) / 2;

    // End: "HERO BMS" on one line, a little below centre to leave room for
    // the logo. Positions are laid out at scale 1 and then scaled about
    // [pivot], which is where the line ends up centred.
    final pivot = Offset(size.width / 2, size.height / 2 + 48);
    final endW = _initialW.fold<double>(0, (a, b) => a + b) + _gapW + _bmsW;
    final endTop = pivot.dy - _fontSize / 2;
    final endX = <double>[];
    var x = pivot.dx - endW / 2;
    for (final w in _initialW) {
      endX.add(x);
      x += w;
    }
    final bmsEndX = x + _gapW;

    Offset place(Offset from, Offset to, double dy) {
      final p = Offset.lerp(from, to, move)!.translate(0, dy);
      return pivot + (p - pivot) * scale;
    }

    Widget glyph(String s, Offset at, Color color, double opacity) => Positioned(
          left: at.dx,
          top: at.dy,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Text(s, textScaler: TextScaler.noScaling, style: _style(scale, color)),
          ),
        );

    final children = <Widget>[];
    for (var i = 0; i < _words.length; i++) {
      final (initial, rest) = _words[i];
      final e = enter(i);
      final dy = (1 - e) * 14;
      final lineTop = startTop + i * _lineHeight;
      children.add(glyph(rest, Offset(startLeft + _initialW[i], lineTop + dy), Colors.white,
          e * (1 - fade)));
      children.add(glyph(initial, place(Offset(startLeft, lineTop), Offset(endX[i], endTop), dy),
          HeroColors.green, e));
    }
    final eb = enter(4);
    children.add(glyph(
        'BMS',
        place(Offset(startLeft, startTop + 4 * _lineHeight), Offset(bmsEndX, endTop), (1 - eb) * 14),
        Colors.white,
        eb));

    children.add(Positioned(
      left: (size.width - _logoSize) / 2,
      top: pivot.dy - _fontSize * _endScale / 2 - 28 - _logoSize,
      child: Opacity(
        opacity: logo,
        child: Transform.scale(
          scale: 0.6 + 0.4 * Curves.easeOutBack.transform(logo),
          child: const HeroLogo(size: _logoSize),
        ),
      ),
    ));

    return Stack(children: children);
  }
}
