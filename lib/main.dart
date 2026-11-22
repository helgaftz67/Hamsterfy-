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
import 'lyrics.dart';
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
final audius = Audius();
final lyrics = LyricsService();

/// One search over the device, the user's server, Audius and Internet
/// Archive releases. Only tracks that play in full: no 30-second previews.
SearchService get searchService => SearchService(
      sources: [
        TrackSource(SearchSource.local,
            (q) async => (await library.searchLocal(q)).where((t) => !t.isRadio && !t.isPreview && !t.isUnavailable).toList(),
            timeout: const Duration(seconds: 3)),
        // The server is asked only for its own folder: the app queries the
        // public catalogs itself, so nothing is fetched twice.
        if (myServer != null) TrackSource(SearchSource.server, (q) async => (await myServer!.search(q, sources: 'library')).tracks),
        TrackSource(SearchSource.audius, audius.search),
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
  liquidClock.start();
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

  void _select(int i) {
    if (i == _tab) {
      _keys[i].currentState?.popUntil((r) => r.isFirst);
    } else {
      setState(() => _tab = i);
    }
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
        body: LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth >= kWideBreakpoint;
            wideLayout = wide;
            final content = IndexedStack(
              index: _tab,
              children: [
                for (var i = 0; i < pages.length; i++)
                  Navigator(
                    key: _keys[i],
                    onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => pages[i]),
                  ),
              ],
            );
            const items = [
              (Icons.home_outlined, Icons.home_rounded, 'Главная'),
              (Icons.search_rounded, Icons.search_rounded, 'Поиск'),
              (Icons.library_music_outlined, Icons.library_music_rounded, 'Медиатека'),
            ];
            if (wide) {
              // Desktop: navigation on the left, the player as one wide
              // bar under the content.
              return Stack(
                fit: StackFit.expand,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 248,
                        child: _Sidebar(
                          index: _tab,
                          items: items,
                          onSelect: _select,
                          onProfile: () => _keys[_tab]
                              .currentState
                              ?.push(MaterialPageRoute(builder: (_) => const ProfilePage())),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          // Lists stay readable on very wide monitors.
                          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100), child: content),
                        ),
                      ),
                    ],
                  ),
                  const AmbientGlow(),
                  const Positioned(left: 260, right: 14, bottom: 14, child: DesktopPlayerBar()),
                ],
              );
            }
            return Stack(
              fit: StackFit.expand,
              children: [
                content,
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
                        GlassTabBar(index: _tab, onSelect: _select, items: items),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Desktop navigation: brand, the three sections, and the account at the
/// bottom.
class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.index, required this.items, required this.onSelect, required this.onProfile});
  final int index;
  final List<(IconData, IconData, String)> items;
  final ValueChanged<int> onSelect;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 0, 14),
      child: Glass(
        radius: 28,
        strength: .7,
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 22),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Image.asset('assets/brand/icon.png', width: 38, height: 38),
                  ),
                  const SizedBox(width: 10),
                  const Text('Hamsterfy', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.4)),
                ],
              ),
            ),
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Pressable(
                  label: items[i].$3,
                  onTap: () => onSelect(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: i == index ? Colors.white.withValues(alpha: .14) : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: i == index ? Colors.white.withValues(alpha: .18) : Colors.transparent),
                    ),
                    child: Row(
                      children: [
                        Icon(i == index ? items[i].$2 : items[i].$1, size: 23, color: i == index ? kInk : kMuted),
                        const SizedBox(width: 12),
                        Text(items[i].$3,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: i == index ? FontWeight.w800 : FontWeight.w600,
                                color: i == index ? kInk : kMuted)),
                      ],
                    ),
                  ),
                ),
              ),
            const Spacer(),
            ListenableBuilder(
              listenable: profiles,
              builder: (context, _) {
                final me = profiles.current;
                if (me == null) return const SizedBox.shrink();
                return Pressable(
                  label: 'Профиль',
                  onTap: onProfile,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .07),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        ProfileAvatar(me, size: 36),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(me.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: kMuted),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
