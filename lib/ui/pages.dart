import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../library.dart';
import '../search/search_service.dart';
import '../main.dart';
import '../models.dart';
import 'aurora.dart';
import 'glass.dart';
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
                padding: EdgeInsets.only(bottom: 24 + dockSpace),
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
                        'Волна собирается из вашей коллекции. Добавьте музыку в Медиатеке или отметьте треки в Поиске.',
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
                                tint: kRose,
                                label: 'Избранное',
                                onTap: () =>
                                    _push(TrackListPage(title: 'Избранное', tracks: () => library.favoriteTracks))),
                            const SizedBox(width: 8),
                            _Quick(
                                icon: Icons.sensors_rounded,
                                tint: kOrange,
                                label: 'Радио',
                                onTap: () => _push(const RadioPage())),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _Quick(
                                icon: Icons.download_done_rounded,
                                tint: const Color(0xFF4FA3A0),
                                label: 'На устройстве',
                                onTap: () =>
                                    _push(TrackListPage(title: 'На устройстве', tracks: () => library.downloaded))),
                            const SizedBox(width: 8),
                            _Quick(
                                icon: Icons.shuffle_rounded,
                                tint: kDuskBlue,
                                label: 'Вперемешку',
                                onTap: empty
                                    ? null
                                    : () => player.playAll(library.songs..shuffle())),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (library.recentlyAdded.length >= 3) ...[
                    _Header('Недавно добавленное',
                        onMore: () => _open('Недавно добавленное', library.recentlyAdded)),
                    _TrackShelf(library.recentlyAdded),
                  ],
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
            borderRadius: BorderRadius.circular(40),
            child: GestureDetector(
              onTap: widget.enabled ? _tap : null,
              child: SizedBox(
                height: 250,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _drift,
                        builder: (_, _) => CustomPaint(painter: DuskPainter(_drift.value, active ? 1.0 : .35)),
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
                          // A glass pill: the sunset shows through it.
                          Center(
                            child: Glass(
                              radius: 30,
                              blur: 14,
                              strength: .55,
                              tint: const Color(0xFFFFFFFF),
                              padding: const EdgeInsets.fromLTRB(18, 11, 24, 11),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(active ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                      color: Colors.white, size: 26),
                                  const SizedBox(width: 8),
                                  Text(active ? 'Пауза' : 'Слушать',
                                      style: const TextStyle(
                                          color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15.5)),
                                ],
                              ),
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
      child: Opacity(
        opacity: onTap == null ? .45 : 1,
        child: Pressable(
          label: label,
          onTap: onTap,
          child: Container(
            height: 66,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              // Dark glass with the tile's colour glowing up from below.
              gradient: RadialGradient(
                center: const Alignment(-.2, 1.5),
                radius: 1.25,
                colors: [tint.withValues(alpha: .70), tint.withValues(alpha: .18), const Color(0xFF141216)],
                stops: const [0, .45, 1],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: .10)),
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: .14),
                    border: Border.all(color: Colors.white.withValues(alpha: .22)),
                  ),
                  child: Icon(icon, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
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
  const CatalogPage({super.key, this.search});

  /// Replaces the app-wide search; tests use it to control timing.
  final Future<SearchResults> Function(String query)? search;

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

enum _Show { all, device }

/// Search tab: one field, one list. Results from the device, the user's
/// server, Audius, the song catalog and Archive releases arrive together,
/// ranked, with duplicates joined and each row marked with its source.
class _CatalogPageState extends State<CatalogPage> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  Timer? _typing;
  Future<SearchResults>? _results;
  List<String> _suggestions = const [];
  _Show _show = _Show.all;

  /// The text the visible results belong to.
  String _searched = '';

  @override
  void dispose() {
    _typing?.cancel();
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Typing: local suggestions at once, the full search after a pause.
  void _typed(String text) {
    _typing?.cancel();
    final q = text.trim();
    if (q.isEmpty) {
      setState(() {
        _results = null;
        _searched = '';
        _suggestions = const [];
      });
      return;
    }
    library.index?.suggest(q).then((found) {
      if (mounted && _query.text.trim() == q) setState(() => _suggestions = found);
    }).catchError((_) {});
    _typing = Timer(const Duration(milliseconds: 450), () => _run(remember: false));
  }

  void _run({bool remember = true}) {
    _typing?.cancel();
    final q = _query.text.trim();
    if (q.isEmpty) return;
    if (remember) library.rememberSearch(q);
    setState(() {
      _searched = q;
      _suggestions = const [];
      // Only the newest request is shown: the list below listens to this
      // future alone, so an older, slower answer cannot replace it.
      _results = (widget.search ?? searchService.search)(q);
    });
  }

  void _use(String text) {
    _query.text = text;
    _query.selection = TextSelection.collapsed(offset: text.length);
    _focus.unfocus();
    _run();
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
              focusNode: _focus,
              hint: 'Песня, исполнитель, альбом или жанр',
              onSearch: _run,
              onChanged: _typed,
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: library,
                builder: (context, _) {
                  if (_suggestions.isNotEmpty && _query.text.trim() != _searched) return _suggestionList();
                  if (_results == null) return _history();
                  return _resultList();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _suggestionList() {
    return ListView(
      padding: EdgeInsets.only(bottom: 24 + dockSpace),
      children: [
        for (final s in _suggestions)
          ListTile(
            dense: true,
            leading: const Icon(Icons.north_west_rounded, size: 18, color: kMuted),
            title: Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
            onTap: () => _use(s),
          ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.search_rounded, size: 18, color: kAccent),
          title: Text('Искать «${_query.text.trim()}» везде',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, color: kAccent)),
          onTap: _run,
        ),
      ],
    );
  }

  Widget _history() {
    final recent = library.searches;
    final genres = library.genres;
    if (recent.isEmpty && genres.isEmpty) {
      return const _Message(
          'Один поиск сразу по вашей музыке, Audius, каталогу песен и свободным релизам. Сначала показывается то, что играет целиком.');
    }
    return ListView(
      padding: EdgeInsets.only(bottom: 24 + dockSpace),
      children: [
        if (genres.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 6, 20, 10),
            child: Text('Жанры в вашей музыке', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final g in genres)
                  Pressable(
                    label: 'Искать жанр $g',
                    onTap: () => _use(g),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            HSLColor.fromColor(seedColor(g)).withLightness(.46).toColor(),
                            HSLColor.fromColor(seedColor(g)).withLightness(.26).toColor(),
                          ],
                        ),
                      ),
                      child: Text(g, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: Colors.white)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (recent.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 8, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Недавние запросы', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                ),
                TextButton(onPressed: library.clearSearches, child: const Text('Очистить')),
              ],
            ),
          ),
        for (final s in recent)
          ListTile(
            leading: const Icon(Icons.history_rounded, color: kMuted),
            title: Text(s, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              tooltip: 'Убрать из истории',
              icon: const Icon(Icons.close_rounded, size: 18, color: kMuted),
              onPressed: () => library.forgetSearch(s),
            ),
            onTap: () => _use(s),
          ),
      ],
    );
  }

  /// Label and colour for a result: where it is and how it plays.
  static (String, Color) _tag(SearchHit h) => switch (h.availability) {
        Availability.offline => ('На устройстве', const Color(0xFF5ED4A8)),
        Availability.full => (h.source.label, kAccent),
        Availability.preview => ('30 сек', kAmber),
        Availability.unavailable => ('${h.source.label} · недоступен', kMuted),
      };

  Widget _resultList() {
    return FutureBuilder<SearchResults>(
      future: _results,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) {
          return _Message('Поиск не сработал. Попробуйте ещё раз.', action: 'Повторить', onAction: _run);
        }
        final r = snap.data!;
        // Saved copies replace search rows, so likes and downloads show.
        final hits = [
          for (final h in r.hits)
            if (_show == _Show.all ||
                (_show == _Show.device && h.availability == Availability.offline))
              h,
        ];
        final tracks = [for (final h in hits) library.tracks[h.track.id] ?? h.track];
        final albums = _show == _Show.device ? const <Album>[] : r.albums;

        final rows = <Widget>[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(
              children: [
                for (final (show, label) in [(_Show.all, 'Все'), (_Show.device, 'На устройстве')])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _show == show,
                      onSelected: (_) => setState(() => _show = show),
                    ),
                  ),
              ],
            ),
          ),
          for (final p in r.problems)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline_rounded, size: 18, color: kAmber),
                  const SizedBox(width: 8),
                  Expanded(child: Text('$p', style: const TextStyle(color: kAmber, fontSize: 13))),
                ],
              ),
            ),
          if (tracks.isEmpty && albums.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                r.isEmpty
                    ? 'По запросу «${r.query}» ничего нет. Проверьте написание или оставьте только имя исполнителя.'
                    : 'С таким фильтром ничего нет. Выберите «Все».',
                textAlign: TextAlign.center,
                style: const TextStyle(color: kMuted, fontSize: 15),
              ),
            ),
          for (var i = 0; i < tracks.length; i++)
            TrackTile(
              tracks[i],
              playButton: true,
              tag: _tag(hits[i]).$1,
              tagColor: _tag(hits[i]).$2,
              onTap: () {
                library.rememberSearch(r.query);
                player.playAll(tracks, start: i);
              },
            ),
          if (albums.isNotEmpty) ...[
            const _Header('Свободные релизы'),
            for (final a in albums)
              ListTile(
                leading: Cover(a.art, size: 50, radius: 6, seed: a.id),
                title: Text(a.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(color: kSunken, borderRadius: BorderRadius.circular(4)),
                      child: const Text('Archive',
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: kAccent)),
                    ),
                    Expanded(child: Text(a.artist, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ],
                ),
                trailing: const Icon(Icons.chevron_right_rounded, color: kMuted),
                onTap: () {
                  library.rememberSearch(r.query);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => AlbumPage(a)));
                },
              ),
          ],
        ];
        return ListView(padding: EdgeInsets.only(bottom: 24 + dockSpace), children: rows);
      },
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField(
      {required this.controller, required this.hint, required this.onSearch, this.onChanged, this.focusNode});
  final TextEditingController controller;
  final String hint;
  final VoidCallback onSearch;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: SearchBar(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
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
                      onChanged == null ? onSearch() : onChanged!('');
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
                    padding: EdgeInsets.only(bottom: 24 + dockSpace),
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
            padding: EdgeInsets.only(bottom: 24 + dockSpace),
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
                        if (isMobile)
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
                            padding: EdgeInsets.only(bottom: 24 + dockSpace),
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
        _Filter.all => isMobile
            ? _Message(
                'Здесь появится ваша музыка. Приложение может само найти все треки на телефоне.',
                action: 'Найти музыку на телефоне',
                onAction: _scan,
              )
            : _Message(
                'Здесь появится ваша музыка. Добавьте файлы с компьютера или отметьте треки в Поиске.',
                action: 'Добавить файлы',
                onAction: _import,
              ),
        _Filter.favorites => const _Message('Отмечайте треки и станции сердечком, и они соберутся здесь.'),
        _Filter.stations => const _Message('Откройте Радио на Главной и отметьте станцию сердечком, она появится здесь.'),
        _ => const _Message('Треки с телефона и скачанные из каталога играют без интернета.'),
      };

  Widget _playlists() {
    final names = library.playlistNames;
    return ListView(
      padding: EdgeInsets.only(bottom: 24 + dockSpace),
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
            padding: EdgeInsets.only(bottom: 24 + dockSpace),
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
