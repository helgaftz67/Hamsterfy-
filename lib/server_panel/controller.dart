import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../server/music_server.dart';

/// Which journal lines the panel shows.
enum EventFilter {
  all('Все события'),
  http('HTTP-запросы'),
  errors('Ошибки');

  const EventFilter(this.label);
  final String label;

  bool accepts(ServerEvent e) => switch (this) {
        EventFilter.all => true,
        EventFilter.http => e.kind == 'http',
        // A request that ended in a server fault counts as an error too.
        EventFilter.errors => e.kind == 'error' || (e.status ?? 0) >= 500,
      };
}

/// Settings the panel remembers between launches.
class ServerSettings {
  ServerSettings({required this.musicFolder, this.port = MusicServer.defaultPort, this.token = '', this.cacheGb = 20});

  String musicFolder;
  int port;
  String token;
  double cacheGb;

  Map<String, dynamic> toJson() => {'musicFolder': musicFolder, 'port': port, 'token': token, 'cacheGb': cacheGb};

  factory ServerSettings.fromJson(Map<String, dynamic> j, {required String fallbackFolder}) => ServerSettings(
        musicFolder: (j['musicFolder'] as String?)?.trim().isNotEmpty == true ? j['musicFolder'] as String : fallbackFolder,
        port: j['port'] as int? ?? MusicServer.defaultPort,
        token: j['token'] as String? ?? '',
        cacheGb: (j['cacheGb'] as num?)?.toDouble() ?? 20,
      );
}

/// Runs the music server inside the desktop panel and exposes what the
/// panel shows: state, counters, addresses and the live journal.
class ServerController extends ChangeNotifier {
  ServerController({required this.dataDir, required String defaultMusicFolder, http.Client? client})
      : _client = client, // ignore: prefer_initializing_formals
        settings = ServerSettings(musicFolder: defaultMusicFolder);

  /// Where settings and journal files live.
  final Directory dataDir;
  final http.Client? _client;
  ServerSettings settings;

  MusicServer? _server;
  StreamSubscription<ServerEvent>? _events;
  Timer? _tick;
  IOSink? _logSink;
  String? _logDay;

  /// Journal lines shown in the panel, newest last.
  final List<ServerEvent> journal = [];
  List<String> addresses = const [];
  int cacheBytes = 0;
  int cachedTracks = 0;
  int libraryTracks = 0;

  /// Why the last start failed, in words for the user; null when fine.
  String? problem;
  bool busy = false;

  File get _settingsFile => File('${dataDir.path}${Platform.pathSeparator}server.json');
  Directory get logsDir => Directory('${dataDir.path}${Platform.pathSeparator}logs');
  Directory get storageDir => Directory(settings.musicFolder);

  bool get running => _server?.running ?? false;
  int? get port => _server?.port;
  int get requests => _server?.requests ?? 0;

  /// Requests that failed on the server side plus journaled errors.
  int get errorCount => _server?.errors.length ?? 0;
  Duration get uptime => running ? DateTime.now().difference(_server!.started) : Duration.zero;

  /// The address to type into the phone app.
  String get mainAddress => addresses.isNotEmpty ? addresses.first : 'http://localhost:${port ?? settings.port}';

  Future<void> load() async {
    await dataDir.create(recursive: true);
    await logsDir.create(recursive: true);
    try {
      if (await _settingsFile.exists()) {
        settings = ServerSettings.fromJson(
          jsonDecode(await _settingsFile.readAsString()) as Map<String, dynamic>,
          fallbackFolder: settings.musicFolder,
        );
      }
    } catch (_) {
      // Damaged settings fall back to defaults.
    }
    notifyListeners();
  }

  Future<void> saveSettings() async {
    await dataDir.create(recursive: true);
    await _settingsFile.writeAsString(jsonEncode(settings.toJson()));
  }

  /// Changes settings; a running server is restarted to pick them up.
  Future<void> applySettings(ServerSettings next) async {
    final wasRunning = running;
    if (wasRunning) await stop();
    settings = next;
    await saveSettings();
    notifyListeners();
    if (wasRunning) await start();
  }

  Future<void> start() async {
    if (running || busy) return;
    busy = true;
    problem = null;
    notifyListeners();
    try {
      await storageDir.create(recursive: true);
      final server = MusicServer(
        music: storageDir,
        token: settings.token.trim().isEmpty ? null : settings.token.trim(),
        cacheLimitBytes: (settings.cacheGb * 1024 * 1024 * 1024).round(),
        client: _client ?? IOClient(HttpClient()..findProxy = HttpClient.findProxyFromEnvironment),
      );
      _events = server.onEvent.listen(_onEvent);
      _server = server;
      await server.open();
      await server.start(port: settings.port);
      _tick = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
      await refresh();
    } on SocketException catch (e) {
      await _dropServer();
      problem = 'Порт ${settings.port} занят другой программой (${e.osError?.message ?? e.message}). '
          'Закройте её или выберите другой порт в настройках.';
    } on ApiError catch (e) {
      await _dropServer();
      problem = e.message;
    } catch (e) {
      await _dropServer();
      problem = 'Сервер не запустился: $e';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    final server = _server;
    if (server == null || busy) return;
    busy = true;
    notifyListeners();
    await server.stop();
    await _dropServer();
    busy = false;
    notifyListeners();
  }

  Future<void> restart() async {
    await stop();
    await start();
  }

  Future<void> _dropServer() async {
    _tick?.cancel();
    _tick = null;
    // Let the "stopped" line reach the journal before unsubscribing.
    await Future<void>.delayed(Duration.zero);
    await _events?.cancel();
    _events = null;
    _server = null;
    addresses = const [];
  }

  /// Re-reads counters that are not updated by events alone.
  Future<void> refresh() async {
    final server = _server;
    if (server == null) return;
    try {
      final status = await server.status();
      addresses = (status['addresses'] as List).cast<String>();
      cacheBytes = (status['cache'] as Map)['bytes'] as int;
      cachedTracks = (status['cache'] as Map)['tracks'] as int;
      libraryTracks = (status['library'] as Map)['tracks'] as int;
    } catch (_) {}
    notifyListeners();
  }

  Future<void> rescan() async {
    await _server?.scan();
    await refresh();
  }

  Future<int> clearCache() async {
    final removed = await _server?.clearSaved() ?? 0;
    await refresh();
    return removed;
  }

  void clearJournal() {
    journal.clear();
    notifyListeners();
  }

  List<ServerEvent> visible(EventFilter filter) => journal.where(filter.accepts).toList();

  void _onEvent(ServerEvent e) {
    journal.add(e);
    if (journal.length > 2000) journal.removeRange(0, journal.length - 2000);
    _writeLog(e);
    // Saving or clearing the cache changes its size.
    if (e.kind == 'info') unawaited(refresh());
    notifyListeners();
  }

  static String formatLine(ServerEvent e) {
    final time = e.time.toIso8601String().substring(0, 19).replaceFirst('T', ' ');
    final extra = e.kind == 'http' ? ' ${e.status} ${e.ms}ms' : '';
    return '$time ${e.kind.toUpperCase().padRight(5)} ${e.text}$extra';
  }

  /// One journal file per day in [logsDir].
  void _writeLog(ServerEvent e) {
    try {
      final day = e.time.toIso8601String().substring(0, 10);
      if (day != _logDay) {
        _logSink?.close();
        _logSink = File('${logsDir.path}${Platform.pathSeparator}server-$day.log').openWrite(mode: FileMode.append);
        _logDay = day;
      }
      _logSink!.writeln(formatLine(e));
    } catch (_) {
      // A full disk must not stop the server.
    }
  }

  /// Flushes the journal file; call before reading it or quitting.
  Future<void> flushLog() async => _logSink?.flush();

  /// Stops the server and closes the journal file. Call before quitting
  /// or before touching the data folder: an open file cannot be moved or
  /// deleted on Windows.
  Future<void> shutdown() async {
    busy = false;
    await stop();
    final sink = _logSink;
    _logSink = null;
    _logDay = null;
    if (sink != null) {
      await sink.flush();
      await sink.close();
    }
  }

  bool _disposed = false;

  /// Work that finishes after the panel is closed (a counter refresh, a
  /// late journal line) must not touch the disposed controller.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _tick?.cancel();
    _events?.cancel();
    _server?.stop();
    _logSink?.close();
    super.dispose();
  }
}
