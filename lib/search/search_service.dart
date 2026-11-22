import 'dart:async';

import '../models.dart';

/// Where a search result came from.
enum SearchSource {
  local('На устройстве'),
  server('Мой сервер'),
  audius('Audius'),
  archive('Archive'),
  previews('Каталог песен');

  const SearchSource(this.label);
  final String label;
}

/// What the app can do with a result, best first.
enum Availability {
  /// The file is on this device: plays without a connection.
  offline('офлайн'),

  /// The whole track streams from its source.
  full('целиком'),

  /// Only a short official preview is playable.
  preview('30 сек'),

  /// Listed for information; nothing can be played.
  unavailable('недоступен');

  const Availability(this.label);
  final String label;
}

/// One row of search results.
class SearchHit {
  SearchHit(this.track, this.source, this.availability, this.score, {Set<SearchSource>? alsoIn})
      : alsoIn = alsoIn ?? {};

  final Track track;
  final SearchSource source;
  final Availability availability;
  final double score;

  /// Other sources that had the same song; the best copy is the one shown.
  final Set<SearchSource> alsoIn;
}

/// A source the search could not use, in words fit to show the user.
class SourceProblem {
  SourceProblem(this.source, this.message);
  final SearchSource source;
  final String message;

  @override
  String toString() => '${source.label}: $message';
}

class SearchResults {
  SearchResults(this.query, this.hits, this.albums, this.problems);
  final String query;
  final List<SearchHit> hits;

  /// Whole releases (the Internet Archive answers with albums, not tracks).
  final List<Album> albums;
  final List<SourceProblem> problems;

  bool get isEmpty => hits.isEmpty && albums.isEmpty;
}

/// A catalog the service can ask for tracks.
class TrackSource {
  TrackSource(this.source, this.search, {this.timeout = const Duration(seconds: 8)});
  final SearchSource source;
  final Future<List<Track>> Function(String query) search;
  final Duration timeout;
}

/// Text clean-up shared by ranking, de-duplication and the local index.
abstract final class SearchText {
  static final _brackets = RegExp(r'[\(\[\{][^\)\]\}]*[\)\]\}]');
  static final _featuring = RegExp(r'\s(feat\.?|ft\.?|featuring|при уч\.?|при участии)\s.*$', caseSensitive: false);
  static final _dashTail = RegExp(
      r'\s[-–—]\s.*\b(remaster(ed)?|version|edit|mix|remix|live|acoustic|mono|stereo|bonus|deluxe|single)\b.*$',
      caseSensitive: false);
  static final _notWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

  /// Words that mark a different recording of the same song.
  static const _variants = {
    'remix': 'remix', 'mix': 'remix', 'rmx': 'remix', 'ремикс': 'remix',
    'live': 'live', 'концерт': 'live', 'концертная': 'live', 'живой': 'live',
    'acoustic': 'acoustic', 'акустика': 'acoustic', 'акустическая': 'acoustic', 'unplugged': 'acoustic',
    'instrumental': 'instrumental', 'инструментал': 'instrumental', 'минус': 'instrumental', 'karaoke': 'instrumental',
    'караоке': 'instrumental',
    'cover': 'cover', 'кавер': 'cover',
    'slowed': 'slowed', 'reverb': 'slowed', 'sped': 'sped', 'nightcore': 'sped', 'speed': 'sped',
  };

  /// Lower case, "ё" as "е", punctuation and repeated spaces removed.
  static String normalize(String text) =>
      text.toLowerCase().replaceAll('ё', 'е').replaceAll(_notWord, ' ').trim().replaceAll(RegExp(r'\s+'), ' ');

  static List<String> words(String text) => normalize(text).split(' ').where((w) => w.isNotEmpty).toList();

  /// The song's own name: no "(Remastered 2011)", "[Live]", "feat. X".
  static String baseTitle(String title) {
    var t = title.replaceAll(_brackets, ' ');
    t = t.replaceFirst(_featuring, '');
    t = t.replaceFirst(_dashTail, '');
    final clean = normalize(t);
    // A title that was nothing but a bracket keeps its original words.
    return clean.isEmpty ? normalize(title) : clean;
  }

  /// "remix", "live" and so on, or an empty string for the plain recording.
  static String variant(String title) {
    final found = <String>{};
    for (final w in words(title)) {
      final v = _variants[w];
      if (v != null) found.add(v);
    }
    return (found.toList()..sort()).join('+');
  }

  /// The main artist: "A feat. B", "A & B", "A, B" all give "a".
  static String mainArtist(String artist) {
    final cut = artist.split(RegExp(r'\s(feat\.?|ft\.?|featuring|&|x|и)\s|,|;|/', caseSensitive: false)).first;
    final clean = normalize(cut);
    return clean.isEmpty ? normalize(artist) : clean;
  }

  /// Two results with the same key are the same recording of one song.
  static String songKey(Track t) => '${mainArtist(t.artist)}|${baseTitle(t.title)}|${variant(t.title)}';
}

/// One search over every source at once.
///
/// Sources run in parallel, each with its own timeout. A source that
/// fails or is too slow is reported in [SearchResults.problems]; the rest
/// of the answer is unaffected.
class SearchService {
  SearchService({required this.sources, this.albumSearch, this.albumTimeout = const Duration(seconds: 8)});

  final List<TrackSource> sources;

  /// Optional search for whole releases (Internet Archive).
  final Future<List<Album>> Function(String query)? albumSearch;
  final Duration albumTimeout;

  Future<SearchResults> search(String query) async {
    final q = query.trim();
    if (SearchText.normalize(q).isEmpty) return SearchResults(q, const [], const [], const []);

    final problems = <SourceProblem>[];
    Future<T> guarded<T>(SearchSource source, Duration timeout, Future<T> Function() run, T empty) async {
      try {
        return await run().timeout(timeout);
      } on TimeoutException {
        problems.add(SourceProblem(source, 'не ответил за ${timeout.inSeconds} с'));
      } catch (e) {
        problems.add(SourceProblem(source, _explain(e)));
      }
      return empty;
    }

    final trackRuns = Future.wait([
      for (final s in sources)
        guarded(s.source, s.timeout, () => s.search(q), const <Track>[]).then((tracks) => (s.source, tracks)),
    ]);
    final albumRun = albumSearch == null
        ? Future.value(const <Album>[])
        : guarded(SearchSource.archive, albumTimeout, () => albumSearch!(q), const <Album>[]);
    final (found, albums) = await (trackRuns, albumRun).wait;

    final hits = <SearchHit>[
      for (final (source, tracks) in found)
        for (final t in tracks) SearchHit(t, source, availabilityOf(t), score(q, t)),
    ];
    return SearchResults(q, rank(merge(hits)), albums, problems);
  }

  static String _explain(Object e) {
    final text = e.toString();
    if (text.contains('SocketException') || text.contains('Failed host lookup') || text.contains('ClientException')) {
      return 'нет связи с источником';
    }
    return text.replaceFirst('Exception: ', '');
  }

  static Availability availabilityOf(Track t) {
    if (t.isLocal) return Availability.offline;
    if (t.isUnavailable) return Availability.unavailable;
    if (t.isPreview) return Availability.preview;
    return Availability.full;
  }

  /// How well [t] answers [query]. Exact title and artist matches lead,
  /// partial matches follow; other recordings (remix, live) drop a little
  /// unless the query asks for them.
  static double score(String query, Track t) {
    final q = SearchText.normalize(query);
    final qWords = q.split(' ').where((w) => w.isNotEmpty).toList();
    final title = SearchText.baseTitle(t.title);
    final fullTitle = SearchText.normalize(t.title);
    final artist = SearchText.normalize(t.artist);
    final main = SearchText.mainArtist(t.artist);
    final album = SearchText.normalize(t.album);

    var s = 0.0;
    final both = {'$main $title', '$title $main', '$artist $title', '$title $artist'};
    if (both.contains(q)) {
      s = 120; // "artist title", exactly
    } else if (q == title || q == fullTitle) {
      s = 100; // the title, exactly
    } else if (q == main || q == artist) {
      s = 80; // the artist, exactly
    } else {
      final inTitle = qWords.where((w) => _hasWord(title, w) || _hasWord(fullTitle, w)).length;
      final inArtist = qWords.where((w) => _hasWord(artist, w)).length;
      final inAlbum = qWords.where((w) => _hasWord(album, w)).length;
      final covered = qWords.where((w) => _hasWord('$fullTitle $artist $album', w)).length;
      if (covered == 0) return 0;
      final share = covered / qWords.length;
      s = 60 * share;
      if (covered == qWords.length && inTitle > 0 && inArtist > 0) s += 25; // words split over title and artist
      if (title.startsWith(q) || fullTitle.startsWith(q)) s += 15;
      if (artist.startsWith(q)) s += 8;
      s += 4 * inTitle / qWords.length + 2 * inArtist / qWords.length + inAlbum / qWords.length;
      // Prefix-only matches ("нoч" for "ночной") count for less.
      final whole = qWords.where((w) => ' $fullTitle $artist $album '.contains(' $w ')).length;
      s -= 6 * (covered - whole) / qWords.length;
      // A partial match never outranks an exact title or artist match.
      if (s > 79) s = 79;
    }

    final variant = SearchText.variant(t.title);
    if (variant.isNotEmpty) {
      final asked = SearchText.variant(query);
      if (!variant.split('+').any(asked.split('+').contains)) s -= 14;
    }
    return s;
  }

  static bool _hasWord(String text, String word) => ' $text'.contains(' $word');

  /// Joins copies of the same recording. The copy that plays best stays:
  /// on the device, then a full stream, then a preview.
  static List<SearchHit> merge(List<SearchHit> hits) {
    final best = <String, SearchHit>{};
    for (final h in hits) {
      final key = SearchText.songKey(h.track);
      final kept = best[key];
      if (kept == null) {
        best[key] = h;
        continue;
      }
      final winner = _better(h, kept) ? h : kept;
      final loser = identical(winner, h) ? kept : h;
      best[key] = SearchHit(
        winner.track,
        winner.source,
        winner.availability,
        winner.score > loser.score ? winner.score : loser.score,
        alsoIn: {...winner.alsoIn, ...loser.alsoIn, loser.source}..remove(winner.source),
      );
    }
    return best.values.toList();
  }

  static bool _better(SearchHit a, SearchHit b) {
    if (a.availability != b.availability) return a.availability.index < b.availability.index;
    if (a.source != b.source) return a.source.index < b.source.index;
    return a.score > b.score;
  }

  /// Orders hits by relevance, then by how well they can be played.
  static List<SearchHit> rank(List<SearchHit> hits) {
    const bonus = {
      Availability.offline: 12.0,
      Availability.full: 6.0,
      Availability.preview: 0.0,
      Availability.unavailable: -30.0,
    };
    double total(SearchHit h) => h.score + bonus[h.availability]!;
    return hits.where((h) => h.score > 0).toList()
      ..sort((a, b) {
        final byScore = total(b).compareTo(total(a));
        if (byScore != 0) return byScore;
        final byPlay = a.availability.index.compareTo(b.availability.index);
        if (byPlay != 0) return byPlay;
        return a.track.title.toLowerCase().compareTo(b.track.title.toLowerCase());
      });
  }
}
