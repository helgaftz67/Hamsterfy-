import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Open music catalog: Creative Commons netlabel releases hosted by the
/// Internet Archive. No key or account is needed.
class Catalog {
  Catalog({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static const _scope = 'mediatype:audio AND collection:netlabels';

  /// Finds releases by title or artist. An empty query returns popular ones.
  Future<List<Album>> search(String query) async {
    final q = query.trim().replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ').trim();
    final lucene = q.isEmpty ? _scope : '(title:($q) OR creator:($q)) AND $_scope';
    final uri = Uri.https('archive.org', '/advancedsearch.php', {
      'q': lucene,
      'fl[]': ['identifier', 'title', 'creator'],
      'sort[]': 'downloads desc',
      'rows': '40',
      'output': 'json',
    });
    final res = await _client.get(uri).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw Exception('Каталог ответил ${res.statusCode}');
    return parseSearch(utf8.decode(res.bodyBytes));
  }

  /// Loads the tracks of one release.
  Future<List<Track>> tracks(Album album) async {
    final uri = Uri.https('archive.org', '/metadata/${album.id}');
    final res = await _client.get(uri).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw Exception('Каталог ответил ${res.statusCode}');
    return parseTracks(utf8.decode(res.bodyBytes), album);
  }

  static String _text(dynamic v) {
    if (v is List) return v.isEmpty ? '' : v.first.toString();
    return v?.toString() ?? '';
  }

  static List<Album> parseSearch(String body) {
    final docs = (jsonDecode(body)['response']?['docs'] as List?) ?? const [];
    return [
      for (final d in docs)
        if (d is Map && d['identifier'] != null)
          Album(
            id: d['identifier'].toString(),
            title: _text(d['title']).isEmpty ? d['identifier'].toString() : _text(d['title']),
            artist: _text(d['creator']).isEmpty ? 'Неизвестный исполнитель' : _text(d['creator']),
          ),
    ];
  }

  static List<Track> parseTracks(String body, Album album) {
    final files = (jsonDecode(body)['files'] as List?) ?? const [];
    final mp3 = files.whereType<Map>().where((f) {
      final name = f['name']?.toString().toLowerCase() ?? '';
      return name.endsWith('.mp3');
    }).toList();
    // Prefer one encoding per song: originals if present, else derivatives.
    final originals = mp3.where((f) => f['source'] == 'original').toList();
    final chosen = originals.isNotEmpty ? originals : mp3;
    chosen.sort((a, b) => _trackNo(a).compareTo(_trackNo(b)));
    return [
      for (final f in chosen)
        Track(
          id: 'ia:${album.id}/${f['name']}',
          title: _text(f['title']).isEmpty ? _stem(f['name'].toString()) : _text(f['title']),
          artist: _text(f['creator']).isNotEmpty
              ? _text(f['creator'])
              : (_text(f['artist']).isNotEmpty ? _text(f['artist']) : album.artist),
          album: _text(f['album']).isEmpty ? album.title : _text(f['album']),
          url: Uri.https('archive.org', '/download/${album.id}/${f['name']}').toString(),
          art: album.art,
          durationMs: parseLength(_text(f['length'])),
        ),
    ];
  }

  static int _trackNo(Map f) {
    final m = RegExp(r'\d+').firstMatch(_text(f['track']));
    return m == null ? 9999 : int.parse(m.group(0)!);
  }

  static String _stem(String name) {
    final base = name.split('/').last;
    final dot = base.lastIndexOf('.');
    return (dot > 0 ? base.substring(0, dot) : base).replaceAll('_', ' ');
  }

  /// The archive reports length either as seconds ("215.43") or "3:35".
  static int parseLength(String s) {
    if (s.isEmpty) return 0;
    if (s.contains(':')) {
      var total = 0;
      for (final part in s.split(':')) {
        total = total * 60 + (int.tryParse(part.split('.').first) ?? 0);
      }
      return total * 1000;
    }
    return ((double.tryParse(s) ?? 0) * 1000).round();
  }
}
