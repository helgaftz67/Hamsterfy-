import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Soft blobs of sunset colour drifting over a deep dusk ground. [t] runs 0..1
/// in a loop; [energy] 0..1 makes the blobs larger and brighter.
class AuroraPainter extends CustomPainter {
  AuroraPainter(this.t, this.energy, {this.ground = const Color(0xFF1B1C2E)});
  final double t;
  final double energy;
  final Color ground;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = ground);
    const colors = [Color(0xFF55628C), Color(0xFF8C6A92), Color(0xFFF2A07A), Color(0xFFF2733A)];
    final unit = math.min(size.width, size.height);
    for (var i = 0; i < colors.length; i++) {
      final a = (t + i / colors.length) * 2 * math.pi;
      final center = Offset(
        size.width * (.5 + .42 * math.cos(a + i * 1.3)),
        size.height * (.5 + .46 * math.sin(a * (i.isEven ? 1 : -1) + i)),
      );
      final radius = unit * (.42 + .1 * math.sin(a * 2 + i)) * (.85 + .3 * energy);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = colors[i].withValues(alpha: .50 + .25 * energy)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, unit * .17),
      );
    }
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x55000000), Color(0x00000000)],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(AuroraPainter old) => old.t != t || old.energy != energy;
}

/// Full-size animated aurora that fades into [fadeTo] at the bottom, so
/// content placed over the lower part stays readable.
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({super.key, required this.fadeTo, this.fadeFrom = .35});
  final Color fadeTo;
  final double fadeFrom;

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground> with SingleTickerProviderStateMixin {
  late final _drift = AnimationController(vsync: this, duration: const Duration(seconds: 16))..repeat();

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _drift,
            builder: (_, _) => CustomPaint(painter: AuroraPainter(_drift.value, .8)),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [widget.fadeTo.withValues(alpha: 0), widget.fadeTo],
              stops: [widget.fadeFrom, .78],
            ),
          ),
        ),
      ],
    );
  }
}

/// A sunset in a card: slate blue falling through mauve to peach, an
/// orange glow at the bottom with the dark of the horizon in it, and a
/// dotted sound wave drifting across the middle.
class DuskPainter extends CustomPainter {
  DuskPainter(this.t, this.energy);

  /// Position in the loop, 0..1.
  final double t;

  /// 0..1: how lively the wave is (higher while music plays).
  final double energy;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF4A5479), Color(0xFF6F6688), Color(0xFFB98285), Color(0xFFF0966A), Color(0xFFF26E2E)],
          stops: [0, .34, .62, .84, 1],
        ).createShader(rect),
    );
    // The horizon: a soft dark ellipse sitting in the glow.
    final horizon = Rect.fromCenter(
      center: Offset(size.width * .5, size.height * .97),
      width: size.width * .62,
      height: size.height * .20,
    );
    canvas.drawOval(
      horizon,
      Paint()
        ..color = const Color(0xCC1A0F0C)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.height * .06),
    );
    // Dotted wave: columns of dots whose height follows two slow sines.
    final dot = Paint()..color = Colors.white.withValues(alpha: .55 + .3 * energy);
    const columns = 46;
    final left = size.width * .12, span = size.width * .76;
    final mid = size.height * .60;
    final step = size.height * .028;
    for (var i = 0; i < columns; i++) {
      final x = left + span * i / (columns - 1);
      final a = i / columns * math.pi * 2;
      final shape = math.sin(a * 3 + t * math.pi * 2) * .5 + math.sin(a * 7 - t * math.pi * 4) * .3;
      final envelope = math.sin(i / (columns - 1) * math.pi);
      final half = (1 + (shape.abs() * 4 * envelope * (.55 + .45 * energy))).round();
      for (var k = -half; k <= half; k++) {
        final fade = 1 - (k.abs() / (half + 1));
        canvas.drawCircle(Offset(x, mid + k * step), size.height * .0058, dot..color = Colors.white.withValues(alpha: (.25 + .6 * fade) * (.6 + .4 * energy)));
      }
    }
  }

  @override
  bool shouldRepaint(DuskPainter old) => old.t != t || old.energy != energy;
}
