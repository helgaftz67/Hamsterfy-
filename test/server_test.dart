import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hamsterfy/server/music_server.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Upstream catalogs are faked: Audius answers, the preview search is down.
http.Client fakeCatalogs({bool audiusDown = false}) => MockClient((req) async {
      if (req.url.host == 'api.audius.co') {
        if (audiusDown) return http.Response('boom', 503);
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'data': [
              {
                'id': 'A1', 'title': 'Тихая волна', 'duration': 200, 'permalink': '/a/b',
                'user': {'name': 'Артист'}, 'is_streamable': true, 'is_stream_gated': false,
                'access': {'stream': true}, 'is_downloadable': false,
              },
              {'id': 'A2', 'title': 'Закрытый', 'duration': 100, 'user': {'name': 'Артист'}, 'is_streamable': false},
            ],
          })),
          200,
        );
      }
      return http.Response('down', 500);
    });

void main() {
  late Directory dir;
  late HttpServer http_;
  late MusicServer server;
  late String base;
  final client = HttpClient();

  Future<(int, dynamic, HttpHeaders)> get(String path, {Map<String, String> headers = const {}}) async {
    final req = await client.getUrl(Uri.parse('$base$path'));
    headers.forEach(req.headers.set);
    final res = await req.close();
    final bytes = await res.fold<List<int>>([], (a, b) => a..addAll(b));
    dynamic body = bytes;
    if (res.headers.contentType?.subType == 'json') body = jsonDecode(utf8.decode(bytes));
    if (res.headers.contentType?.subType == 'html') body = utf8.decode(bytes);
    return (res.statusCode, body, res.headers);
  }

  Future<void> boot({String? token, bool audiusDown = false}) async {
    server = MusicServer(music: dir, token: token, client: fakeCatalogs(audiusDown: audiusDown));
    await server.scan();
    http_ = await server.start(port: 0, address: InternetAddress.loopbackIPv4);
    base = 'http://127.0.0.1:${http_.port}';
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hamsterfy_srv');
    // Not real audio: tags cannot be read, so the file name becomes the title.
    await File('${dir.path}/Ночной город.mp3').writeAsBytes(List.generate(1000, (i) => i % 256));
    await File('${dir.path}/notes.txt').writeAsString('not music');
  });

  tearDown(() async {
    await http_.close(force: true);
    await dir.delete(recursive: true);
  });

  test('health, library and status page', () async {
    await boot();
    final (status, health, _) = await get('/health');
    expect(status, 200);
    expect(health['ok'], isTrue);
    expect(health['tracks'], 1);
    final (_, lib, _) = await get('/library');
    expect(lib['tracks'].single['title'], 'Ночной город');
    expect(lib['tracks'].single['url'], startsWith('/stream/'));
    final (_, page, _) = await get('/');
    expect(page, contains('Hamsterfy Server'));
    expect(page, contains('Журнал ошибок'));
  });

  test('search merges sources and reports the one that failed', () async {
    await boot();
    final (status, body, _) = await get('/search?q=${Uri.encodeQueryComponent('ночной')}');
    expect(status, 200);
    expect(body['results'].first['source'], 'library');
    final (_, mixed, _) = await get('/search?q=${Uri.encodeQueryComponent('волна')}');
    final rows = mixed['results'] as List;
    expect(rows.map((r) => r['id']), ['au:A1', 'au:A2']);
    expect(rows.first['full'], isTrue);
    expect(rows.last['full'], isFalse);
    // The preview catalog is down: the answer still arrives, with the reason.
    expect(mixed['errors'].single['source'], 'previews');
    expect(server.errors.any((e) => e.where == 'search/previews'), isTrue);
    final (_, journal, _) = await get('/errors');
    expect(journal['count'], greaterThan(0));
  });

  test('stream supports ranges for seeking', () async {
    await boot();
    final (_, lib, _) = await get('/library');
    final url = lib['tracks'].single['url'] as String;
    final (full, all, _) = await get(url);
    expect(full, 200);
    expect((all as List).length, 1000);
    final (part, bytes, headers) = await get(url, headers: {'Range': 'bytes=500-509'});
    expect(part, 206);
    expect(headers.value('content-range'), 'bytes 500-509/1000');
    expect(bytes, List.generate(10, (i) => (500 + i) % 256));
    final (tail, last, _) = await get(url, headers: {'Range': 'bytes=-4'});
    expect(tail, 206);
    expect(last, [996 % 256, 997 % 256, 998 % 256, 999 % 256]);
  });

  test('every mistake gets a clear JSON error with the right status', () async {
    await boot();
    Future<void> expectError(String path, int status, String code, {Map<String, String> headers = const {}}) async {
      final (got, body, _) = await get(path, headers: headers);
      expect(got, status, reason: path);
      expect(body['error']['code'], code, reason: path);
      expect(body['error']['message'], isNotEmpty);
    }

    await expectError('/search', 400, 'missing_query');
    await expectError('/search?q=x&sources=napster', 400, 'unknown_source');
    await expectError('/stream', 400, 'missing_id');
    await expectError('/stream/nope', 404, 'track_not_found');
    await expectError('/cover/nope', 404, 'track_not_found');
    await expectError('/nothing/here', 404, 'not_found');
    final (_, lib, _) = await get('/library');
    final url = lib['tracks'].single['url'] as String;
    await expectError(url, 416, 'range_not_satisfiable', headers: {'Range': 'bytes=5000-6000'});
    await expectError(url, 416, 'bad_range', headers: {'Range': 'lines=1-2'});
    await expectError(url.replaceFirst('/stream/', '/cover/'), 404, 'no_cover');
    final post = await client.postUrl(Uri.parse('$base/health'));
    final res = await post.close();
    expect(res.statusCode, 405);
    await res.drain<void>();
  });

  test('token protects every route', () async {
    await boot(token: 's3cret');
    final (denied, body, _) = await get('/health');
    expect(denied, 401);
    expect(body['error']['code'], 'unauthorized');
    expect((await get('/health?token=s3cret')).$1, 200);
    expect((await get('/health', headers: {'Authorization': 'Bearer s3cret'})).$1, 200);
    expect((await get('/health?token=wrong')).$1, 401);
  });

  test('a deleted file is reported, and rescan drops it', () async {
    await boot();
    final (_, lib, _) = await get('/library');
    final url = lib['tracks'].single['url'] as String;
    await File('${dir.path}/Ночной город.mp3').delete();
    final (gone, body, _) = await get(url);
    expect(gone, 410);
    expect(body['error']['code'], 'file_gone');
    final (_, rescan, _) = await get('/rescan');
    expect(rescan['tracks'], 0);
  });
}
