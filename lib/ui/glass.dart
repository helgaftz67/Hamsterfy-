import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import 'theme.dart';

/// How much room floating chrome (tab bar, mini player) takes at the
/// bottom of a tab. Lists add it to their bottom padding so the last rows
/// can scroll clear of the glass.
double get dockSpace => 86 + (player.current == null ? 0 : 70);

/// A sheet of "liquid glass": whatever is behind it shows through,
/// blurred; a bright rim and a soft highlight give it thickness.
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
    final base = tint ?? const Color(0xFF2A2540);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .26), blurRadius: 22, offset: const Offset(0, 6))],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: CustomPaint(
            foregroundPainter: _RimPainter(radius),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(base, Colors.white, .16)!.withValues(alpha: .50 * strength),
                    base.withValues(alpha: .42 * strength),
                    Color.lerp(base, Colors.black, .30)!.withValues(alpha: .50 * strength),
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

/// The bright edge of the glass: light catches the top-left, fades along
/// the sides and returns faintly at the bottom-right.
class _RimPainter extends CustomPainter {
  _RimPainter(this.radius);
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(rect.deflate(.6), Radius.circular(radius - .6));
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x99FFFFFF), Color(0x1AFFFFFF), Color(0x0DFFFFFF), Color(0x40FFFFFF)],
          stops: [0, .35, .7, 1],
        ).createShader(rect),
    );
    // Specular sheen across the upper part.
    canvas.save();
    canvas.clipRRect(shape);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height * .5),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x1FFFFFFF), Color(0x00FFFFFF)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height * .5)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RimPainter old) => old.radius != radius;
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
          scale: _down ? .95 : 1,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
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
