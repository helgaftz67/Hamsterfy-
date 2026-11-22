import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hamsterfy/server_panel/controller.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory root;
  late ServerController panel;
  final client = HttpClient();

  Future<(int, dynamic)> get(String path) async {
    final req = await client.getUrl(Uri.parse('http://127.0.0.1:${panel.port}$path'));
    final res = await req.close();
    final body = utf8.decode(await res.fold<List<int>>([], (a, b) => a..addAll(b)));
    return (res.statusCode, body.startsWith('{') ? jsonDecode(body) : body);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('hamsterfy_panel');
    await Directory('${root.path}/music').create();
    await File('${root.path}/music/Ночной город.mp3').writeAsBytes(List.filled(500, 1));
    panel = ServerController(
      dataDir: Directory('${root.path}/data'),
      defaultMusicFolder: '${root.path}/music',
      client: MockClient((_) async => http.Response('down', 500)),
    );
    await panel.load();
    panel.settings.port = 0; // let the system pick a free port
  });

  tearDown(() async {
    panel.dispose();
    await root.delete(recursive: true);
  });

  test('start, stop and restart; state and counters follow', () async {
    expect(panel.running, isFalse);
    expect(panel.uptime, Duration.zero);
    await panel.start();
    expect(panel.problem, isNull);
    expect(panel.running, isTrue);
    expect(panel.port, isNotNull);
    expect(panel.libraryTracks, 1);
    expect(panel.mainAddress, startsWith('http://'));
    expect(panel.mainAddress, endsWith(':${panel.port}'));

    expect((await get('/api/status')).$1, 200);
    expect((await get('/api/stream/nope')).$1, 404);
    await Future<void>.delayed(Duration.zero);
    expect(panel.requests, 2);

    await panel.stop();
    expect(panel.running, isFalse);
    expect(panel.port, isNull);
    await panel.restart();
    expect(panel.running, isTrue);
    expect((await get('/api/status')).$2['running'], isTrue);
  });

  test('journal filters: all, HTTP requests, errors', () async {
    await panel.start();
    await get('/api/status');
    await get('/api/search?q=x'); // every catalog is down: journaled errors
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final all = panel.visible(EventFilter.all);
    final requests = panel.visible(EventFilter.http);
    final errors = panel.visible(EventFilter.errors);
    expect(all.length, greaterThan(requests.length));
    expect(requests.every((e) => e.kind == 'http'), isTrue);
    expect(requests.map((e) => e.text), containsAll(['GET /api/status', 'GET /api/search?q=x']));
    expect(errors, isNotEmpty);
    expect(errors.every((e) => e.kind == 'error' || (e.status ?? 0) >= 500), isTrue);
    expect(all.any((e) => e.kind == 'info' && e.text.startsWith('Сервер запущен')), isTrue);
    expect(panel.errorCount, greaterThan(0));

    panel.clearJournal();
    expect(panel.visible(EventFilter.all), isEmpty);
  });

  test('journal is written to a daily file in the logs folder', () async {
    await panel.start();
    await get('/api/status');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await panel.flushLog();
    final files = panel.logsDir.listSync().whereType<File>().toList();
    expect(files.single.path, matches(RegExp(r'server-\d{4}-\d{2}-\d{2}\.log$')));
    final text = await files.single.readAsString();
    expect(text, contains('INFO  Сервер запущен на порту'));
    expect(text, contains('HTTP  GET /api/status 200'));
  });

  test('a busy port is explained instead of crashing', () async {
    final blocker = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    panel.settings.port = blocker.port;
    await panel.start();
    expect(panel.running, isFalse);
    expect(panel.problem, contains('Порт ${blocker.port} занят'));
    await blocker.close();
    await panel.start();
    expect(panel.running, isTrue);
    expect(panel.problem, isNull);
  });

  test('settings are saved, reloaded, and applied with a restart', () async {
    await panel.start();
    final other = await Directory('${root.path}/other').create();
    await panel.applySettings(ServerSettings(musicFolder: other.path, port: 0, token: 'key', cacheGb: 5));
    expect(panel.running, isTrue);
    expect(panel.libraryTracks, 0); // the new folder is empty
    expect((await get('/api/status')).$1, 401); // the key is now required
    expect((await get('/api/status?token=key')).$1, 200);

    final again = ServerController(dataDir: Directory('${root.path}/data'), defaultMusicFolder: '${root.path}/music');
    await again.load();
    expect(again.settings.musicFolder, other.path);
    expect(again.settings.token, 'key');
    expect(again.settings.cacheGb, 5);
    again.dispose();
  });
}
