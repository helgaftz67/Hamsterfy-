import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Start-up screen: the two hamsters bob to the beat while the app loads.
/// Shows [child] once [load] has finished and the greeting had its moment.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.load, required this.child});
  final Future<void> Function() load;
  final Widget child;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  static const _lines = [
    'Хомяки надевают наушники…',
    'Набиваем щёки музыкой…',
    'Раскручиваем колесо…',
    'Ищем, куда закатился бит…',
    'Проверяем запасы семечек…',
    'Настраиваем усы на нужную частоту…',
  ];

  late final _beat = AnimationController(vsync: this, duration: const Duration(milliseconds: 620))..repeat(reverse: true);
  late int _line = math.Random().nextInt(_lines.length);
  Timer? _ticker;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 1100), (_) {
      if (mounted) setState(() => _line = (_line + 1) % _lines.length);
    });
    _start();
  }

  Future<void> _start() async {
    // Long enough to read one line, never longer than loading needs.
    final pause = Future<void>.delayed(const Duration(milliseconds: 1700));
    try {
      await widget.load();
    } catch (_) {
      // A failed load still opens the app, on the account screen.
    }
    await pause;
    if (!mounted) return;
    _ticker?.cancel();
    setState(() => _ready = true);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      child: _ready ? widget.child : _loading(),
    );
  }

  Widget _loading() {
    return Scaffold(
      key: const ValueKey('splash'),
      body: Semantics(
        label: 'Hamsterfy загружается',
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 240,
                height: 230,
                child: AnimatedBuilder(
                  animation: _beat,
                  builder: (context, _) {
                    final t = Curves.easeInOut.transform(_beat.value);
                    return Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        // Notes drift up and fade, out of step with each other.
                        for (final (dx, phase, size) in [(-92.0, 0.0, 30.0), (88.0, .5, 24.0), (-40.0, .25, 20.0)])
                          Positioned(
                            left: 120 + dx - size / 2,
                            top: 44 - 34 * ((t + phase) % 1),
                            child: Opacity(
                              opacity: (1 - ((t + phase) % 1)).clamp(0, 1).toDouble(),
                              child: Icon(Icons.music_note_rounded, size: size, color: dx > 0 ? kAmber : kAccent),
                            ),
                          ),
                        // The icon squashes on the beat and tilts side to side.
                        Positioned(
                          bottom: 0,
                          child: Transform.translate(
                            offset: Offset(0, -16 * t),
                            child: Transform.rotate(
                              angle: (t - .5) * .12,
                              child: Transform.scale(
                                scaleX: 1 + .05 * (1 - t),
                                scaleY: 1 - .05 * (1 - t),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(40),
                                  child: Image.asset('assets/brand/icon.png', width: 168, height: 168),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 26),
              const Text('Hamsterfy', style: kTitle),
              const SizedBox(height: 10),
              SizedBox(
                height: 22,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(_lines[_line],
                      key: ValueKey(_line), style: const TextStyle(color: kMuted, fontWeight: FontWeight.w500)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
