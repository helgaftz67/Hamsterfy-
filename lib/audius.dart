import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Audius: an open music platform where artists publish their own tracks.
/// Its public API lets third-party apps search and stream whole tracks.
/// Docs: https://docs.audius.co/api/
class Audius {
  Audius({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static const _host = 'api.audius.co';
  static const appName = 'Hamsterfy';

  /// Finds tracks by title or artist name.
  Future<List<Track>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final uri = Uri.https(_host, '/v1/tracks/search', {'query': q, 'limit': '50', 'app_name': appName});
    final res = await _client.get(uri).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw Exception('Audius ответил ${res.statusCode}');
    return parse(utf8.decode(res.bodyBytes));
  }

  /// Address that redirects to the track's MP3. The redirect is signed and
  /// short-lived, so the player asks for it anew on every play.
  static String streamUrl(String trackId) =>
      Uri.https(_host, '/v1/tracks/$trackId/stream', {'app_name': appName}).toString();

  /// True when anyone may stream the whole track without an account:
  /// published, not deleted, not gated behind a purchase or a specific app.
  static bool isFreelyStreamable(Map<String, dynamic> t) {
    final access = t['access'];
    final keys = t['allowed_api_keys'];
    return t['is_streamable'] == true &&
        t['is_stream_gated'] != true &&
        t['is_delete'] != true &&
        t['is_unlisted'] != true &&
        t['is_available'] != false &&
        (access is! Map || access['stream'] != false) &&
        (keys is! List || keys.isEmpty);
  }

  /// Converts API rows to tracks. A track that cannot be streamed freely
  /// keeps its title and cover but gets no stream address, so the UI can
  /// show it without a play button.
  static List<Track> parse(String body) {
    final rows = (jsonDecode(body)['data'] as List?) ?? const [];
    return [
      for (final t in rows.whereType<Map<String, dynamic>>())
        if (t['id'] != null)
          Track(
            id: 'au:${t['id']}',
            title: (t['title'] ?? '').toString().trim(),
            artist: _artist(t),
            album: 'Audius',
            url: isFreelyStreamable(t) ? streamUrl(t['id'].toString()) : null,
            art: _art(t),
            durationMs: ((t['duration'] as num?) ?? 0).round() * 1000,
            link: t['permalink'] == null ? null : 'https://audius.co${t['permalink']}',
            // Offline copies only when the artist allows downloads.
            canSave: t['is_downloadable'] == true && t['is_download_gated'] != true,
          ),
    ];
  }

  static String _artist(Map<String, dynamic> t) {
    final user = t['user'];
    final name = user is Map ? (user['name'] ?? user['handle'] ?? '').toString().trim() : '';
    return name.isEmpty ? 'Неизвестный исполнитель' : name;
  }

  static String? _art(Map<String, dynamic> t) {
    final art = t['artwork'];
    if (art is! Map) return null;
    final url = (art['480x480'] ?? art['1000x1000'] ?? art['150x150'])?.toString();
    return (url != null && url.startsWith('http')) ? url : null;
  }
}
