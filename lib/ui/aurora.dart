import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Soft blobs of colour drifting over a deep violet ground. [t] runs 0..1
/// in a loop; [energy] 0..1 makes the blobs larger and brighter.
class AuroraPainter extends CustomPainter {
  AuroraPainter(this.t, this.energy, {this.ground = const Color(0xFF2B1D6E)});
  final double t;
  final double energy;
  final Color ground;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = ground);
    const colors = [Color(0xFF8E6BFF), Color(0xFFFF7EB6), Color(0xFFFFB938), Color(0xFF4AC7FF)];
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
