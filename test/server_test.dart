import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hamsterfy/models.dart';
import 'package:hamsterfy/my_server.dart';
import 'package:hamsterfy/server/music_server.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Upstream catalogs are faked: Audius answers, the preview search is down.
Map<String, dynamic> audiusTrack(String id, {bool downloadable = true, bool streamable = true}) => {
      'id': id, 'title': 'Песня $id', 'duration': 180, 'permalink': '/a/$id',
      'user': {'name': 'Артист'}, 'is_streamable': streamable, 'is_stream_gated': false,
      'access': {'stream': true}, 'is_downloadable': downloadable, 'is_download_gated': false,
    };

http.Client fakeCatalogs({bool audiusDown = false}) => MockClient((req) async {
      if (req.url.host == 'api.audius.co') {
        if (audiusDown) return http.Response('boom', 503);
        final seg = req.url.pathSegments;
        // /v1/tracks/ID and /v1/tracks/ID/stream
        if (seg.length >= 3 && seg[1] == 'tracks' && seg[2] != 'search') {
          final id = seg[2];
          if (seg.length == 4 && seg[3] == 'stream') return http.Response.bytes(List.filled(4000, 7), 200);
          if (id == 'missing') return http.Response('{"data":null}', 404);
          return http.Response.bytes(
              utf8.encode(jsonEncode({'data': audiusTrack(id, downloadable: id != 'locked', streamable: id != 'gated')})), 200);
        }
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

  Future<void> boot({String? token, bool audiusDown = false, int limit = 1 << 30}) async {
    server = MusicServer(music: dir, token: token, cacheLimitBytes: limit, client: fakeCatalogs(audiusDown: audiusDown));
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

  test('save keeps only tracks whose artist allows downloads', () async {
    await boot();
    final (ok, saved, _) = await get('/save?id=au:D1');
    expect(ok, 200);
    expect(saved['already'], isFalse);
    expect(saved['track']['title'], 'Песня D1');
    expect(saved['track']['artist'], 'Артист');
    final url = saved['track']['url'] as String;
    final (status, bytes, _) = await get(url);
    expect(status, 200);
    expect((bytes as List).length, 4000);
    expect((await get('/save?id=au:D1')).$2['already'], isTrue);
    final (_, info, _) = await get('/saved');
    expect(info['count'], 1);
    expect(info['bytes'], 4000);
    expect(info['staleAfterDays'], 30);

    Future<void> refused(String id, int status, String code) async {
      final (got, body, _) = await get('/save?id=$id');
      expect(got, status, reason: id);
      expect(body['error']['code'], code, reason: id);
    }

    await refused('au:locked', 403, 'download_not_allowed');
    await refused('au:gated', 403, 'not_streamable');
    await refused('au:missing', 404, 'track_not_found');
    await refused('it:123', 400, 'unsupported_source');
    await refused('', 400, 'missing_id');
    expect((await get('/saved')).$2['count'], 1);
  });

  test('saved tracks leave after 30 unplayed days or when the limit is hit', () async {
    await boot(limit: 9000);
    await get('/save?id=au:A');
    await get('/save?id=au:B');
    expect((await get('/saved')).$2['count'], 2);
    // A third 4000-byte track does not fit 9000 bytes: the one unplayed
    // longest goes, the newcomer stays.
    await get('/stream/${(await get('/library')).$2['tracks'].firstWhere((t) => t['title'] == 'Песня B')['id'].substring(3)}');
    await get('/save?id=au:C');
    final (_, after, _) = await get('/saved');
    expect((after['tracks'] as List).map((t) => t['id']).toSet(), {'au:B', 'au:C'});
    // Forty days later nothing was played: everything saved is cleared.
    final removed = await server.trimSaved(now: DateTime.now().add(const Duration(days: 40)));
    expect(removed.length, 2);
    await server.scan();
    final (_, lib, _) = await get('/library');
    expect(lib['tracks'].single['title'], 'Ночной город');
  });

  test('the app client talks to the server: search, play address, save, problems', () async {
    await boot(token: 'key');
    final app = MyServer('127.0.0.1:${http_.port}/', token: 'key');
    expect(app.base, 'http://127.0.0.1:${http_.port}');
    expect(await app.health(), 1);

    final own = await app.search('ночной');
    final track = own.tracks.first;
    expect(track.isServer, isTrue);
    expect(track.canSave, isTrue);
    expect(track.url, startsWith('http://127.0.0.1:${http_.port}/stream/'));
    expect(track.url, contains('token=key'));
    // The address the player gets really returns the file, and seeks.
    final req = await client.getUrl(Uri.parse(track.url!));
    req.headers.set('Range', 'bytes=100-199');
    final res = await req.close();
    expect(res.statusCode, 206);
    expect((await res.fold<int>(0, (n, chunk) => n + chunk.length)), 100);

    // Sources that failed arrive as readable notes, not as a broken search.
    final mixed = await app.search('волна');
    expect(mixed.tracks.map((t) => t.id), contains('au:A1'));
    expect(mixed.problems.single, startsWith('Каталог песен: '));

    final saved = await app.save(mixed.tracks.firstWhere((t) => t.id == 'au:A1'));
    expect(saved.isServer, isTrue);
    expect(saved.title, 'Песня A1');

    // Refusals and connection trouble come back as plain sentences.
    await expectLater(
      app.save(Track(id: 'au:locked', title: 'x', artist: 'y')),
      throwsA(isA<ServerProblem>().having((e) => e.code, 'code', 'download_not_allowed')),
    );
    await expectLater(
      MyServer('127.0.0.1:${http_.port}', token: 'wrong').health(),
      throwsA(isA<ServerProblem>().having((e) => e.code, 'code', 'unauthorized')),
    );
    await expectLater(
      MyServer('127.0.0.1:1').health(),
      throwsA(isA<ServerProblem>().having((e) => e.message, 'message', contains('Не удалось связаться'))),
    );
  });
}
