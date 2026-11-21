import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'catalog.dart';
import 'library.dart';
import 'player.dart';
import 'ui/pages.dart';
import 'ui/player_ui.dart';
import 'ui/theme.dart';

final library = Library();
final catalog = Catalog();
late final Player player;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'dev.hamsterfy.audio',
    androidNotificationChannelName: 'Воспроизведение',
    androidNotificationOngoing: true,
  );
  await library.load();
  player = Player(library);
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
      home: const Shell(),
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
