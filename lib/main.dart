import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:permission_handler/permission_handler.dart';

import 'audius.dart';
import 'catalog.dart';
import 'library.dart';
import 'my_server.dart';
import 'player.dart';
import 'profiles.dart';
import 'radio.dart';
import 'search/search_service.dart';
import 'songs.dart';
import 'ui/glass.dart';
import 'ui/pages.dart';
import 'ui/player_ui.dart';
import 'ui/profile_ui.dart';
import 'ui/splash.dart';
import 'ui/theme.dart';

/// Phones get system media controls and the on-device music scan; the
/// desktop builds share everything else.
final bool isMobile = Platform.isAndroid || Platform.isIOS;

final library = Library();
final catalog = Catalog();
final radio = RadioDirectory();
final songs = SongSearch();
final audius = Audius();

/// One search over the device, the user's server, Audius, the song
/// catalog and Internet Archive releases.
SearchService get searchService => SearchService(
      sources: [
        TrackSource(SearchSource.local,
            (q) async => (await library.searchLocal(q)).where((t) => !t.isRadio && !t.isPreview && !t.isUnavailable).toList(),
            timeout: const Duration(seconds: 3)),
        // The server is asked only for its own folder: the app queries the
        // public catalogs itself, so nothing is fetched twice.
        if (myServer != null) TrackSource(SearchSource.server, (q) async => (await myServer!.search(q, sources: 'library')).tracks),
        TrackSource(SearchSource.audius, audius.search),
        TrackSource(SearchSource.previews, songs.search),
      ],
      albumSearch: catalog.search,
    );

/// Client for the user's own server, or null when none is set up.
MyServer? get myServer => library.hasServer ? MyServer(library.serverUrl, token: library.serverToken) : null;
late final Player player;
late final Profiles profiles;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (isMobile) {
    // Lock-screen and notification controls.
    await JustAudioBackground.init(
      androidNotificationChannelId: 'dev.hamsterfy.audio',
      androidNotificationChannelName: 'Воспроизведение',
      androidNotificationOngoing: true,
      // White silhouette shown in the status bar while music plays.
      androidNotificationIcon: 'drawable/ic_stat_music',
    );
  } else {
    // Windows and Linux play through libmpv.
    JustAudioMediaKit.ensureInitialized();
  }
  player = Player(library);
  profiles = Profiles(library, player);
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
      // In a wide desktop window the app stays a centred column.
      builder: (context, child) => ColoredBox(
        color: kBg,
        child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: child)),
      ),
      home: SplashScreen(
        // Accounts and the library load while the splash plays.
        load: profiles.load,
        child: ListenableBuilder(
          listenable: profiles,
          builder: (context, _) {
            final p = profiles.current;
            // A fresh Shell per account, so no screen keeps the previous one's data.
            return p == null ? const ProfileGate() : Shell(key: ValueKey(p.id));
          },
        ),
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
  void initState() {
    super.initState();
    // Android 13+ shows the playback notification and its status-bar icon
    // only after the user allows notifications.
    if (Platform.isAndroid) Permission.notification.request();
  }

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
        body: Stack(
          fit: StackFit.expand,
          children: [
            IndexedStack(
              index: _tab,
              children: [
                for (var i = 0; i < pages.length; i++)
                  Navigator(
                    key: _keys[i],
                    onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => pages[i]),
                  ),
              ],
            ),
            // Light from the current artwork over every screen.
            const AmbientGlow(),
            // Floating glass: the mini player and the tab bar. Content
            // scrolls underneath and shows through, blurred.
            Positioned(
              left: 12,
              right: 12,
              bottom: 0,
              child: SafeArea(
                minimum: const EdgeInsets.only(bottom: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const MiniPlayer(),
                    GlassTabBar(
                      index: _tab,
                      onSelect: (i) {
                        if (i == _tab) {
                          _keys[i].currentState?.popUntil((r) => r.isFirst);
                        } else {
                          setState(() => _tab = i);
                        }
                      },
                      items: const [
                        (Icons.home_outlined, Icons.home_rounded, 'Главная'),
                        (Icons.search_rounded, Icons.search_rounded, 'Поиск'),
                        (Icons.library_music_outlined, Icons.library_music_rounded, 'Медиатека'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
