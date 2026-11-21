import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
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
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
                    child: Text('Hamsterfy', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                  ),
                  _Wave(enabled: !empty),
                  if (empty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(24, 4, 24, 16),
                      child: Text(
                        'Волна собирается из вашей коллекции. Добавьте файлы в Медиатеке или отметьте треки из Каталога.',
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
  late Future<List<Album>> _results = catalog.search('');

  void _search() => setState(() => _results = catalog.search(_query.text));

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
              child: Text('Свободная музыка с Internet Archive: слушайте и скачивайте без ограничений.',
                  style: TextStyle(color: kMuted)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: SearchBar(
                controller: _query,
                hintText: 'Исполнитель или релиз',
                leading: const Icon(Icons.search),
                elevation: const WidgetStatePropertyAll(0),
                backgroundColor: const WidgetStatePropertyAll(kSurface),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                trailing: [
                  if (_query.text.isNotEmpty)
                    IconButton(
                      tooltip: 'Очистить',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _query.clear();
                        _search();
                      },
                    ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Album>>(
                future: _results,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return _Message(
                      'Каталог не отвечает. Проверьте подключение к интернету.',
                      action: 'Повторить',
                      onAction: _search,
                    );
                  }
                  final albums = snap.data!;
                  if (albums.isEmpty) {
                    return const _Message('Ничего не нашлось. Попробуйте другое название или имя исполнителя.');
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

enum _Filter { all, favorites, downloaded }

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  _Filter _filter = _Filter.all;
  bool _importing = false;

  Future<void> _import() async {
    setState(() => _importing = true);
    try {
      final n = await library.importFiles();
      if (mounted && n > 0) toast(context, 'Добавлено треков: $n');
    } catch (_) {
      if (mounted) toast(context, 'Не удалось добавить файлы. Попробуйте выбрать их снова.');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importing ? null : _import,
        icon: _importing
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5))
            : const Icon(Icons.add),
        label: const Text('Добавить файлы'),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: library,
          builder: (context, _) {
            final tracks = switch (_filter) {
              _Filter.all => library.all,
              _Filter.favorites => library.favoriteTracks,
              _Filter.downloaded => library.downloaded,
            };
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: Text('Медиатека', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final (f, label) in [
                        (_Filter.all, 'Все'),
                        (_Filter.favorites, 'Избранное'),
                        (_Filter.downloaded, 'На устройстве'),
                      ])
                        ChoiceChip(
                          label: Text(label),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: tracks.isEmpty
                      ? _Message(switch (_filter) {
                          _Filter.all =>
                            'Здесь появится ваша музыка. Добавьте файлы с телефона или отметьте треки в Каталоге.',
                          _Filter.favorites => 'Отмечайте треки сердечком, и они соберутся здесь.',
                          _Filter.downloaded => 'Скачанные и добавленные с телефона треки играют без интернета.',
                        })
                      : ListView.builder(
                          padding: const EdgeInsets.only(top: 8, bottom: 88),
                          itemCount: tracks.length,
                          itemBuilder: (context, i) =>
                              TrackTile(tracks[i], onTap: () => player.playAll(tracks, start: i)),
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

/// A plain list of tracks with "play all" and "shuffle".
class TrackListPage extends StatelessWidget {
  const TrackListPage({super.key, required this.title, required this.tracks});
  final String title;
  final List<Track> Function() tracks;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListenableBuilder(
        listenable: library,
        builder: (context, _) {
          final list = tracks();
          if (list.isEmpty) return const _Message('Пока пусто.');
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
              return TrackTile(list[i - 1], onTap: () => player.playAll(list, start: i - 1));
            },
          );
        },
      ),
    );
  }
}
