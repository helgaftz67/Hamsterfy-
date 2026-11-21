import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Search across the world song catalog (iTunes Search API). Every result
/// carries the store's official 30-second preview and a link to the full
/// track in Apple Music; full audio is never fetched from here.
class SongSearch {
  SongSearch({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Future<List<Track>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final uri = Uri.https('itunes.apple.com', '/search', {
      'term': q,
      'media': 'music',
      'entity': 'song',
      'limit': '50',
      // The US storefront has the widest catalog, Russian artists included.
      'country': 'US',
    });
    final res = await _client.get(uri).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw Exception('Поиск ответил ${res.statusCode}');
    return parse(utf8.decode(res.bodyBytes));
  }

  static List<Track> parse(String body) {
    final rows = (jsonDecode(body)['results'] as List?) ?? const [];
    return [
      for (final r in rows.whereType<Map<String, dynamic>>())
        if (r['trackId'] != null && (r['previewUrl'] ?? '').toString().startsWith('http'))
          Track(
            id: 'it:${r['trackId']}',
            title: (r['trackName'] ?? '').toString(),
            artist: (r['artistName'] ?? '').toString(),
            album: (r['collectionName'] ?? '').toString(),
            url: r['previewUrl'].toString(),
            art: (r['artworkUrl100'] ?? '').toString().isEmpty
                ? null
                : r['artworkUrl100'].toString().replaceFirst('100x100bb', '600x600bb'),
            durationMs: r['trackTimeMillis'] as int? ?? 0,
            link: r['trackViewUrl']?.toString(),
          ),
    ];
  }
}
