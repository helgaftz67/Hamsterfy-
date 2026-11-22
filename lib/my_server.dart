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
  ServerSearch(this.tracks, this.problems);
  final List<Track> tracks;
  final List<String> problems;
}

/// Client for the personal Hamsterfy server (see bin/server.dart).
class MyServer {
  MyServer(String address, {this.token, http.Client? client})
      : base = normalize(address),
        _client = client ?? http.Client();

  final String base;
  final String? token;
  final http.Client _client;

  /// Accepts "192.168.1.5:8787", "http://host:8787/" and the like.
  static String normalize(String address) {
    var a = address.trim();
    if (a.isEmpty) return a;
    if (!a.startsWith('http://') && !a.startsWith('https://')) a = 'http://$a';
    while (a.endsWith('/')) {
      a = a.substring(0, a.length - 1);
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
    final body = await _get('/health');
    if (body['ok'] != true) throw ServerProblem('По этому адресу отвечает не сервер Hamsterfy.');
    return body['tracks'] as int? ?? 0;
  }

  Future<ServerSearch> search(String query) async {
    final body = await _get('/search', {'q': query});
    return ServerSearch(
      [for (final r in (body['results'] as List? ?? const [])) track(r as Map<String, dynamic>)],
      [
        for (final e in (body['errors'] as List? ?? const []))
          '${_sourceName(e['source'].toString())}: ${e['message']}',
      ],
    );
  }

  /// Asks the server to keep a track in its own folder.
  Future<Track> save(Track t) async => track((await _get('/save', {'id': t.id}))['track'] as Map<String, dynamic>);

  static String _sourceName(String source) => switch (source) {
        'audius' => 'Audius',
        'previews' => 'Каталог песен',
        'library' => 'Папка сервера',
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
