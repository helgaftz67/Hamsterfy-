import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../audius.dart';
import '../models.dart';
import '../songs.dart';

/// A problem the server reports to the client as JSON:
/// `{"error": {"code": "...", "message": "..."}}` with a matching status.
class ApiError implements Exception {
  ApiError(this.status, this.code, this.message);
  final int status;
  final String code;
  final String message;
}

/// One line of the error journal shown on the status page and at /errors.
class LoggedError {
  LoggedError(this.where, this.message) : time = DateTime.now();
  final DateTime time;
  final String where;
  final String message;

  Map<String, dynamic> toJson() => {'time': time.toIso8601String(), 'where': where, 'message': message};
}

class _Song {
  _Song(this.id, this.file, this.title, this.artist, this.album, this.durationMs, this.hasCover);
  final String id;
  final File file;
  final String title, artist, album;
  final int durationMs;
  final bool hasCover;
}

/// Personal music server. Every route is a GET:
///
///   /            status page with the error journal
///   /health      is the server up, how many tracks it has
///   /library     every track in the music folder
///   /search?q=   one search over the folder, Audius and song previews
///   /stream/ID   the audio file, with Range support for seeking
///   /cover/ID    embedded artwork
///   /rescan      re-read the music folder
///   /save?id=    keep a track the artist allows to download (Audius)
///   /saved       what was saved, how much room is left
///   /errors      the error journal as JSON
///
/// It serves files the owner put in the folder and relays public catalog
/// searches. The only audio it fetches itself is what an artist published
/// with downloads allowed; everything else stays a stream or a preview.
class MusicServer {
  MusicServer({required this.music, this.token, this.cacheLimitBytes = 20 * 1024 * 1024 * 1024, http.Client? client})
      : _client = client ?? http.Client();

  final Directory music;

  /// When set, every request must carry it as `?token=` or a Bearer header.
  final String? token;
  final http.Client _client;

  /// Upper bound for tracks the server saved itself (see /save).
  final int cacheLimitBytes;

  /// Saved tracks unplayed for this long are removed.
  static const staleAfter = Duration(days: 30);

  /// Folder inside the music folder for tracks saved through /save, with
  /// an index of where each came from and when it was last played.
  Directory get cacheDir => Directory('${music.path}${Platform.pathSeparator}_hamsterfy_saved');
  File get _indexFile => File('${cacheDir.path}${Platform.pathSeparator}index.json');
  Map<String, dynamic> _index = {};

  final Map<String, _Song> _songs = {};
  final List<LoggedError> errors = [];
  final DateTime started = DateTime.now();
  DateTime? lastScan;
  int requests = 0;

  static const _types = {
    'mp3': 'audio/mpeg',
    'flac': 'audio/flac',
    'm4a': 'audio/mp4',
    'aac': 'audio/aac',
    'ogg': 'audio/ogg',
    'opus': 'audio/ogg',
    'wav': 'audio/wav',
  };

  int get trackCount => _songs.length;

  void log(String where, Object message) {
    errors.add(LoggedError(where, message.toString()));
    if (errors.length > 200) errors.removeAt(0);
    stderr.writeln('[${DateTime.now().toIso8601String()}] $where: $message');
  }

  // ---- Music folder --------------------------------------------------------

  /// Reads the music folder. Files without readable tags keep their name.
  Future<int> scan() async {
    if (!await music.exists()) {
      throw ApiError(500, 'music_folder_missing', 'Папка с музыкой не найдена: ${music.path}');
    }
    await _loadIndex();
    final found = <String, _Song>{};
    await for (final entity in music.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final ext = entity.path.split('.').last.toLowerCase();
      if (!_types.containsKey(ext)) continue;
      final relative = entity.path.substring(music.path.length);
      final id = sha1.convert(utf8.encode(relative)).toString().substring(0, 16);
      var title = entity.uri.pathSegments.last.replaceAll(RegExp(r'\.[^.]+$'), '');
      var artist = 'Неизвестный исполнитель', album = '';
      var durationMs = 0, hasCover = false;
      try {
        final meta = readMetadata(entity, getImage: true);
        if ((meta.title ?? '').trim().isNotEmpty) title = meta.title!.trim();
        if ((meta.artist ?? '').trim().isNotEmpty) artist = meta.artist!.trim();
        album = (meta.album ?? '').trim();
        durationMs = meta.duration?.inMilliseconds ?? 0;
        hasCover = meta.pictures.isNotEmpty;
      } catch (e) {
        log('scan', 'Не удалось прочитать теги файла $relative: $e');
      }
      // Saved tracks take their names from the index: their files may
      // carry no tags.
      final saved = _index[entity.uri.pathSegments.last];
      if (saved is Map) {
        title = (saved['title'] ?? title).toString();
        artist = (saved['artist'] ?? artist).toString();
        album = (saved['album'] ?? album).toString();
        if (durationMs == 0) durationMs = saved['durationMs'] as int? ?? 0;
      }
      found[id] = _Song(id, entity, title, artist, album, durationMs, hasCover);
    }
    _songs
      ..clear()
      ..addAll(found);
    lastScan = DateTime.now();
    return found.length;
  }

  /// Start-up housekeeping: read the folder and clear out stale saves.
  Future<int> open() async {
    await scan();
    final removed = await trimSaved();
    return removed.isEmpty ? trackCount : await scan();
  }

  Map<String, dynamic> _own(_Song s) => {
        'id': 'sv:${s.id}',
        'source': 'library',
        'title': s.title,
        'artist': s.artist,
        'album': s.album,
        'durationMs': s.durationMs,
        'url': '/stream/${s.id}',
        'art': s.hasCover ? '/cover/${s.id}' : null,
        'link': null,
        'full': true,
        'canSave': true,
      };

  static Map<String, dynamic> _external(Track t, String source) => {
        'id': t.id,
        'source': source,
        'title': t.title,
        'artist': t.artist,
        'album': t.album,
        'durationMs': t.durationMs,
        'url': t.url,
        'art': t.art,
        'link': t.link,
        'full': source != 'previews' && t.url != null,
        'canSave': t.canSave && source != 'previews',
      };

  List<_Song> _match(String query) {
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    return _songs.values.where((s) {
      final hay = '${s.title} ${s.artist} ${s.album}'.toLowerCase();
      return words.every(hay.contains);
    }).toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }

  // ---- Saved tracks -------------------------------------------------------

  Future<void> _loadIndex() async {
    try {
      if (await _indexFile.exists()) _index = jsonDecode(await _indexFile.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      log('saved', 'Не удалось прочитать список сохранённых треков: $e');
      _index = {};
    }
  }

  Future<void> _saveIndex() async {
    await cacheDir.create(recursive: true);
    await _indexFile.writeAsString(jsonEncode(_index));
  }

  /// Remembers that a saved track was just played.
  void _touch(_Song song) {
    final entry = _index[song.file.uri.pathSegments.last];
    if (entry is Map) {
      entry['lastPlayed'] = DateTime.now().millisecondsSinceEpoch;
      unawaited(_saveIndex().catchError((Object e) => log('saved', e)));
    }
  }

  /// Saves an Audius track into the server's folder, if its artist allows
  /// downloads. Anything else is refused with a clear reason.
  Future<Map<String, dynamic>> save(String? id) async {
    final raw = (id ?? '').trim();
    if (raw.isEmpty) throw ApiError(400, 'missing_id', 'Укажите трек: /save?id=au:ИДЕНТИФИКАТОР.');
    if (!raw.startsWith('au:')) {
      throw ApiError(400, 'unsupported_source',
          'Сохранять можно только треки Audius (id начинается с «au:»). Фрагменты песен и радио не сохраняются.');
    }
    final trackId = raw.substring(3);
    final name = 'audius_$trackId.mp3';
    final existing = _songs.values.where((s) => s.file.uri.pathSegments.last == name).firstOrNull;
    if (existing != null) return {'ok': true, 'already': true, 'track': _own(existing)};

    final infoRes = await _client
        .get(Uri.https('api.audius.co', '/v1/tracks/$trackId', {'app_name': Audius.appName}))
        .timeout(const Duration(seconds: 20));
    if (infoRes.statusCode == 404) throw ApiError(404, 'track_not_found', 'На Audius нет трека $trackId.');
    if (infoRes.statusCode != 200) throw ApiError(502, 'source_failed', 'Audius ответил ${infoRes.statusCode}.');
    final info = jsonDecode(utf8.decode(infoRes.bodyBytes))['data'];
    if (info is! Map<String, dynamic>) throw ApiError(404, 'track_not_found', 'На Audius нет трека $trackId.');
    if (!Audius.isFreelyStreamable(info)) {
      throw ApiError(403, 'not_streamable', 'Этот трек недоступен для свободного прослушивания.');
    }
    if (info['is_downloadable'] != true || info['is_download_gated'] == true) {
      throw ApiError(403, 'download_not_allowed',
          'Артист не разрешил скачивать этот трек. Его можно слушать онлайн, но сохранять нельзя.');
    }
    final track = Audius.parse(jsonEncode({'data': [info]})).single;

    await cacheDir.create(recursive: true);
    final dest = File('${cacheDir.path}${Platform.pathSeparator}$name');
    final part = File('${dest.path}.part');
    try {
      final res = await _client.send(http.Request('GET', Uri.parse(track.url!)));
      if (res.statusCode != 200) throw ApiError(502, 'source_failed', 'Audius не отдал файл: ответ ${res.statusCode}.');
      final sink = part.openWrite();
      await res.stream.pipe(sink);
      await part.rename(dest.path);
    } catch (e) {
      if (await part.exists()) await part.delete();
      if (e is ApiError) rethrow;
      throw ApiError(502, 'source_failed', 'Не удалось скачать файл с Audius: $e');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    _index[name] = {
      'id': raw,
      'title': track.title,
      'artist': track.artist,
      'album': 'Audius',
      'durationMs': track.durationMs,
      'link': track.link,
      'savedAt': now,
      'lastPlayed': now,
    };
    await _saveIndex();
    await trimSaved(keep: name);
    await scan();
    final song = _songs.values.firstWhere((s) => s.file.uri.pathSegments.last == name);
    return {'ok': true, 'already': false, 'track': _own(song)};
  }

  /// Removes saved tracks unplayed for 30 days, then the longest-unplayed
  /// ones until the folder fits the limit. Returns the removed file names.
  Future<List<String>> trimSaved({String? keep, DateTime? now}) async {
    final t0 = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final removed = <String>[];
    final files = <String, int>{};
    if (await cacheDir.exists()) {
      await for (final f in cacheDir.list()) {
        if (f is File && _index.containsKey(f.uri.pathSegments.last)) {
          files[f.uri.pathSegments.last] = await f.length();
        }
      }
    }
    int last(String name) => ((_index[name] as Map)['lastPlayed'] as int?) ?? 0;
    Future<void> drop(String name) async {
      final f = File('${cacheDir.path}${Platform.pathSeparator}$name');
      if (await f.exists()) await f.delete();
      _index.remove(name);
      files.remove(name);
      removed.add(name);
    }

    for (final name in files.keys.toList()) {
      if (name != keep && t0 - last(name) > staleAfter.inMilliseconds) await drop(name);
    }
    final byAge = files.keys.where((n) => n != keep).toList()..sort((a, b) => last(a).compareTo(last(b)));
    var total = files.values.fold(0, (a, b) => a + b);
    for (final name in byAge) {
      if (total <= cacheLimitBytes) break;
      total -= files[name]!;
      await drop(name);
    }
    if (removed.isNotEmpty) await _saveIndex();
    return removed;
  }

  Future<Map<String, dynamic>> savedInfo() async {
    var bytes = 0;
    final rows = <Map<String, dynamic>>[];
    for (final name in _index.keys) {
      final f = File('${cacheDir.path}${Platform.pathSeparator}$name');
      if (!await f.exists()) continue;
      final size = await f.length();
      bytes += size;
      rows.add({...(_index[name] as Map).cast<String, dynamic>(), 'file': name, 'bytes': size});
    }
    return {'count': rows.length, 'bytes': bytes, 'limitBytes': cacheLimitBytes, 'staleAfterDays': staleAfter.inDays, 'tracks': rows};
  }

  // ---- HTTP ----------------------------------------------------------------

  Future<HttpServer> start({int port = 8787, Object? address}) async {
    final server = await HttpServer.bind(address ?? InternetAddress.anyIPv4, port);
    server.listen(handle);
    return server;
  }

  Future<void> handle(HttpRequest req) async {
    requests++;
    final res = req.response;
    try {
      if (req.method != 'GET' && req.method != 'HEAD') {
        throw ApiError(405, 'method_not_allowed', 'Сервер принимает только GET-запросы.');
      }
      _authorize(req);
      final seg = req.uri.pathSegments.where((s) => s.isNotEmpty).toList();
      switch (seg.isEmpty ? '' : seg.first) {
        case '':
          await _html(res, _statusPage());
        case 'health':
          await _json(res, {
            'ok': true,
            'tracks': trackCount,
            'musicFolder': music.path,
            'lastScan': lastScan?.toIso8601String(),
            'uptimeSeconds': DateTime.now().difference(started).inSeconds,
            'errors': errors.length,
          });
        case 'library':
          final all = _songs.values.toList()..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
          await _json(res, {'count': all.length, 'tracks': all.map(_own).toList()});
        case 'search':
          await _json(res, await search(req.uri.queryParameters['q'], req.uri.queryParameters['sources']));
        case 'rescan':
          await _json(res, {'ok': true, 'tracks': await scan()});
        case 'save':
          await _json(res, await save(req.uri.queryParameters['id']));
        case 'saved':
          await _json(res, await savedInfo());
        case 'errors':
          await _json(res, {'count': errors.length, 'errors': errors.reversed.map((e) => e.toJson()).toList()});
        case 'stream':
          await _stream(req, _song(seg));
        case 'cover':
          await _cover(res, _song(seg));
        default:
          throw ApiError(404, 'not_found', 'Такого адреса нет: ${req.uri.path}. Список адресов — на главной странице.');
      }
    } on ApiError catch (e) {
      // Wrong requests are answered but not journaled; server faults are.
      if (e.status >= 500) log(req.uri.path, e.message);
      await _fail(res, e);
    } catch (e, stack) {
      log(req.uri.path, '$e\n$stack');
      await _fail(res, ApiError(500, 'internal_error', 'Внутренняя ошибка сервера: $e'));
    }
  }

  void _authorize(HttpRequest req) {
    if (token == null || token!.isEmpty) return;
    final header = req.headers.value(HttpHeaders.authorizationHeader);
    final given = req.uri.queryParameters['token'] ?? (header != null && header.startsWith('Bearer ') ? header.substring(7) : null);
    if (given != token) {
      throw ApiError(401, 'unauthorized', 'Нужен ключ доступа: добавьте к адресу ?token=… или заголовок Authorization.');
    }
  }

  _Song _song(List<String> seg) {
    if (seg.length < 2) throw ApiError(400, 'missing_id', 'Укажите идентификатор трека: /${seg.first}/ID.');
    final song = _songs[seg[1].replaceFirst('sv:', '')];
    if (song == null) {
      throw ApiError(404, 'track_not_found', 'Трека с идентификатором ${seg[1]} нет. Возможно, файл удалён — откройте /rescan.');
    }
    return song;
  }

  /// One search over every source. A source that fails does not break the
  /// answer: its problem is listed under `errors` and journaled.
  Future<Map<String, dynamic>> search(String? query, [String? sources]) async {
    final q = (query ?? '').trim();
    if (q.isEmpty) throw ApiError(400, 'missing_query', 'Укажите запрос: /search?q=название или исполнитель.');
    const known = ['library', 'audius', 'previews'];
    final wanted = sources == null || sources.trim().isEmpty ? known : sources.split(',').map((s) => s.trim()).toList();
    final unknown = wanted.where((s) => !known.contains(s)).toList();
    if (unknown.isNotEmpty) {
      throw ApiError(400, 'unknown_source', 'Неизвестный источник: ${unknown.join(', ')}. Доступны: ${known.join(', ')}.');
    }
    final failures = <Map<String, String>>[];
    Future<List<Map<String, dynamic>>> guarded(String source, Future<List<Track>> Function() run) async {
      if (!wanted.contains(source)) return const [];
      try {
        return [for (final t in await run()) _external(t, source)];
      } catch (e) {
        log('search/$source', e);
        failures.add({'source': source, 'message': 'Источник не ответил: $e'});
        return const [];
      }
    }

    final own = wanted.contains('library') ? _match(q).map(_own).toList() : const <Map<String, dynamic>>[];
    final remote = await Future.wait([
      guarded('audius', () => Audius(client: _client).search(q)),
      guarded('previews', () => SongSearch(client: _client).search(q)),
    ]);
    // Whole tracks first, previews and unplayable rows last.
    final results = [...own, ...remote[0].where((t) => t['full'] == true), ...remote[1], ...remote[0].where((t) => t['full'] != true)];
    return {'query': q, 'count': results.length, 'results': results, 'errors': failures};
  }

  Future<void> _stream(HttpRequest req, _Song song) async {
    final res = req.response;
    if (!await song.file.exists()) {
      throw ApiError(410, 'file_gone', 'Файл трека «${song.title}» исчез с диска. Откройте /rescan.');
    }
    final length = await song.file.length();
    final ext = song.file.path.split('.').last.toLowerCase();
    res.headers
      ..set(HttpHeaders.contentTypeHeader, _types[ext] ?? 'application/octet-stream')
      ..set(HttpHeaders.acceptRangesHeader, 'bytes');
    var start = 0, end = length - 1;
    final range = req.headers.value(HttpHeaders.rangeHeader);
    if (range != null) {
      final m = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range.trim());
      if (m == null || (m.group(1)!.isEmpty && m.group(2)!.isEmpty)) {
        throw ApiError(416, 'bad_range', 'Непонятный диапазон «$range». Ожидается bytes=НАЧАЛО-КОНЕЦ.');
      }
      if (m.group(1)!.isEmpty) {
        start = length - int.parse(m.group(2)!);
        if (start < 0) start = 0;
      } else {
        start = int.parse(m.group(1)!);
        if (m.group(2)!.isNotEmpty) end = int.parse(m.group(2)!);
      }
      if (end >= length) end = length - 1;
      if (start > end || start >= length) {
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
        throw ApiError(416, 'range_not_satisfiable', 'Диапазон за пределами файла: в нём $length байт.');
      }
      res.statusCode = HttpStatus.partialContent;
      res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$length');
    }
    res.contentLength = end - start + 1;
    _touch(song);
    if (req.method != 'HEAD') await res.addStream(song.file.openRead(start, end + 1));
    await res.close();
  }

  Future<void> _cover(HttpResponse res, _Song song) async {
    Picture? picture;
    try {
      final pictures = readMetadata(song.file, getImage: true).pictures;
      if (pictures.isNotEmpty) picture = pictures.first;
    } catch (e) {
      log('cover', 'Не удалось прочитать обложку «${song.title}»: $e');
    }
    if (picture == null) throw ApiError(404, 'no_cover', 'У трека «${song.title}» нет встроенной обложки.');
    res.headers.set(HttpHeaders.contentTypeHeader, picture.mimetype.isEmpty ? 'image/jpeg' : picture.mimetype);
    res.add(picture.bytes);
    await res.close();
  }

  Future<void> _json(HttpResponse res, Object body, [int status = 200]) async {
    res.statusCode = status;
    res.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
    res.write(const JsonEncoder.withIndent('  ').convert(body));
    await res.close();
  }

  Future<void> _html(HttpResponse res, String body) async {
    res.headers.contentType = ContentType('text', 'html', charset: 'utf-8');
    res.write(body);
    await res.close();
  }

  Future<void> _fail(HttpResponse res, ApiError e) async {
    try {
      await _json(res, {'error': {'code': e.code, 'message': e.message, 'status': e.status}}, e.status);
    } catch (_) {
      // Headers already sent (a stream broke midway): nothing more to say.
      await res.close().catchError((_) {});
    }
  }

  static String _esc(String s) => const HtmlEscape().convert(s);

  String _statusPage() {
    final up = DateTime.now().difference(started);
    final rows = errors.reversed.take(50).map((e) =>
        '<tr><td>${_esc(e.time.toLocal().toString().substring(0, 19))}</td><td>${_esc(e.where)}</td><td>${_esc(e.message)}</td></tr>');
    final key = token == null || token!.isEmpty ? '' : '?token=…';
    return '''<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="15"><title>Hamsterfy Server</title>
<style>body{margin:0;background:#121019;color:#eceaf5;font:15px/1.5 system-ui,sans-serif}main{max-width:860px;margin:0 auto;padding:28px 16px}
h1{font-size:28px;margin:0 0 4px}h2{font-size:18px;margin:28px 0 8px}.muted{color:#a39fbc}.ok{color:#5ed4a8}.bad{color:#ff7a8a}
.cards{display:flex;flex-wrap:wrap;gap:10px;margin-top:16px}.card{background:#1c1926;border-radius:14px;padding:12px 16px;min-width:130px}
.card b{display:block;font-size:22px}code{background:#262233;padding:2px 6px;border-radius:6px}
.scroll{overflow-x:auto}table{border-collapse:collapse;width:100%;min-width:520px}td,th{text-align:left;padding:8px 10px;border-bottom:1px solid #34304a;vertical-align:top}
th{color:#a39fbc;font-weight:500;font-size:13px}td:last-child{word-break:break-word}</style></head><body><main>
<h1>Hamsterfy Server</h1><div class="muted">Личный музыкальный сервер. Страница обновляется каждые 15 секунд.</div>
<div class="cards">
<div class="card"><span class="muted">Состояние</span><b class="ok">работает</b></div>
<div class="card"><span class="muted">Треков в папке</span><b>$trackCount</b></div>
<div class="card"><span class="muted">Запросов</span><b>$requests</b></div>
<div class="card"><span class="muted">Ошибок в журнале</span><b class="${errors.isEmpty ? 'ok' : 'bad'}">${errors.length}</b></div>
<div class="card"><span class="muted">Работает</span><b>${up.inHours} ч ${up.inMinutes % 60} мин</b></div>
</div>
<p class="muted">Папка с музыкой: <code>${_esc(music.path)}</code>. Последнее чтение папки: ${lastScan == null ? 'ещё не было' : _esc(lastScan!.toLocal().toString().substring(0, 19))}.</p>
<h2>Адреса</h2><div class="scroll"><table>
<tr><th>Адрес</th><th>Что отдаёт</th></tr>
<tr><td><code>/health$key</code></td><td>Работает ли сервер и сколько в нём треков</td></tr>
<tr><td><code>/search?q=запрос</code></td><td>Поиск сразу по папке, Audius и фрагментам песен</td></tr>
<tr><td><code>/library</code></td><td>Все треки из папки</td></tr>
<tr><td><code>/stream/ID</code></td><td>Аудиофайл, с поддержкой перемотки</td></tr>
<tr><td><code>/cover/ID</code></td><td>Обложка из файла</td></tr>
<tr><td><code>/rescan</code></td><td>Перечитать папку после добавления файлов</td></tr>
<tr><td><code>/save?id=au:ID</code></td><td>Сохранить трек Audius, если артист разрешил скачивание</td></tr>
<tr><td><code>/saved</code></td><td>Что сохранено и сколько места занято</td></tr>
<tr><td><code>/errors</code></td><td>Журнал ошибок в JSON</td></tr>
</table></div>
<h2>Журнал ошибок</h2>
${errors.isEmpty ? '<p class="ok">Ошибок нет.</p>' : '<div class="scroll"><table><tr><th>Время</th><th>Где</th><th>Что случилось</th></tr>${rows.join()}</table></div>'}
</main></body></html>''';
  }
}
