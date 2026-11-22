import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import 'theme.dart';

/// How much room floating chrome (tab bar, mini player) takes at the
/// bottom of a tab. Lists add it to their bottom padding so the last rows
/// can scroll clear of the glass.
double get dockSpace =>
    wideLayout ? (player.current == null ? 0 : 104) : 86 + (player.current == null ? 0 : 70);

/// True while the app is laid out for a wide desktop window: a sidebar
/// and a full-width player bar instead of the bottom tab bar. Set by the
/// shell on every layout.
bool wideLayout = false;

/// Windows at least this wide get the desktop layout.
const double kWideBreakpoint = 900;

/// Drives the slow flow of light inside every sheet of glass. One ticker
/// for the whole app; it is started from `main`, so widget tests (which
/// never start it) see still glass and can settle.
class LiquidClock extends ChangeNotifier {
  Ticker? _ticker;
  double seconds = 0;

  void start() {
    _ticker ??= Ticker((elapsed) {
      seconds = elapsed.inMicroseconds / 1e6;
      notifyListeners();
    })
      ..start();
  }
}

final liquidClock = LiquidClock();

/// Deepens the colours seen through the glass, as real thick glass does.
const _vivid = ColorFilter.matrix(<double>[
  1.28, -.20, -.08, 0, 0, //
  -.08, 1.16, -.08, 0, 0, //
  -.08, -.20, 1.28, 0, 0, //
  0, 0, 0, 1, 0,
]);

/// A sheet of liquid glass: whatever is behind it shows through, blurred
/// and richer in colour; the edge bends light like a lens, and soft
/// highlights drift slowly inside as if the glass were fluid.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 24,
    this.blur = 26,
    this.tint,
    this.strength = 1,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final double radius;
  final double blur;

  /// Colour mixed into the glass, e.g. from the current artwork.
  final Color? tint;

  /// 0..1: how milky the glass is. Lower lets more of the backdrop through.
  final double strength;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    final base = tint ?? const Color(0xFF2B2429);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: .30), blurRadius: 30, offset: const Offset(0, 12)),
          BoxShadow(color: Colors.black.withValues(alpha: .18), blurRadius: 4, offset: const Offset(0, 1)),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.compose(
            outer: _vivid,
            inner: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          ),
          child: CustomPaint(
            foregroundPainter: _LiquidPainter(radius, identityHashCode(this) % 97 / 97),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(base, Colors.white, .26)!.withValues(alpha: .32 * strength),
                    base.withValues(alpha: .22 * strength),
                    Color.lerp(base, Colors.black, .25)!.withValues(alpha: .34 * strength),
                  ],
                ),
              ),
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Everything that makes the sheet read as thick, wet glass: drifting
/// light inside, a lens-like edge, and a rim whose bright spot slowly
/// travels round the outline.
class _LiquidPainter extends CustomPainter {
  _LiquidPainter(this.radius, this.phase) : super(repaint: liquidClock);
  final double radius;

  /// Offsets this sheet's motion so neighbours do not move in step.
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rad = Radius.circular(math.max(0, radius - .6));
    final shape = RRect.fromRectAndRadius(rect.deflate(.6), rad);
    final t = liquidClock.seconds * .22 + phase * math.pi * 2;

    canvas.save();
    canvas.clipRRect(shape);
    // Caustics: two pools of light sliding along the top and bottom edges.
    final m = math.min(size.width, size.height);
    void pool(double x, double y, double w, double h, double alpha) => canvas.drawOval(
          Rect.fromCenter(center: Offset(x, y), width: w, height: h),
          Paint()
            ..color = Colors.white.withValues(alpha: alpha)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, m * .22),
        );
    pool(size.width * (.30 + .22 * math.sin(t)), size.height * .02, size.width * .62, m * .50, .11);
    pool(size.width * (.72 + .18 * math.sin(t * .8 + 2)), size.height * 1.0, size.width * .55, m * .42, .06);
    // Lens edge: light inside the top lip, shade inside the bottom lip.
    final lip = math.min(m * .5, 14.0);
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = lip
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, lip * .55)
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x30FFFFFF), Color(0x00FFFFFF), Color(0x00000000), Color(0x2E000000)],
          stops: [0, .4, .6, 1],
        ).createShader(rect),
    );
    canvas.restore();

    // Rim: a hairline that is brightest at a spot which drifts around.
    final a = -math.pi * .75 + .5 * math.sin(t * .7);
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..shader = SweepGradient(
          transform: GradientRotation(a),
          colors: const [
            Color(0xD9FFFFFF),
            Color(0x38FFFFFF),
            Color(0x14FFFFFF),
            Color(0x70FFFFFF),
            Color(0x14FFFFFF),
            Color(0x38FFFFFF),
            Color(0xD9FFFFFF),
          ],
          stops: const [0, .14, .38, .5, .62, .86, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_LiquidPainter old) => old.radius != radius;
}

/// Shrinks slightly while pressed, like something soft being touched.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, required this.onTap, this.onLongPress, this.label});
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? label;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      enabled: widget.onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _down ? .94 : 1,
          duration: Duration(milliseconds: _down ? 90 : 420),
          curve: _down ? Curves.easeOut : Curves.elasticOut,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Light the current artwork throws over the whole app: a glow at the top
/// of the screen and a fainter one behind the bottom glass.
class AmbientGlow extends StatelessWidget {
  const AmbientGlow({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: player,
        builder: (context, _) {
          final t = player.current;
          return ArtColorBuilder(
            art: t?.art,
            seed: t == null ? 'hamsterfy' : t.album + t.artist,
            builder: (context, color) {
              final glow = HSLColor.fromColor(t == null ? kAccent : color).withLightness(.55).toColor();
              return DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      glow.withValues(alpha: .26),
                      glow.withValues(alpha: 0),
                      glow.withValues(alpha: 0),
                      glow.withValues(alpha: .20),
                    ],
                    stops: const [0, .34, .72, 1],
                  ),
                ),
                child: const SizedBox.expand(),
              );
            },
          );
        },
      ),
    );
  }
}

/// Floating glass tab bar with a pill that slides to the chosen tab.
class GlassTabBar extends StatelessWidget {
  const GlassTabBar({super.key, required this.index, required this.onSelect, required this.items});
  final int index;
  final ValueChanged<int> onSelect;
  final List<(IconData, IconData, String)> items;

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: 32,
      child: SizedBox(
        height: 64,
        child: LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth / items.length;
            return Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 340),
                  curve: Curves.easeOutBack,
                  left: w * index + 6,
                  top: 6,
                  width: w - 12,
                  height: 52,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: Colors.white.withValues(alpha: .18)),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      Expanded(
                        child: Pressable(
                          label: items[i].$3,
                          onTap: () {
                            if (i != index) HapticFeedback.selectionClick();
                            onSelect(i);
                          },
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(i == index ? items[i].$2 : items[i].$1, size: 24, color: i == index ? kInk : kMuted),
                              const SizedBox(height: 3),
                              Text(items[i].$3,
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: i == index ? FontWeight.w800 : FontWeight.w600,
                                      color: i == index ? kInk : kMuted)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
