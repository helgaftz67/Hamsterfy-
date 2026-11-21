import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Internet radio stations from the community directory Radio Browser.
/// Stations are represented as tracks with an endless stream.
class RadioDirectory {
  RadioDirectory({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static const _host = 'all.api.radio-browser.info';

  Future<List<dynamic>> _get(Map<String, String> params) async {
    final uri = Uri.https(_host, '/json/stations/search', {
      'order': 'clickcount',
      'reverse': 'true',
      'hidebroken': 'true',
      'limit': '60',
      ...params,
    });
    final res = await _client.get(uri, headers: {'User-Agent': 'Hamsterfy/0.3'}).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw Exception('Каталог радио ответил ${res.statusCode}');
    return jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
  }

  /// Finds stations by name or genre. An empty query returns the most
  /// popular Russian stations.
  Future<List<Track>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return parse(await _get({'countrycode': 'RU'}));
    final results = await Future.wait([_get({'name': q}), _get({'tag': q.toLowerCase()})]);
    return parse([...results[0], ...results[1]]);
  }

  /// Converts directory rows to tracks: drops duplicates and rows without a
  /// stream, most listened stations first.
  static List<Track> parse(List<dynamic> rows) {
    final byId = <String, Map<String, dynamic>>{};
    for (final r in rows.whereType<Map<String, dynamic>>()) {
      final id = r['stationuuid']?.toString() ?? '';
      final url = (r['url_resolved'] ?? r['url'] ?? '').toString();
      if (id.isEmpty || !url.startsWith('http')) continue;
      byId.putIfAbsent(id, () => r);
    }
    final sorted = byId.values.toList()
      ..sort((a, b) => ((b['clickcount'] as int?) ?? 0).compareTo((a['clickcount'] as int?) ?? 0));
    return [
      for (final r in sorted)
        Track(
          id: 'radio:${r['stationuuid']}',
          title: (r['name'] ?? '').toString().trim().isEmpty ? 'Без названия' : r['name'].toString().trim(),
          artist: _describe(r),
          album: 'Радио',
          url: (r['url_resolved'] ?? r['url']).toString(),
          art: (r['favicon'] ?? '').toString().startsWith('https') ? r['favicon'].toString() : null,
        ),
    ];
  }

  static String _describe(Map<String, dynamic> r) {
    final tags = (r['tags'] ?? '').toString().split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).take(3);
    final country = (r['country'] ?? '').toString().trim();
    final parts = ['Радио', if (country.isNotEmpty) country, if (tags.isNotEmpty) tags.join(', ')];
    return parts.join(' · ');
  }
}
