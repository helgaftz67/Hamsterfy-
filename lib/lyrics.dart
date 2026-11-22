import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// One line of time-synced lyrics.
class LyricLine {
  const LyricLine(this.at, this.text);
  final Duration at;
  final String text;
}

/// Lyrics of one song: plain text, and timed lines when the database has
/// them.
class Lyrics {
  const Lyrics({this.plain = '', this.synced = const [], this.instrumental = false});
  final String plain;
  final List<LyricLine> synced;
  final bool instrumental;

  bool get isEmpty => plain.trim().isEmpty && synced.isEmpty && !instrumental;

  /// Index of the line being sung at [position], or -1 before the first.
  int lineAt(Duration position) {
    var i = -1;
    for (var k = 0; k < synced.length; k++) {
      if (synced[k].at > position) break;
      i = k;
    }
    return i;
  }

  /// Parses the LRC format: `[mm:ss.xx] words`.
  static List<LyricLine> parseLrc(String lrc) {
    final stamp = RegExp(r'\[(\d+):(\d+)(?:[.:](\d+))?\]');
    final out = <LyricLine>[];
    for (final raw in const LineSplitter().convert(lrc)) {
      final marks = stamp.allMatches(raw).toList();
      if (marks.isEmpty) continue;
      final text = raw.substring(marks.last.end).trim();
      for (final m in marks) {
        final frac = m.group(3) ?? '0';
        final ms = (int.parse(frac) * 1000 / _pow10(frac.length)).round();
        out.add(LyricLine(
          Duration(minutes: int.parse(m.group(1)!), seconds: int.parse(m.group(2)!), milliseconds: ms),
          text,
        ));
      }
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  static int _pow10(int n) {
    var v = 1;
    for (var i = 0; i < n; i++) {
      v *= 10;
    }
    return v;
  }
}

/// Looks lyrics up in LRCLIB, an open lyrics database. Nothing is stored
/// in the app beyond a per-session memory cache.
class LyricsService {
  LyricsService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  final _cache = <String, Lyrics?>{};

  /// Lyrics for [t], or null when the database has none. Throws when the
  /// service cannot be reached.
  Future<Lyrics?> find(Track t) async {
    if (_cache.containsKey(t.id)) return _cache[t.id];
    Lyrics? found;
    for (final (artist, title) in candidates(t)) {
      found = await _search(artist, title, t.durationMs);
      if (found != null) break;
    }
    return _cache[t.id] = found;
  }

  /// Ways to read the track's tags. Uploads are often titled
  /// "Artist - Song (Official Video)" under the uploader's name.
  static List<(String, String)> candidates(Track t) {
    String clean(String s) =>
        s.replaceAll(RegExp(r'[\(\[][^\)\]]*[\)\]]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    final title = clean(t.title);
    final out = <(String, String)>[];
    final parts = t.title.split(RegExp(r'\s+[-–—]\s+'));
    if (parts.length >= 2) out.add((clean(parts.first), clean(parts.sublist(1).join(' - '))));
    if (title.isNotEmpty) out.add((t.artist.trim(), title));
    return out;
  }

  Future<Lyrics?> _search(String artist, String title, int durationMs) async {
    if (title.isEmpty) return null;
    final uri = Uri.https('lrclib.net', '/api/search', {
      'track_name': title,
      if (artist.isNotEmpty) 'artist_name': artist,
    });
    final res = await _client.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) throw Exception('Сервис текстов ответил ${res.statusCode}');
    return pick(utf8.decode(res.bodyBytes), durationMs);
  }

  /// Chooses the best row of a search answer: with lyrics, synced first,
  /// closest in length to the track.
  static Lyrics? pick(String body, int durationMs) {
    final rows = (jsonDecode(body) as List).whereType<Map<String, dynamic>>().toList();
    Lyrics? best;
    var bestScore = double.negativeInfinity;
    for (final r in rows) {
      final plain = (r['plainLyrics'] ?? '').toString();
      final lrc = (r['syncedLyrics'] ?? '').toString();
      final instrumental = r['instrumental'] == true;
      if (plain.trim().isEmpty && lrc.trim().isEmpty && !instrumental) continue;
      final gap = durationMs > 0 && r['duration'] is num
          ? ((r['duration'] as num) * 1000 - durationMs).abs() / 1000
          : 0.0;
      // Timed lines are useless if they belong to a different cut.
      final timed = lrc.trim().isNotEmpty && gap <= 5;
      final score = (timed ? 100 : 0) - gap;
      if (score > bestScore) {
        bestScore = score;
        best = Lyrics(plain: plain, synced: timed ? Lyrics.parseLrc(lrc) : const [], instrumental: instrumental);
      }
    }
    return best;
  }
}
