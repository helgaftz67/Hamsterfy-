import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'catalog.dart';
import 'library.dart';
import 'player.dart';
import 'profiles.dart';
import 'ui/pages.dart';
import 'ui/player_ui.dart';
import 'ui/profile_ui.dart';
import 'ui/theme.dart';

final library = Library();
final catalog = Catalog();
late final Player player;
late final Profiles profiles;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'dev.hamsterfy.audio',
    androidNotificationChannelName: 'Воспроизведение',
    androidNotificationOngoing: true,
  );
  player = Player(library);
  profiles = Profiles(library, player);
  await profiles.load();
  runApp(const HamsterfyApp());
}

class HamsterfyApp extends StatelessWidget {
  const HamsterfyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hamsterfy',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: ListenableBuilder(
        listenable: profiles,
        builder: (context, _) {
          final p = profiles.current;
          // A fresh Shell per account, so no screen keeps the previous one's data.
          return p == null ? const ProfileGate() : Shell(key: ValueKey(p.id));
        },
      ),
    );
  }
}

/// Three tabs with the mini player pinned above the navigation bar.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  final _keys = List.generate(3, (_) => GlobalKey<NavigatorState>());

  @override
  Widget build(BuildContext context) {
    const pages = [HomePage(), CatalogPage(), LibraryPage()];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final nav = _keys[_tab].currentState!;
        if (nav.canPop()) {
          nav.pop();
        } else if (_tab != 0) {
          setState(() => _tab = 0);
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _tab,
          children: [
            for (var i = 0; i < pages.length; i++)
              Navigator(
                key: _keys[i],
                onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => pages[i]),
              ),
          ],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MiniPlayer(),
            NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) {
                if (i == _tab) {
                  _keys[i].currentState?.popUntil((r) => r.isFirst);
                } else {
                  setState(() => _tab = i);
                }
              },
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Главная'),
                NavigationDestination(icon: Icon(Icons.travel_explore), label: 'Каталог'),
                NavigationDestination(
                    icon: Icon(Icons.library_music_outlined),
                    selectedIcon: Icon(Icons.library_music),
                    label: 'Медиатека'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
