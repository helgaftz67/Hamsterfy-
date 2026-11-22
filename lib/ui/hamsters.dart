import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// The Hamsterfy mascots, made of glass, as a living scene: a vinyl record spins like a
/// hamster wheel while the white and the black hamster nod to the beat in
/// their headphones, blink now and then, and send notes drifting up.
class HamsterScene extends StatefulWidget {
  const HamsterScene({super.key});

  @override
  State<HamsterScene> createState() => _HamsterSceneState();
}

class _HamsterSceneState extends State<HamsterScene> with SingleTickerProviderStateMixin {
  // One loop is eight beats; everything in the painter derives from it.
  late final _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 5600))..repeat();

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'Два хомяка в наушниках слушают пластинку',
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _loop,
          builder: (_, _) => CustomPaint(painter: HamsterPainter(_loop.value), size: Size.infinite),
        ),
      ),
    );
  }
}

class _Fur {
  const _Fur({
    required this.fur,
    required this.muzzle,
    required this.earIn,
    required this.eye,
    required this.blush,
    required this.nose,
    required this.phones,
    this.eyeRing,
  });
  final Color fur, muzzle, earIn, eye, blush, nose, phones;
  final Color? eyeRing;
}

const _white = _Fur(
  fur: Color(0xFFFDFBFF),
  muzzle: Color(0xFFFFFFFF),
  earIn: Color(0xFFFFC6D4),
  eye: Color(0xFF221D32),
  blush: Color(0xFFFFA0B8),
  nose: Color(0xFFF07896),
  phones: Color(0xFF221D32),
);

const _black = _Fur(
  fur: Color(0xFF221D32),
  muzzle: Color(0xFF3E3756),
  earIn: Color(0xFF9A7896),
  eye: Color(0xFF141020),
  blush: Color(0xFFC77A9C),
  nose: Color(0xFFFFB0C4),
  phones: Color(0xFFFCFAFF),
  eyeRing: Color(0xFFFAF8FF),
);

class HamsterPainter extends CustomPainter {
  HamsterPainter(this.t);

  /// Position in the loop, 0..1.
  final double t;

  static const _beats = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final unit = math.min(w, h * 1.15);
    final beat = t * _beats;
    // 0 at the top of the nod, 1 at the bottom, once per beat.
    double nod(double offset) => (1 - math.cos((beat + offset) * 2 * math.pi)) / 2;

    final record = Offset(w / 2, h * .44);
    _record(canvas, record, unit * .40, t * 2 * math.pi * 3);
    _notes(canvas, w, h, unit);

    final s = unit * .165;
    final ground = h * .70;
    _hamster(canvas, Offset(w / 2 + s * 1.12, ground - s * .10 + s * .12 * nod(.5)), s, _black,
        tilt: .10 - .05 * nod(.5), blink: _blinking(1.9));
    _hamster(canvas, Offset(w / 2 - s * 1.12, ground + s * .12 * nod(0)), s, _white,
        tilt: -.10 + .05 * nod(0), blink: _blinking(.4));
  }

  /// Each hamster closes its eyes for a moment twice per loop.
  bool _blinking(double at) {
    final beat = (t * _beats - at) % 4;
    return beat >= 0 && beat < .16;
  }

  void _record(Canvas canvas, Offset c, double r, double angle) {
    canvas.drawCircle(c + Offset(0, r * .06), r, Paint()
      ..color = const Color(0x66000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * .12));
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF14111F));
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * .008
      ..color = const Color(0x22FFFFFF);
    for (var i = 0; i < 9; i++) {
      canvas.drawCircle(c, r * (.46 + i * .058), groove);
    }
    // Two soft glints sweep round with the record, so the spin is visible.
    final glint = Paint()
      ..shader = SweepGradient(
        transform: GradientRotation(angle),
        colors: const [
          Color(0x00FFFFFF), Color(0x38FFFFFF), Color(0x00FFFFFF), Color(0x00FFFFFF),
          Color(0x2AFFFFFF), Color(0x00FFFFFF), Color(0x00FFFFFF),
        ],
        stops: const [0, .06, .14, .5, .56, .64, 1],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, glint);
    // Label with a notch that turns.
    canvas.drawCircle(c, r * .36, Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF7B594), Color(0xFFE5622B)],
      ).createShader(Rect.fromCircle(center: c, radius: r * .36)));
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(r * .10, -r * .035, r * .20, r * .07), Radius.circular(r * .035)),
      Paint()..color = kCream,
    );
    canvas.restore();
    canvas.drawCircle(c, r * .045, Paint()..color = const Color(0xFF14111F));
  }

  void _notes(Canvas canvas, double w, double h, double unit) {
    const lanes = [(-.34, 0.0, 1.0, kAccent), (.36, .37, .8, kAmber), (-.08, .68, .7, Colors.white), (.16, .15, .6, kRose)];
    for (final (x, phase, scale, color) in lanes) {
      final p = (t * 2 + phase) % 1;
      final rise = Curves.easeOut.transform(p);
      final center = Offset(
        w / 2 + x * unit + math.sin((p + phase) * 2 * math.pi) * unit * .03,
        h * .34 - rise * h * .30,
      );
      final alpha = (p < .15 ? p / .15 : (1 - p) / .85).clamp(0.0, 1.0);
      _note(canvas, center, unit * .085 * scale, color.withValues(alpha: alpha));
    }
  }

  void _note(Canvas canvas, Offset c, double k, Color color) {
    final paint = Paint()..color = color;
    canvas.drawOval(Rect.fromCenter(center: c, width: k * .56, height: k * .42), paint);
    canvas.drawLine(
      c + Offset(k * .22, 0),
      c + Offset(k * .22, -k * .86),
      Paint()
        ..color = color
        ..strokeWidth = k * .11
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      Path()
        ..moveTo(c.dx + k * .22, c.dy - k * .86)
        ..lineTo(c.dx + k * .64, c.dy - k * .60)
        ..lineTo(c.dx + k * .64, c.dy - k * .38)
        ..lineTo(c.dx + k * .22, c.dy - k * .62)
        ..close(),
      paint,
    );
  }

  /// Paints [shape] as a piece of glass: a translucent body that lets the
  /// backdrop through, a pool of warm light at the bottom, a soft sheen
  /// and a sharp glint at the top-left, and a bright rim.
  void _glass(Canvas canvas, Path shape, Rect box, Color top, Color bottom, {double rim = .8, double sheen = .5}) {
    canvas.drawPath(
      shape,
      Paint()
        ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, bottom])
            .createShader(box),
    );
    canvas.save();
    canvas.clipPath(shape);
    // Light from the sunset pooling inside the lower part.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(box.center.dx, box.bottom), width: box.width * 1.1, height: box.height * .7),
      Paint()
        ..color = const Color(0x40F2A07A)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, box.height * .12),
    );
    // Soft sheen across the upper left.
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(box.left + box.width * .34, box.top + box.height * .22),
          width: box.width * .62,
          height: box.height * .34),
      Paint()
        ..color = Colors.white.withValues(alpha: sheen)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, box.height * .09),
    );
    canvas.restore();
    // Rim: brightest where the light comes from.
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = box.width * .012
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: rim),
            Colors.white.withValues(alpha: rim * .18),
            Colors.white.withValues(alpha: rim * .45),
          ],
          stops: const [0, .55, 1],
        ).createShader(box),
    );
  }

  void _hamster(Canvas canvas, Offset c, double s, _Fur f, {required double tilt, required bool blink}) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(tilt);
    Rect ovalRect(double x, double y, double rx, double ry) =>
        Rect.fromCenter(center: Offset(x * s, y * s), width: rx * 2 * s, height: ry * 2 * s);
    void oval(double x, double y, double rx, double ry, Color color) =>
        canvas.drawOval(ovalRect(x, y, rx, ry), Paint()..color = color);
    Path ovalPath(double x, double y, double rx, double ry) => Path()..addOval(ovalRect(x, y, rx, ry));
    Path join(Path a, Path b) => Path.combine(PathOperation.union, a, b);

    // The white one is clear frosted glass, the black one smoked glass.
    final dark = f.eyeRing != null;
    final top = dark ? const Color(0xB8221C2C) : const Color(0xC7FFFFFF);
    final bottom = dark ? const Color(0x80120E18) : const Color(0x66FFFFFF);
    final rim = dark ? .55 : .95;
    final sheen = dark ? .22 : .55;

    // Soft shadow on the ground.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(0, s * 1.42), width: s * 2.3, height: s * .5),
      Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * .16),
    );

    // Body, head and cheeks are one piece of glass: joined into a single
    // outline so the overlaps do not show as seams.
    var body = ovalPath(0, 1.02, .92, .62);
    body = join(body, ovalPath(0, 0, .98, .88));
    for (final sx in [-1.0, 1.0]) {
      body = join(body, ovalPath(sx * .60, .34, .50, .42));
    }
    _glass(canvas, body, Rect.fromLTRB(-1.1 * s, -.88 * s, 1.1 * s, 1.64 * s), top, bottom, rim: rim, sheen: sheen);
    // A sharp glint, the mark of something glossy.
    oval(-.50, -.52, .16, .075, Colors.white.withValues(alpha: dark ? .55 : .9));
    oval(-.28, -.66, .05, .035, Colors.white.withValues(alpha: dark ? .45 : .8));

    // Paws and muzzle: slightly denser glass.
    for (final sx in [-1.0, 1.0]) {
      oval(sx * .34, .98, .17, .12, f.muzzle.withValues(alpha: dark ? .55 : .5));
    }
    oval(0, .40, .40, .28, f.muzzle.withValues(alpha: dark ? .5 : .45));

    // Headphones: a glossy band over the head, glass cups on the sides.
    final bandRect = Rect.fromCenter(center: Offset.zero, width: s * 2.08, height: s * 1.94);
    canvas.drawArc(
      bandRect,
      192 * math.pi / 180,
      156 * math.pi / 180,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * .14
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(f.phones, Colors.white, .35)!, f.phones.withValues(alpha: .85)],
        ).createShader(bandRect),
    );
    for (final sx in [-1.0, 1.0]) {
      final cup = Rect.fromLTRB((sx * 1.02 - .19) * s, -.30 * s, (sx * 1.02 + .19) * s, .34 * s);
      final cupPath = Path()..addRRect(RRect.fromRectAndRadius(cup, Radius.circular(s * .17)));
      _glass(canvas, cupPath, cup, f.phones.withValues(alpha: .92), f.phones.withValues(alpha: .70), rim: .7, sheen: .3);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTRB((sx * 1.02 - .08) * s, -.16 * s, (sx * 1.02 + .08) * s, .20 * s), Radius.circular(s * .07)),
        Paint()..color = kCream,
      );
    }
    // Ears peek out in front of the band, each its own bead of glass.
    for (final sx in [-1.0, 1.0]) {
      final ear = ovalRect(sx * .60, -.72, .23, .23);
      _glass(canvas, Path()..addOval(ear), ear, top, bottom, rim: rim, sheen: sheen * .8);
      oval(sx * .60, -.70, .125, .125, f.earIn.withValues(alpha: .85));
    }
    // Eyes: glossy when open, a happy curve when blinking.
    for (final sx in [-1.0, 1.0]) {
      final ex = sx * .40, ey = .08;
      if (blink) {
        canvas.drawArc(
          Rect.fromCenter(center: Offset(ex * s, (ey + .03) * s), width: s * .28, height: s * .16),
          math.pi,
          math.pi,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * .05
            ..strokeCap = StrokeCap.round
            ..color = f.eyeRing ?? f.eye,
        );
        continue;
      }
      if (f.eyeRing != null) oval(ex, ey, .17, .195, f.eyeRing!);
      oval(ex, ey, .135, .16, f.eye);
      oval(ex + .045, ey - .06, .05, .05, Colors.white);
      oval(ex - .045, ey + .06, .025, .025, Colors.white);
    }
    for (final sx in [-1.0, 1.0]) {
      oval(sx * .64, .36, .15, .09, f.blush.withValues(alpha: .85));
    }
    // Tiny nose and smile.
    oval(0, .27, .06, .045, f.nose);
    final mouth = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * .034
      ..strokeCap = StrokeCap.round
      ..color = f.nose;
    for (final sx in [-1.0, 1.0]) {
      canvas.drawArc(
        Rect.fromLTRB((sx - 1) * .075 * s, .26 * s, (sx + 1) * .075 * s, .42 * s),
        0,
        math.pi,
        false,
        mouth,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(HamsterPainter old) => old.t != t;
}
