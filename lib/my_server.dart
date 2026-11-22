import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// What the server said went wrong, in words fit to show the user.
class ServerProblem implements Exception {
  ServerProblem(this.message, {this.code});
  final String message;
  final String? code;

  @override
  String toString() => message;
}

/// Answer to a search: the tracks, plus sources that failed on the way.
class ServerSearch {
  ServerSearch(this.tracks, this.problems, [this.albums = const []]);
  final List<Track> tracks;
  final List<String> problems;

  /// Free releases the server found (Internet Archive).
  final List<Album> albums;
}

/// Client for the personal Hamsterfy server (see bin/server.dart).
class MyServer {
  MyServer(String address, {this.token, http.Client? client})
      : base = normalize(address),
        _client = client ?? http.Client();

  final String base;
  final String? token;
  final http.Client _client;

  /// The port the server listens on unless told otherwise.
  static const defaultPort = 8765;

  /// Accepts "192.168.1.5", "192.168.1.5:8765", "http://host:8765/" and
  /// the like. An address without a port gets the server's usual one.
  static String normalize(String address) {
    var a = address.trim();
    if (a.isEmpty) return a;
    final hadScheme = a.startsWith('http://') || a.startsWith('https://');
    if (!hadScheme) a = 'http://$a';
    while (a.endsWith('/')) {
      a = a.substring(0, a.length - 1);
    }
    final uri = Uri.tryParse(a);
    // Only bare http hosts get the port: an https address behind a proxy
    // or tunnel is expected to be complete as typed.
    if (uri != null && uri.hasAuthority && !uri.hasPort && uri.scheme == 'http' && uri.path.isEmpty) {
      a = '$a:$defaultPort';
    }
    return a;
  }

  Uri _uri(String path, [Map<String, String> query = const {}]) {
    final u = Uri.parse('$base$path');
    return u.replace(queryParameters: {
      ...u.queryParameters,
      ...query,
      if (token != null && token!.isNotEmpty) 'token': token!,
    });
  }

  /// Turns a server path such as "/stream/ID" into a playable address.
  String absolute(String url) => url.startsWith('/') ? _uri(url).toString() : url;

  Future<Map<String, dynamic>> _get(String path, [Map<String, String> query = const {}]) async {
    http.Response res;
    try {
      res = await _client.get(_uri(path, query)).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw ServerProblem('Сервер не ответил за 30 секунд. Проверьте, что он запущен и адрес верный.');
    } catch (e) {
      throw ServerProblem('Не удалось связаться с сервером по адресу $base. Проверьте адрес и сеть.');
    }
    Map<String, dynamic>? body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {}
    if (res.statusCode != 200) {
      final error = body?['error'];
      if (error is Map) throw ServerProblem(error['message'].toString(), code: error['code']?.toString());
      throw ServerProblem('Сервер ответил ошибкой ${res.statusCode}.');
    }
    if (body == null) throw ServerProblem('По этому адресу отвечает не сервер Hamsterfy.');
    return body;
  }

  /// Number of tracks in the server's folder; throws when it is unreachable.
  Future<int> health() async {
    final body = await _get('/api/status');
    if (body['ok'] != true) throw ServerProblem('По этому адресу отвечает не сервер Hamsterfy.');
    return body['tracks'] as int? ?? 0;
  }

  /// Searches through the server. [sources] narrows it, e.g. "library"
  /// for the server's own folder only.
  Future<ServerSearch> search(String query, {String? sources}) async {
    final body = await _get('/api/search', {'q': query, 'sources': ?sources});
    return ServerSearch(
      [for (final r in (body['results'] as List? ?? const [])) track(r as Map<String, dynamic>)],
      [
        for (final e in (body['errors'] as List? ?? const []))
          '${_sourceName(e['source'].toString())}: ${e['message']}',
      ],
      [
        for (final a in (body['albums'] as List? ?? const []))
          Album(id: a['id'].toString(), title: (a['title'] ?? '').toString(), artist: (a['artist'] ?? '').toString()),
      ],
    );
  }

  /// Asks the server to keep a track in its own folder.
  Future<Track> save(Track t) async => track((await _get('/api/save', {'id': t.id}))['track'] as Map<String, dynamic>);

  static String _sourceName(String source) => switch (source) {
        'audius' => 'Audius',
        'previews' => 'Каталог песен',
        'library' => 'Папка сервера',
        'archive' => 'Archive',
        _ => source,
      };

  Track track(Map<String, dynamic> r) {
    final url = r['url'] as String?;
    final art = r['art'] as String?;
    return Track(
      id: r['id'].toString(),
      title: (r['title'] ?? '').toString(),
      artist: (r['artist'] ?? '').toString(),
      album: (r['album'] ?? '').toString(),
      url: url == null ? null : absolute(url),
      art: art == null ? null : absolute(art),
      durationMs: r['durationMs'] as int? ?? 0,
      link: r['link'] as String?,
      canSave: r['canSave'] as bool? ?? false,
    );
  }
}
