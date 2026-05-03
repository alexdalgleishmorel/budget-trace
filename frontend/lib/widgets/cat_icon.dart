import 'dart:math' as math;
import 'package:flutter/material.dart';

// Lucide-style icon paths mapped to category names (mirrors hifi-icons.jsx)

class BudgetIcons {
  static const _paths = <String, String>{
    'plan':    'M3 3h8v12H3zM13 3h8v7h-8zM13 12h8v9h-8zM3 17h8v4H3z',
    'grid':    'M3 3h8v8H3zM13 3h8v8h-8zM3 13h8v8H3zM13 13h8v8h-8z',
    'expenses':'M4 5h16M4 12h16M4 19h10',
    'results': 'M3 3v18h18M7 16l4-5 3 3 5-7',
    'insights':'M12 3a9 9 0 1 1 0 18A9 9 0 0 1 12 3zM12 7v5l3 2',
    'plus':    'M12 5v14M5 12h14',
    'edit':    'M17 3.5a2.1 2.1 0 1 1 3 3L7.5 19l-4 1 1-4z',
    'close':   'M6 6l12 12M18 6L6 18',
    'check':   'M5 12l5 5 9-11',
    'chevron-right': 'M9 6l6 6-6 6',
    'chevron-down':  'M6 9l6 6 6-6',
    'chevron-left':  'M15 6l-6 6 6 6',
    'chevron-up':    'M18 15l-6-6-6 6',
    'arrow-up':   'M12 19V5M5 12l7-7 7 7',
    'arrow-down': 'M12 5v14M5 12l7 7 7-7',
    'search': 'M20 20l-3.5-3.5',
    'filter': 'M3 5h18M6 12h12M10 19h4',
    'upload': 'M12 16V4M7 9l5-5 5 5M4 20h16',
    'more':   '',
    'alert':  'M12 3l10 18H2zM12 10v5',
    'exclaim': 'M12 4v11',
    'trash':  'M4 7h16M6 7v13a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2V7M9 7V4h6v3M10 11v7M14 11v7',
    'menu':   'M4 6h16M4 12h16M4 18h16',
    'home':   'M3 10l9-7 9 7v11H3zM9 21v-7h6v7',
    'fork':   'M4 4v7a4 4 0 0 0 4 4h0a4 4 0 0 0 4-4V4M8 15v5M18 4v8M18 15v5',
    'piggy':  'M15 5H8a5 5 0 0 0 0 10h.5l1.5 4h3l.5-2H16l1.5 2H20l-1-4a6 6 0 0 0-4-8z',
    'zap':    'M13 3L4 14h7l-1 7 9-11h-7z',
    'wifi':   'M2 8.5a15 15 0 0 1 20 0M5 12a11 11 0 0 1 14 0M8.5 15.5a6 6 0 0 1 7 0',
    'car':    'M5 17h14l-1.5-6a2 2 0 0 0-2-1.5h-7a2 2 0 0 0-2 1.5L5 17z',
    'fuel':   'M14 8h2a2 2 0 0 1 2 2v7a2 2 0 0 0 2 2M7 9h5',
    'cart':   'M3 3h2l2.5 11a2 2 0 0 0 2 1.5h7a2 2 0 0 0 2-1.5L21 7H6.5',
    'sparkle':'M12 3l2 5 5 2-5 2-2 5-2-5-5-2 5-2z',
    'bag':    'M6 7h12l-1 13H7zM9 7a3 3 0 1 1 6 0',
    'shield': 'M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z',
    'hourglass': 'M7 3h10M7 21h10M7 3c0 5 5 5 5 9s-5 4-5 9M17 3c0 5-5 5-5 9s5 4 5 9',
    'plane':  'M10 3l1 6 8 4-8 4-1 6 2-2 6-8-6-8z',
    'music':  'M9 18V5l12-2v13',
    'briefcase': 'M20 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2zM16 7V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v2',
    'heart':  'M12 20s-7-4.5-7-10a4 4 0 0 1 7-2 4 4 0 0 1 7 2c0 5.5-7 10-7 10z',
    'coffee': 'M5 8h12v6a4 4 0 0 1-4 4H9a4 4 0 0 1-4-4zM17 9h2a2 2 0 0 1 0 4h-2M7 4v2M11 4v2',
    'question': 'M9.5 9a2.5 2.5 0 0 1 5 0c0 1.5-2.5 2-2.5 4',
    'sun': 'M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41',
    'moon': 'M21 13A9 9 0 0 1 11 3a7 7 0 1 0 10 10z',
  };

  // Icons that need extra shapes (circles, rects not expressible in a single path)
  static Widget build(String name, {double size = 20, double strokeWidth = 1.75, Color? color}) {
    return _BudgetIconWidget(name: name, size: size, strokeWidth: strokeWidth, color: color);
  }

  static const _catMap = <String, String>{
    'House': 'home', 'Living': 'fork', 'Savings': 'piggy',
    'Unknown': 'question',
    'Car Insurance': 'shield', 'Gas': 'fuel', 'Grocery': 'cart',
    'Fun': 'sparkle', 'Shopping': 'bag', 'Rent': 'home',
    'Utilities': 'zap', 'Internet': 'wifi',
    'Emergency Fund': 'shield', 'Retirement': 'hourglass', 'Travel': 'plane',
    'Subscriptions': 'music', 'Work': 'briefcase', 'Health': 'heart',
    'Cafes': 'coffee',
  };

  static String iconKey(String categoryName) =>
      _catMap[categoryName] ?? 'question';

  static Widget forCategory(String name, {double size = 20, double strokeWidth = 1.75, Color? color}) =>
      build(iconKey(name), size: size, strokeWidth: strokeWidth, color: color);

  static String? path(String name) => _paths[name];
}

class _BudgetIconWidget extends StatelessWidget {
  const _BudgetIconWidget({
    required this.name,
    required this.size,
    required this.strokeWidth,
    this.color,
  });

  final String name;
  final double size;
  final double strokeWidth;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Colors.black;
    return CustomPaint(
      size: Size(size, size),
      painter: _IconPainter(name: name, color: c, strokeWidth: strokeWidth),
    );
  }
}

class _IconPainter extends CustomPainter {
  _IconPainter({required this.name, required this.color, required this.strokeWidth});

  final String name;
  final Color color;
  final double strokeWidth;

  static final _parseCache = <String, Path>{};

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24.0;
    canvas.scale(scale, scale);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth / scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final pathStr = BudgetIcons.path(name) ?? '';
    if (pathStr.isEmpty) {
      // 'more' icon: three circles
      final fp = Paint()..color = color..style = PaintingStyle.fill;
      canvas.drawCircle(const Offset(5, 12), 1, fp);
      canvas.drawCircle(const Offset(12, 12), 1, fp);
      canvas.drawCircle(const Offset(19, 12), 1, fp);
      return;
    }

    final cacheKey = name;
    final path = _parseCache.putIfAbsent(cacheKey, () => parseSvgPath(pathStr));
    canvas.drawPath(path, paint);

    // Extra shapes for specific icons
    if (name == 'search') {
      canvas.drawCircle(const Offset(11, 11), 7, paint);
    } else if (name == 'music') {
      canvas.drawCircle(const Offset(6, 18), 3, paint);
      canvas.drawCircle(const Offset(18, 16), 3, paint);
    } else if (name == 'car') {
      canvas.drawCircle(const Offset(8, 17), 2, paint);
      canvas.drawCircle(const Offset(16, 17), 2, paint);
    } else if (name == 'cart') {
      canvas.drawCircle(const Offset(9, 20), 1, paint);
      canvas.drawCircle(const Offset(18, 20), 1, paint);
    } else if (name == 'results') {
      // Already handled by path
    } else if (name == 'insights') {
      canvas.drawCircle(const Offset(12, 12), 9, paint);
    }

    // Fill dots
    final fp = Paint()..color = color..style = PaintingStyle.fill;
    if (name == 'alert' || name == 'exclaim') {
      canvas.drawCircle(const Offset(12, 19), 1.5, fp);
    } else if (name == 'question') {
      canvas.drawCircle(const Offset(12, 12), 9, paint);
      canvas.drawCircle(const Offset(12, 17), 1.5, fp);
    } else if (name == 'wifi') {
      canvas.drawCircle(const Offset(12, 19), 0.8, fp);
    } else if (name == 'piggy') {
      canvas.drawCircle(const Offset(16, 11), 1.0, fp);
    } else if (name == 'fuel') {
      canvas.drawRect(
        Rect.fromLTWH(5, 4, 9, 17),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth / scale
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.name != name || old.color != color || old.strokeWidth != strokeWidth;
}

// Minimal SVG path parser for M, L, H, V, C, S, Q, Z commands
Path parseSvgPath(String d) {
  final path = Path();
  final tokens = _tokenize(d);
  int i = 0;
  double cx = 0, cy = 0;
  String cmd = 'M';

  while (i < tokens.length) {
    final t = tokens[i];
    if (RegExp(r'^[MmLlHhVvCcSsQqTtAaZz]$').hasMatch(t)) {
      cmd = t;
      i++;
    }
    switch (cmd) {
      case 'M':
        cx = _n(tokens, i); cy = _n(tokens, i + 1); i += 2;
        path.moveTo(cx, cy); cmd = 'L';
      case 'm':
        cx += _n(tokens, i); cy += _n(tokens, i + 1); i += 2;
        path.moveTo(cx, cy); cmd = 'l';
      case 'L':
        cx = _n(tokens, i); cy = _n(tokens, i + 1); i += 2;
        path.lineTo(cx, cy);
      case 'l':
        cx += _n(tokens, i); cy += _n(tokens, i + 1); i += 2;
        path.lineTo(cx, cy);
      case 'H':
        cx = _n(tokens, i); i++;
        path.lineTo(cx, cy);
      case 'h':
        cx += _n(tokens, i); i++;
        path.lineTo(cx, cy);
      case 'V':
        cy = _n(tokens, i); i++;
        path.lineTo(cx, cy);
      case 'v':
        cy += _n(tokens, i); i++;
        path.lineTo(cx, cy);
      case 'C':
        final x1=_n(tokens,i), y1=_n(tokens,i+1), x2=_n(tokens,i+2), y2=_n(tokens,i+3);
        cx = _n(tokens, i+4); cy = _n(tokens, i+5); i += 6;
        path.cubicTo(x1, y1, x2, y2, cx, cy);
      case 'c':
        final x1=cx+_n(tokens,i), y1=cy+_n(tokens,i+1), x2=cx+_n(tokens,i+2), y2=cy+_n(tokens,i+3);
        cx += _n(tokens, i+4); cy += _n(tokens, i+5); i += 6;
        path.cubicTo(x1, y1, x2, y2, cx, cy);
      case 'Q':
        final x1=_n(tokens,i), y1=_n(tokens,i+1);
        cx = _n(tokens, i+2); cy = _n(tokens, i+3); i += 4;
        path.quadraticBezierTo(x1, y1, cx, cy);
      case 'q':
        final x1=cx+_n(tokens,i), y1=cy+_n(tokens,i+1);
        cx += _n(tokens, i+2); cy += _n(tokens, i+3); i += 4;
        path.quadraticBezierTo(x1, y1, cx, cy);
      case 'A':
        final arx=_n(tokens,i), ary=_n(tokens,i+1), axr=_n(tokens,i+2);
        final ala=_n(tokens,i+3)!=0, asw=_n(tokens,i+4)!=0;
        final aex=_n(tokens,i+5), aey=_n(tokens,i+6); i+=7;
        _svgArcTo(path, cx, cy, arx, ary, axr, ala, asw, aex, aey);
        cx=aex; cy=aey;
      case 'a':
        final arx=_n(tokens,i), ary=_n(tokens,i+1), axr=_n(tokens,i+2);
        final ala=_n(tokens,i+3)!=0, asw=_n(tokens,i+4)!=0;
        final aex=cx+_n(tokens,i+5), aey=cy+_n(tokens,i+6); i+=7;
        _svgArcTo(path, cx, cy, arx, ary, axr, ala, asw, aex, aey);
        cx=aex; cy=aey;
      case 'Z': case 'z':
        path.close();
      default:
        i++;
    }
  }
  return path;
}

double _n(List<String> t, int i) =>
    i < t.length ? double.tryParse(t[i]) ?? 0 : 0;

List<String> _tokenize(String d) {
  final out = <String>[];
  final re = RegExp(r'[MmLlHhVvCcSsQqTtAaZz]|[-+]?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?');
  for (final m in re.allMatches(d)) { out.add(m.group(0)!); }
  return out;
}

// ── SVG arc → cubic bezier (SVG spec §F.6.5) ─────────────────────────────────

double _vecAngle(double ux, double uy, double vx, double vy) {
  final len = math.sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy));
  if (len == 0) return 0;
  final a = math.acos(((ux * vx + uy * vy) / len).clamp(-1.0, 1.0));
  return (ux * vy - uy * vx < 0) ? -a : a;
}

void _svgArcTo(Path path, double x1, double y1, double rx, double ry,
    double xRotDeg, bool largeArc, bool sweep, double x2, double y2) {
  if (rx == 0 || ry == 0) { path.lineTo(x2, y2); return; }
  rx = rx.abs(); ry = ry.abs();

  final phi = xRotDeg * math.pi / 180;
  final cosPhi = math.cos(phi), sinPhi = math.sin(phi);

  final dx = (x1 - x2) / 2, dy = (y1 - y2) / 2;
  final x1p =  cosPhi * dx + sinPhi * dy;
  final y1p = -sinPhi * dx + cosPhi * dy;

  var rxSq = rx * rx, rySq = ry * ry;
  final x1pSq = x1p * x1p, y1pSq = y1p * y1p;
  final lambda = x1pSq / rxSq + y1pSq / rySq;
  if (lambda > 1) {
    final s = math.sqrt(lambda);
    rx *= s; ry *= s; rxSq = rx * rx; rySq = ry * ry;
  }

  final den = rxSq * y1pSq + rySq * x1pSq;
  final sq = den == 0 ? 0.0
      : (largeArc == sweep ? -1.0 : 1.0) *
        math.sqrt(math.max(0.0, (rxSq * rySq - rxSq * y1pSq - rySq * x1pSq) / den));
  final cxp = sq * rx * y1p / ry, cyp = -sq * ry * x1p / rx;

  final cxAbs = cosPhi * cxp - sinPhi * cyp + (x1 + x2) / 2;
  final cyAbs = sinPhi * cxp + cosPhi * cyp + (y1 + y2) / 2;

  final theta1 = _vecAngle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry);
  var dTheta = _vecAngle(
    (x1p - cxp) / rx, (y1p - cyp) / ry,
    (-x1p - cxp) / rx, (-y1p - cyp) / ry,
  );
  if (!sweep && dTheta > 0) dTheta -= 2 * math.pi;
  if (sweep  && dTheta < 0) dTheta += 2 * math.pi;

  final nSegs = math.max(1, (dTheta.abs() / (math.pi / 2)).ceil());
  final step = dTheta / nSegs;

  for (int j = 0; j < nSegs; j++) {
    final t1 = theta1 + step * j, t2 = t1 + step;
    final alpha = 4 / 3 * math.tan(step / 4);
    final c1x = rx * (math.cos(t1) - alpha * math.sin(t1));
    final c1y = ry * (math.sin(t1) + alpha * math.cos(t1));
    final c2x = rx * (math.cos(t2) + alpha * math.sin(t2));
    final c2y = ry * (math.sin(t2) - alpha * math.cos(t2));
    final ex  = rx * math.cos(t2), ey = ry * math.sin(t2);
    path.cubicTo(
      cosPhi * c1x - sinPhi * c1y + cxAbs, sinPhi * c1x + cosPhi * c1y + cyAbs,
      cosPhi * c2x - sinPhi * c2y + cxAbs, sinPhi * c2x + cosPhi * c2y + cyAbs,
      cosPhi * ex  - sinPhi * ey  + cxAbs, sinPhi * ex  + cosPhi * ey  + cyAbs,
    );
  }
}
