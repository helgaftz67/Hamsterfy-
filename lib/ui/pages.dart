import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../library.dart';
import '../main.dart';
import '../models.dart';
import 'profile_ui.dart';
import 'theme.dart';

// ---------------------------------------------------------------- Home ----

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Future<List<Album>>? _forYou;
  String _forYouTitle = 'Популярное в открытом каталоге';

  @override
  void initState() {
    super.initState();
    _loadForYou();
  }

  /// Catalog picks: releases matching the user's favourite artists, or the
  /// most downloaded releases when there is nothing to go on yet.
  void _loadForYou() {
    final artists = library.topArtists;
    setState(() {
      _forYou = () async {
        for (final a in artists) {
          final found = await catalog.search(a);
          if (found.isNotEmpty) {
            _forYouTitle = 'Похоже на «$a»';
            return found;
          }
        }
        _forYouTitle = 'Популярное в открытом каталоге';
        return catalog.search('');
      }();
    });
  }

  void _open(String title, List<Track> tracks) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => TrackListPage(title: title, tracks: () => tracks)));
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 5) return 'Доброй ночи';
    if (h < 12) return 'Доброе утро';
    if (h < 18) return 'Добрый день';
    return 'Добрый вечер';
  }

  void _push(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: Listenable.merge([library, profiles]),
          builder: (context, _) {
            final empty = library.songs.isEmpty;
            final top = library.mostPlayed;
            final me = profiles.current;
            return RefreshIndicator(
              onRefresh: () async {
                _loadForYou();
                await _forYou;
              },
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_greeting, style: const TextStyle(color: kMuted, fontWeight: FontWeight.w600)),
                              Text(me?.name ?? 'Hamsterfy', maxLines: 1, overflow: TextOverflow.ellipsis, style: kTitle),
                            ],
                          ),
                        ),
                        if (me != null)
                          IconButton(
                            tooltip: 'Профиль',
                            onPressed: () => _push(const ProfilePage()),
                            icon: ProfileAvatar(me, size: 42),
                          ),
                      ],
                    ),
                  ),
                  _Wave(enabled: !empty),
                  if (empty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(24, 14, 24, 4),
                      child: Text(
                        'Волна собирается из вашей коллекции. Откройте Медиатеку и найдите музыку на телефоне.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: kMuted),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            _Quick(
                                icon: Icons.favorite_rounded,
                                tint: kAccent,
                                label: 'Избранное',
                                onTap: () =>
                                    _push(TrackListPage(title: 'Избранное', tracks: () => library.favoriteTracks))),
                            const SizedBox(width: 8),
                            _Quick(
                                icon: Icons.sensors_rounded,
                                tint: kAmber,
                                label: 'Радио',
                                onTap: () => _push(const RadioPage())),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _Quick(
                                icon: Icons.download_done_rounded,
                                tint: const Color(0xFF5ED4A8),
                                label: 'На устройстве',
                                onTap: () =>
                                    _push(TrackListPage(title: 'На устройстве', tracks: () => library.downloaded))),
                            const SizedBox(width: 8),
                            _Quick(
                                icon: Icons.shuffle_rounded,
                                tint: const Color(0xFFFF8FB1),
                                label: 'Вперемешку',
                                onTap: empty
                                    ? null
                                    : () => player.playAll(library.songs..shuffle())),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (top.isNotEmpty) ...[
                    _Header('Часто слушаете', onMore: () => _open('Часто слушаете', top)),
                    _TrackShelf(top),
                  ],
                  if (library.forgotten().length >= 3) ...[
                    _Header('Давно не слушали', onMore: () => _open('Давно не слушали', library.forgotten())),
                    _TrackShelf(library.forgotten()),
                  ],
                  FutureBuilder<List<Album>>(
                    future: _forYou,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (snap.hasError || (snap.data ?? const []).isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(20, 24, 12, 0),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text('Рекомендации из каталога не загрузились. Нужен интернет.',
                                    style: TextStyle(color: kMuted)),
                              ),
                              TextButton(onPressed: _loadForYou, child: const Text('Повторить')),
                            ],
                          ),
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [_Header(_forYouTitle), _AlbumShelf(snap.data!)],
                      );
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The "My wave" hero: a card of slowly drifting colour that starts a
/// personal mix with one tap.
class _Wave extends StatefulWidget {
  const _Wave({required this.enabled});
  final bool enabled;

  @override
  State<_Wave> createState() => _WaveState();
}

class _WaveState extends State<_Wave> with SingleTickerProviderStateMixin {
  late final _drift = AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat();
  bool _waveOn = false;

  @override
  void initState() {
    super.initState();
    player.addListener(_sync);
  }

  void _sync() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    player.removeListener(_sync);
    _drift.dispose();
    super.dispose();
  }

  void _tap() {
    HapticFeedback.mediumImpact();
    if (_waveOn && player.current != null) {
      player.toggle();
      return;
    }
    _waveOn = true;
    player.playAll(library.wave());
  }

  @override
  Widget build(BuildContext context) {
    final active = _waveOn && player.playing;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Semantics(
        button: true,
        label: active ? 'Поставить волну на паузу' : 'Запустить мою волну',
        child: Opacity(
          opacity: widget.enabled ? 1 : .5,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: GestureDetector(
              onTap: widget.enabled ? _tap : null,
              child: SizedBox(
                height: 208,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _drift,
                        builder: (_, _) => CustomPaint(painter: _WavePainter(_drift.value, active ? 1.0 : .55)),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(active ? 'ИГРАЕТ' : 'ДЛЯ ВАС',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: .8),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.6)),
                          const SizedBox(height: 4),
                          const Text('Моя волна',
                              style: TextStyle(
                                  color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1)),
                          const SizedBox(height: 2),
                          Text('Бесконечный микс из вашей коллекции',
                              style: TextStyle(color: Colors.white.withValues(alpha: .82), fontWeight: FontWeight.w500)),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.fromLTRB(14, 10, 20, 10),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(active ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.black, size: 26),
                                const SizedBox(width: 6),
                                Text(active ? 'Пауза' : 'Слушать',
                                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 15)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Soft blobs of colour drifting over a deep violet ground.
class _WavePainter extends CustomPainter {
  _WavePainter(this.t, this.energy);
  final double t;
  final double energy;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF2B1D6E));
    const colors = [Color(0xFF8E6BFF), Color(0xFFFF7EB6), Color(0xFFFFB938), Color(0xFF4AC7FF)];
    for (var i = 0; i < colors.length; i++) {
      final a = (t + i / colors.length) * 2 * math.pi;
      final center = Offset(
        size.width * (.5 + .42 * math.cos(a + i * 1.3)),
        size.height * (.5 + .46 * math.sin(a * (i.isEven ? 1 : -1) + i)),
      );
      final radius = size.width * (.34 + .08 * math.sin(a * 2 + i)) * (.85 + .3 * energy);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = colors[i].withValues(alpha: .50 + .25 * energy)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * .14),
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
  bool shouldRepaint(_WavePainter old) => old.t != t || old.energy != energy;
}

/// Compact shortcut tile, two per row.
class _Quick extends StatelessWidget {
  const _Quick({required this.icon, required this.tint, required this.label, required this.onTap});
  final IconData icon;
  final Color tint;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: kSurface,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                color: tint.withValues(alpha: .20),
                child: Icon(icon, color: tint, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text, {this.onMore});
  final String text;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -.3)),
          ),
          if (onMore != null) TextButton(onPressed: onMore, child: const Text('Все')),
        ],
      ),
    );
  }
}

class _TrackShelf extends StatelessWidget {
  const _TrackShelf(this.tracks);
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 204,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: tracks.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final t = tracks[i];
          return _ShelfCard(
            art: t.art,
            seed: t.album + t.artist,
            title: t.title,
            subtitle: t.artist,
            onTap: () => player.playAll(tracks, start: i),
          );
        },
      ),
    );
  }
}

class _AlbumShelf extends StatelessWidget {
  const _AlbumShelf(this.albums);
  final List<Album> albums;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 204,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: albums.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final a = albums[i];
          return _ShelfCard(
            art: a.art,
            seed: a.id,
            title: a.title,
            subtitle: a.artist,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AlbumPage(a))),
          );
        },
      ),
    );
  }
}

class _ShelfCard extends StatelessWidget {
  const _ShelfCard({required this.art, required this.seed, required this.title, required this.subtitle, required this.onTap});
  final String? art;
  final String seed;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 148,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Cover(art, size: 148, radius: 12, seed: seed),
            const SizedBox(height: 8),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kMuted, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- Catalog ----

class CatalogPage extends StatefulWidget {
  const CatalogPage({super.key});

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

/// Search tab: every song in the world catalog (previews), or the free
/// catalog where whole releases can be played and downloaded.
class _CatalogPageState extends State<CatalogPage> {
  final _query = TextEditingController();
  bool _world = true;
  Future<List<Track>>? _songs;
  Future<List<Album>>? _albums;

  void _search() => setState(() {
        if (_world) {
          _songs = _query.text.trim().isEmpty ? null : songs.search(_query.text);
        } else {
          _albums = catalog.search(_query.text);
        }
      });

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 16, 0),
              child: Text('Поиск', style: kTitle),
            ),
            _SearchField(
                controller: _query,
                hint: _world ? 'Песня или исполнитель' : 'Исполнитель, релиз или жанр',
                onSearch: _search),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(
                children: [
                  for (final (world, label) in [(true, 'Все песни'), (false, 'Свободная музыка')])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: _world == world,
                        onSelected: (_) {
                          _world = world;
                          _search();
                        },
                      ),
                    ),
                ],
              ),
            ),
            Expanded(child: _world ? _songList() : _albumList()),
          ],
        ),
      ),
    );
  }

  Widget _songList() {
    if (_songs == null) {
      return const _Message(
          'Найдётся любая песня. Трек из вашей медиатеки сыграет целиком, остальные — 30-секундным фрагментом со ссылкой на полную версию.');
    }
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) => FutureBuilder<List<Track>>(
        future: _songs,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) {
            return _Message('Поиск не отвечает. Проверьте подключение к интернету.', action: 'Повторить', onAction: _search);
          }
          // Songs the user already owns play in full instead of the preview.
          final seen = <String>{};
          final found = [
            for (final t in snap.data ?? const <Track>[])
              if (seen.add((library.match(t) ?? t).id)) library.match(t) ?? library.tracks[t.id] ?? t,
          ];
          final own = Library.filter(library.songs, _query.text).where((t) => seen.add(t.id)).toList();
          final all = [...own, ...found];
          if (all.isEmpty) {
            return const _Message('Ничего не нашлось. Проверьте написание или попробуйте только имя исполнителя.');
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: all.length,
            itemBuilder: (context, i) => TrackTile(all[i], onTap: () => player.playAll(all, start: i)),
          );
        },
      ),
    );
  }

  Widget _albumList() {
    return FutureBuilder<List<Album>>(
      future: _albums,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) {
          return _Message('Каталог не отвечает. Проверьте подключение к интернету.', action: 'Повторить', onAction: _search);
        }
        final albums = snap.data ?? const [];
        if (albums.isEmpty) {
          return const _Message(
              'В свободном каталоге этого нет: здесь релизы под свободными лицензиями и концертные записи. Популярных артистов ищите во вкладке «Все песни».');
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: albums.length,
          itemBuilder: (context, i) {
            final a = albums[i];
            return ListTile(
              leading: Cover(a.art, size: 52, seed: a.id),
              title: Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(a.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.chevron_right_rounded, color: kMuted),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AlbumPage(a))),
            );
          },
        );
      },
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.hint, required this.onSearch});
  final TextEditingController controller;
  final String hint;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: SearchBar(
        controller: controller,
        hintText: hint,
        leading: const Icon(Icons.search),
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: const WidgetStatePropertyAll(kSurface),
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => onSearch(),
        trailing: [
          ListenableBuilder(
            listenable: controller,
            builder: (_, _) => controller.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Очистить',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      controller.clear();
                      onSearch();
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Internet radio: its own screen, opened from the home page.
class RadioPage extends StatefulWidget {
  const RadioPage({super.key});

  @override
  State<RadioPage> createState() => _RadioPageState();
}

class _RadioPageState extends State<RadioPage> {
  final _query = TextEditingController();
  late Future<List<Track>> _stations = radio.search('');

  void _search() => setState(() => _stations = radio.search(_query.text));

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Радио')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Живой эфир станций со всего мира. Отметьте станцию сердечком, чтобы она была под рукой.',
                style: TextStyle(color: kMuted)),
          ),
          _SearchField(controller: _query, hint: 'Станция или жанр: шансон, rock', onSearch: _search),
          Expanded(
            child: ListenableBuilder(
              listenable: library,
              builder: (context, _) => FutureBuilder<List<Track>>(
                future: _stations,
                builder: (context, snap) {
                  final mine = _query.text.trim().isEmpty ? library.stations : const <Track>[];
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError && mine.isEmpty) {
                    return _Message('Список станций не загрузился. Проверьте подключение к интернету.',
                        action: 'Повторить', onAction: _search);
                  }
                  final mineIds = {for (final t in mine) t.id};
                  final found = (snap.data ?? const <Track>[]).where((t) => !mineIds.contains(t.id)).toList();
                  if (found.isEmpty && mine.isEmpty) {
                    return const _Message(
                        'Станций с таким названием или жанром нет. Попробуйте другое слово, например «rock» или «ретро».');
                  }
                  return ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      if (mine.isNotEmpty) ...[
                        const _Header('Мои станции'),
                        for (final t in mine) TrackTile(t, onTap: () => player.playAll([t])),
                        const _Header('Популярные'),
                      ],
                      for (final t in found) TrackTile(t, onTap: () => player.playAll([t])),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.action, this.onAction});
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: kMuted, fontSize: 15)),
            if (action != null) ...[
              const SizedBox(height: 12),
              FilledButton.tonal(onPressed: onAction, child: Text(action!)),
            ],
          ],
        ),
      ),
    );
  }
}

class AlbumPage extends StatefulWidget {
  const AlbumPage(this.album, {super.key});
  final Album album;

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  late Future<List<Track>> _tracks = catalog.tracks(widget.album);

  Future<void> _downloadAll(List<Track> tracks) async {
    toast(context, 'Скачиваю релиз');
    var failed = 0;
    for (final t in tracks) {
      try {
        await library.download(library.tracks[t.id] ?? t);
      } catch (_) {
        failed++;
      }
    }
    if (mounted) toast(context, failed == 0 ? 'Релиз скачан' : 'Не скачалось треков: $failed. Попробуйте ещё раз.');
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.album;
    return Scaffold(
      appBar: AppBar(),
      body: FutureBuilder<List<Track>>(
        future: _tracks,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) {
            return _Message('Релиз не загрузился. Проверьте подключение к интернету.',
                action: 'Повторить', onAction: () => setState(() => _tracks = catalog.tracks(a)));
          }
          // Reuse library copies so downloaded tracks play from the device.
          final tracks = [for (final t in snap.data!) library.tracks[t.id] ?? t];
          if (tracks.isEmpty) return const _Message('В этом релизе нет треков в формате MP3.');
          return ListView.builder(
            itemCount: tracks.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    children: [
                      Cover(a.art, size: 210, radius: 14, seed: a.id, shadow: true),
                      const SizedBox(height: 14),
                      Text(a.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -.4)),
                      const SizedBox(height: 2),
                      Text(a.artist, textAlign: TextAlign.center, style: const TextStyle(color: kMuted)),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FilledButton.icon(
                              onPressed: () => player.playAll(tracks),
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Слушать')),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                              onPressed: () => _downloadAll(tracks),
                              icon: const Icon(Icons.download),
                              label: const Text('Скачать всё')),
                        ],
                      ),
                    ],
                  ),
                );
              }
              return TrackTile(tracks[i - 1], onTap: () => player.playAll(tracks, start: i - 1));
            },
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------------- Library ----

enum _Filter { all, favorites, playlists, stations, downloaded }

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  _Filter _filter = _Filter.all;
  bool _busy = false;
  String _query = '';

  /// Ids ticked in selection mode; the mode is on while this is not empty.
  final Set<String> _selected = {};

  void _toggle(Track t) => setState(() {
        if (!_selected.remove(t.id)) _selected.add(t.id);
      });

  Future<void> _removeSelected() async {
    final picked = [for (final id in _selected) if (library.tracks[id] != null) library.tracks[id]!];
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Убрать из медиатеки треков: ${picked.length}?'),
        content: const Text('Они пропадут из медиатеки, избранного и плейлистов. Ваши файлы в памяти телефона останутся.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Убрать')),
        ],
      ),
    );
    if (ok != true) return;
    for (final t in picked) {
      await library.forget(t);
    }
    if (!mounted) return;
    setState(_selected.clear);
    toast(context, 'Убрано треков: ${picked.length}');
  }

  @override
  void initState() {
    super.initState();
    // Pick up new files quietly when access was already granted.
    library.scanDevice(ask: false).catchError((_) => 0);
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() => _run(() async {
        try {
          final n = await library.importFiles();
          if (mounted && n > 0) toast(context, 'Добавлено треков: $n');
        } catch (_) {
          if (mounted) toast(context, 'Не удалось добавить файлы. Попробуйте выбрать их снова.');
        }
      });

  Future<void> _scan() => _run(() async {
        try {
          final n = await library.scanDevice();
          if (!mounted) return;
          toast(
            context,
            n < 0
                ? 'Нет доступа к музыке. Разрешите его в настройках телефона: Приложения → Hamsterfy → Разрешения.'
                : (n == 0 ? 'Новых треков на телефоне нет' : 'Найдено новых треков: $n'),
          );
        } catch (_) {
          if (mounted) toast(context, 'Не удалось просмотреть память телефона. Попробуйте ещё раз.');
        }
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: library,
          builder: (context, _) {
            final inFilter = switch (_filter) {
              _Filter.all => library.songs,
              _Filter.favorites => library.favoriteTracks,
              _Filter.stations => library.stations,
              _Filter.downloaded => library.downloaded,
              _Filter.playlists => const <Track>[],
            };
            final tracks = Library.filter(inFilter, _query);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_selected.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
                    child: Row(
                      children: [
                        IconButton(
                            tooltip: 'Отменить выделение',
                            onPressed: () => setState(_selected.clear),
                            icon: const Icon(Icons.close_rounded)),
                        Expanded(
                          child: Text('Выбрано: ${_selected.length}',
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            final ids = tracks.map((t) => t.id).toSet();
                            if (_selected.containsAll(ids)) {
                              _selected.clear();
                            } else {
                              _selected.addAll(ids);
                            }
                          }),
                          child: Text(_selected.length >= tracks.length ? 'Снять все' : 'Выбрать все'),
                        ),
                        IconButton(
                            tooltip: 'Убрать выбранные из медиатеки',
                            onPressed: _removeSelected,
                            icon: const Icon(Icons.delete_outline_rounded)),
                      ],
                    ),
                  )
                else
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 4, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('Медиатека', style: kTitle),
                      ),
                      if (_busy)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
                        )
                      else ...[
                        IconButton(
                            tooltip: 'Найти музыку на телефоне',
                            onPressed: _scan,
                            icon: const Icon(Icons.phonelink_setup)),
                        IconButton(
                            tooltip: 'Добавить файлы вручную', onPressed: _import, icon: const Icon(Icons.add)),
                      ],
                    ],
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      for (final (f, label) in [
                        (_Filter.all, 'Треки'),
                        (_Filter.favorites, 'Избранное'),
                        (_Filter.playlists, 'Плейлисты'),
                        (_Filter.stations, 'Радио'),
                        (_Filter.downloaded, 'На устройстве'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(label),
                            selected: _filter == f,
                            onSelected: (_) => setState(() {
                              _filter = f;
                              _selected.clear();
                            }),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (_filter == _Filter.playlists)
                  Expanded(child: _playlists())
                else ...[
                  if (inFilter.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                      child: TextField(
                        onChanged: (v) => setState(() => _query = v),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Поиск по медиатеке',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: kSurface,
                          isDense: true,
                          border:
                              OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                  Expanded(
                    child: tracks.isEmpty
                        ? (inFilter.isNotEmpty
                            ? const _Message('В медиатеке такого нет. Проверьте написание или поищите в Каталоге.')
                            : _empty())
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 24),
                            itemCount: tracks.length,
                            itemBuilder: (context, i) => TrackTile(
                              tracks[i],
                              selected: _selected.isEmpty ? null : _selected.contains(tracks[i].id),
                              onLongPress: () {
                                HapticFeedback.selectionClick();
                                _toggle(tracks[i]);
                              },
                              onTap: () => _selected.isNotEmpty
                                  ? _toggle(tracks[i])
                                  : (tracks[i].isRadio
                                      ? player.playAll([tracks[i]])
                                      : player.playAll(tracks, start: i)),
                            ),
                          ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _empty() => switch (_filter) {
        _Filter.all => _Message(
            'Здесь появится ваша музыка. Приложение может само найти все треки на телефоне.',
            action: 'Найти музыку на телефоне',
            onAction: _scan,
          ),
        _Filter.favorites => const _Message('Отмечайте треки и станции сердечком, и они соберутся здесь.'),
        _Filter.stations => const _Message('Откройте Радио на Главной и отметьте станцию сердечком, она появится здесь.'),
        _ => const _Message('Треки с телефона и скачанные из каталога играют без интернета.'),
      };

  Widget _playlists() {
    final names = library.playlistNames;
    return ListView(
      children: [
        ListTile(
          leading: const CircleAvatar(backgroundColor: kSunken, child: Icon(Icons.add, color: kAccent)),
          title: const Text('Новый плейлист'),
          onTap: () => newPlaylistDialog(context),
        ),
        if (names.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Text('Собирайте треки в плейлисты: откройте меню трека и выберите «Добавить в плейлист».',
                textAlign: TextAlign.center, style: TextStyle(color: kMuted)),
          ),
        for (final name in names)
          ListTile(
            leading: Cover(library.playlistTracks(name).firstOrNull?.art, seed: name),
            title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('Треков: ${library.playlists[name]!.length}'),
            trailing: const Icon(Icons.chevron_right, color: kMuted),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TrackListPage(title: name, tracks: () => library.playlistTracks(name), playlist: name),
              ),
            ),
          ),
      ],
    );
  }
}

/// A plain list of tracks with "play all" and "shuffle".
class TrackListPage extends StatelessWidget {
  const TrackListPage({super.key, required this.title, required this.tracks, this.playlist});
  final String title;
  final List<Track> Function() tracks;

  /// Name of the playlist this page shows, if it is one.
  final String? playlist;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (playlist != null)
            IconButton(
              tooltip: 'Удалить плейлист',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final nav = Navigator.of(context);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: Text('Удалить плейлист «$playlist»?'),
                    content: const Text('Сами треки останутся в медиатеке.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Отмена')),
                      FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Удалить')),
                    ],
                  ),
                );
                if (ok == true) {
                  library.deletePlaylist(playlist!);
                  nav.pop();
                }
              },
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: library,
        builder: (context, _) {
          final list = tracks();
          if (list.isEmpty) {
            return _Message(playlist == null
                ? 'Пока пусто.'
                : 'В плейлисте пока нет треков. Откройте меню любого трека и выберите «Добавить в плейлист».');
          }
          return ListView.builder(
            itemCount: list.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Row(
                    children: [
                      FilledButton.icon(
                          onPressed: () => player.playAll(list),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Слушать')),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                          onPressed: () => player.playAll([...list]..shuffle()),
                          icon: const Icon(Icons.shuffle),
                          label: const Text('Вперемешку')),
                    ],
                  ),
                );
              }
              return TrackTile(list[i - 1], playlist: playlist, onTap: () => player.playAll(list, start: i - 1));
            },
          );
        },
      ),
    );
  }
}
