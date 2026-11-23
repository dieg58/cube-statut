// Mode disco : la boule descend du haut de la fenêtre et tourne, des spots balaient le fond.
// Portage de la télécommande web (même dessin à facettes, mêmes couleurs de la charte).
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'theme.dart';

class DiscoLayer extends StatefulWidget {
  const DiscoLayer({super.key, required this.on});
  final bool on;

  @override
  State<DiscoLayer> createState() => _DiscoLayerState();
}

class _DiscoLayerState extends State<DiscoLayer> with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 60));
  late final AnimationController _drop = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    if (widget.on) _start();
  }

  @override
  void didUpdateWidget(DiscoLayer old) {
    super.didUpdateWidget(old);
    if (widget.on != old.on) widget.on ? _start() : _stop();
  }

  bool get _reduceMotion => MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  void _start() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _drop.forward();
      if (!_reduceMotion) _spin.repeat();
    });
  }

  void _stop() {
    _drop.reverse();
    _spin.stop();
  }

  @override
  void dispose() {
    _spin.dispose();
    _drop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: Listenable.merge([_spin, _drop]),
        builder: (context, _) {
          final drop = const Cubic(.3, 1.35, .5, 1).transform(_drop.value);
          final ms = _spin.value * 60000;
          return Stack(children: [
            Positioned.fill(
              child: Opacity(
                opacity: _drop.value.clamp(0, 1),
                child: CustomPaint(painter: _SpotsPainter(ms)),
              ),
            ),
            Positioned(
              top: -200 + 200 * drop,
              left: 0,
              right: 0,
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 1.5, height: 34, color: K.paper),
                  Container(
                    width: 18,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFFAEB8C0),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(2)),
                    ),
                  ),
                  CustomPaint(size: const Size.square(120), painter: _BallPainter(ms)),
                ]),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

double _hash(int a, int b, int c) {
  var h = (a * 374761393 + b * 668265263 + c * 2147483647) & 0xFFFFFFFF;
  h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF;
  return ((h ^ (h >> 16)) & 0xFFFFFFFF) / 4294967295;
}

List<double> _mix(List<double> a, List<double> b, double t) =>
    [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];

const _sky = [86.0, 180.0, 233.0], _amber = [230.0, 159.0, 0.0], _blue = [0.0, 114.0, 178.0], _paperC = [247.0, 245.0, 240.0];

class _BallPainter extends CustomPainter {
  _BallPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, r = w / 2 - 2, cx = w / 2, cy = w / 2;
    final center = Offset(cx, cy);
    canvas.drawCircle(center, r, Paint()..color = K.ink);
    final rot = t * 0.0009;
    const lat = 11;
    const l = [-0.42, -0.62, 0.66];
    final tick = (t / 420).floor();
    List<double> p(double phi, double th) => [math.cos(phi) * math.sin(th), math.sin(phi), math.cos(phi) * math.cos(th)];
    final paint = Paint()..isAntiAlias = true;
    for (var i = 0; i < lat; i++) {
      final p0 = -math.pi / 2 + math.pi * i / lat, p1 = -math.pi / 2 + math.pi * (i + 1) / lat, pm = (p0 + p1) / 2;
      final m = math.max(5, (24 * math.cos(pm)).round());
      for (var j = 0; j < m; j++) {
        final t0 = rot + 2 * math.pi * j / m, t1 = rot + 2 * math.pi * (j + 1) / m, tm = (t0 + t1) / 2;
        final n = p(pm, tm);
        if (n[2] <= 0.02) continue;
        final lit = math.max(0.0, n[0] * l[0] + n[1] * l[1] + n[2] * l[2]);
        var col = _mix([30, 50, 70], [150, 168, 182], math.min(1, 0.15 + lit * 0.95));
        final rr = _hash(i, j, 7);
        if (rr < 0.16) {
          col = _mix(col, _sky, 0.65);
        } else if (rr < 0.30) {
          col = _mix(col, _amber, 0.7);
        } else if (rr < 0.38) {
          col = _mix(col, _blue, 0.6);
        }
        if (lit > 0.9 || _hash(i, j, tick) > 0.955) col = _paperC;
        final q = [p(p0, t0), p(p0, t1), p(p1, t1), p(p1, t0)];
        final path = Path();
        for (var k = 0; k < 4; k++) {
          final c = q[k];
          final x = cx + (c[0] * 0.94 + n[0] * 0.06) * r, y = cy + (c[1] * 0.94 + n[1] * 0.06) * r;
          k == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
        }
        path.close();
        paint.color = Color.fromARGB(255, col[0].toInt(), col[1].toInt(), col[2].toInt());
        canvas.drawPath(path, paint);
      }
    }
    canvas.drawCircle(center, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = K.paper);
  }

  @override
  bool shouldRepaint(_BallPainter old) => old.t != t;
}

class _SpotsPainter extends CustomPainter {
  _SpotsPainter(this.t);
  final double t;
  static const _colors = [K.sky, K.amber, K.paper, K.blue, K.sky, K.amber, K.paper, K.sky, K.amber, K.paper, K.sky, K.amber];

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < _colors.length; i++) {
      final dur = 9000 + (i * 1300) % 7000;
      final phase = ((t + i * 1900) % dur) / dur;
      final x = -0.25 * size.width + phase * 1.5 * size.width;
      final y = ((i * 29) % 92) / 100 * size.height + math.sin(phase * math.pi * 2) * size.height * 0.06 * (i.isOdd ? -1 : 1);
      final radius = 32.0 + (i * 17) % 48;
      final paint = Paint()
        ..color = _colors[i].withValues(alpha: .38)
        ..blendMode = BlendMode.screen
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(_SpotsPainter old) => old.t != t;
}
