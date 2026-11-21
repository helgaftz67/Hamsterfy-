import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: library,
          builder: (context, _) {
            final empty = library.tracks.isEmpty;
            final top = library.mostPlayed;
            return RefreshIndicator(
              onRefresh: () async {
                _loadForYou();
                await _forYou;
              },
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 12, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text('Hamsterfy', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                        ),
                        if (profiles.current != null)
                          IconButton(
                            tooltip: 'Аккаунт',
                            onPressed: () => showAccountSheet(context),
                            icon: ProfileAvatar(profiles.current!),
                          ),
                      ],
                    ),
                  ),
                  _Wave(enabled: !empty),
                  if (empty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(24, 4, 24, 16),
                      child: Text(
                        'Волна собирается из вашей коллекции. Откройте Медиатеку и найдите музыку на телефоне или включите радио ниже.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: kMuted),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Row(
                        children: [
                          _Quick(
                              icon: Icons.favorite,
                              label: 'Избранное',
                              count: library.favorites.length,
                              onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          TrackListPage(title: 'Избранное', tracks: () => library.favoriteTracks)))),
                          const SizedBox(width: 10),
                          _Quick(
                              icon: Icons.download_done,
                              label: 'Скачанное',
                              count: library.downloaded.length,
                              onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          TrackListPage(title: 'Скачанное', tracks: () => library.downloaded)))),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                    child: Material(
                      color: kSurface,
                      borderRadius: BorderRadius.circular(12),
                      child: ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        leading: const Icon(Icons.sensors, color: kAmber),
                        title: const Text('Радио', style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: const Text('Живой эфир без файлов'),
                        trailing: const Icon(Icons.chevron_right, color: kMuted),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RadioPage())),
                      ),
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
                          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
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

/// The big "My wave" button: one tap starts a personal mix.
class _Wave extends StatefulWidget {
  const _Wave({required this.enabled});
  final bool enabled;

  @override
  State<_Wave> createState() => _WaveState();
}

class _WaveState extends State<_Wave> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  bool _waveOn = false;

  @override
  void initState() {
    super.initState();
    player.addListener(_sync);
  }

  void _sync() {
    final active = _waveOn && player.playing;
    if (active && !_pulse.isAnimating) _pulse.repeat(reverse: true);
    if (!active && _pulse.isAnimating) _pulse.stop();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    player.removeListener(_sync);
    _pulse.dispose();
    super.dispose();
  }

  void _tap() {
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
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Semantics(
          button: true,
          label: active ? 'Поставить волну на паузу' : 'Запустить мою волну',
          child: GestureDetector(
            onTap: widget.enabled ? _tap : null,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) => Transform.scale(scale: 1 + _pulse.value * .06, child: child),
              child: Opacity(
                opacity: widget.enabled ? 1 : .45,
                child: Container(
                  width: 190,
                  height: 190,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const SweepGradient(colors: [kAccent, Color(0xFF6C4CF0), kAmber, kAccent]),
                    boxShadow: [BoxShadow(color: kAccent.withValues(alpha: .35), blurRadius: 40, spreadRadius: 2)],
                  ),
                  child: Container(
                    margin: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: kSurface),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(active ? Icons.pause : Icons.play_arrow, size: 44, color: kInk),
                        const SizedBox(height: 4),
                        const Text('Моя волна', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Quick extends StatelessWidget {
  const _Quick({required this.icon, required this.label, required this.count, required this.onTap});
  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: kSurface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(icon, color: kAccent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                Text('$count', style: const TextStyle(color: kMuted)),
              ],
            ),
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
      padding: const EdgeInsets.fromLTRB(16, 24, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
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
      height: 182,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tracks.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
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
      height: 182,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: albums.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
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
      width: 128,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Cover(art, size: 128, radius: 10, seed: seed),
            const SizedBox(height: 8),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
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

class _CatalogPageState extends State<CatalogPage> {
  final _query = TextEditingController();
  late Future<List<Album>> _albums = catalog.search('');

  void _search() => setState(() => _albums = catalog.search(_query.text));

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 4),
              child: Text('Каталог', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Релизы под свободными лицензиями и концертные записи с Internet Archive.',
                  style: TextStyle(color: kMuted)),
            ),
            _SearchField(controller: _query, hint: 'Исполнитель, релиз или жанр', onSearch: _search),
            Expanded(
              child: FutureBuilder<List<Album>>(
                future: _albums,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return _Message('Каталог не отвечает. Проверьте подключение к интернету.',
                        action: 'Повторить', onAction: _search);
                  }
                  final albums = snap.data ?? const [];
                  if (albums.isEmpty) {
                    return const _Message(
                        'В открытом каталоге этого нет. Здесь только свободная музыка и концертные записи. Популярных артистов можно услышать по радио на Главной.');
                  }
                  return ListView.builder(
                    itemCount: albums.length,
                    itemBuilder: (context, i) {
                      final a = albums[i];
                      return ListTile(
                        leading: Cover(a.art, size: 52, seed: a.id),
                        title: Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(a.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: const Icon(Icons.chevron_right, color: kMuted),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AlbumPage(a))),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
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
                      Cover(a.art, size: 180, radius: 14, seed: a.id),
                      const SizedBox(height: 14),
                      Text(a.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
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
              _Filter.all => library.all.where((t) => !t.isRadio).toList(),
              _Filter.favorites => library.favoriteTracks,
              _Filter.stations => library.stations,
              _Filter.downloaded => library.downloaded,
              _Filter.playlists => const <Track>[],
            };
            final tracks = Library.filter(inFilter, _query);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 4, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('Медиатека', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
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
                            onSelected: (_) => setState(() => _filter = f),
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
                              onTap: () => tracks[i].isRadio
                                  ? player.playAll([tracks[i]])
                                  : player.playAll(tracks, start: i),
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
