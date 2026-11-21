import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'hamsters.dart';
import 'theme.dart';

/// Start-up screen: the hamsters listen to their record while the app loads.
/// Shows [child] once [load] has finished and the greeting had its moment.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.load, required this.child});
  final Future<void> Function() load;
  final Widget child;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const _lines = [
    'Хомяки надевают наушники…',
    'Набиваем щёки музыкой…',
    'Раскручиваем колесо…',
    'Ищем, куда закатился бит…',
    'Проверяем запасы семечек…',
    'Настраиваем усы на нужную частоту…',
  ];

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
              const SizedBox(width: 320, height: 300, child: HamsterScene()),
              const SizedBox(height: 8),
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
