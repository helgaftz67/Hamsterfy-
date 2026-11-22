import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:math' as math;

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'models.dart';
import 'search/local_index.dart';

/// The user's collection: tracks, favourites, listening history and
/// downloads. Everything is kept on the device in one JSON file.
class Library extends ChangeNotifier {
  final Map<String, Track> tracks = {};
  final Set<String> favorites = {};
  final Map<String, int> plays = {};
  final Map<String, int> lastPlayed = {};

  /// Ids of phone tracks the user removed from the library. The files stay
  /// on the phone; the scan just stops bringing them back.
  final Set<String> hidden = {};

  /// Playlists by name, each an ordered list of track ids.
  final Map<String, List<String>> playlists = {};

  /// Listening cache: catalog tracks are saved as they are played, and the
  /// least played ones are removed once the cache outgrows the limit.
  bool autoCache = true;
  int cacheLimitMb = 2048;

  /// Recent search queries, newest first.
  final List<String> searches = [];

  void rememberSearch(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    searches.removeWhere((s) => s.toLowerCase() == q.toLowerCase());
    searches.insert(0, q);
    if (searches.length > 12) searches.removeRange(12, searches.length);
    _changed();
  }

  void forgetSearch(String query) {
    searches.remove(query);
    _changed();
  }

  void clearSearches() {
    searches.clear();
    _changed();
  }

  /// Address and access key of the user's own server, if they run one.
  String serverUrl = '';
  String serverToken = '';
  bool get hasServer => serverUrl.trim().isNotEmpty;

  /// Download progress per track id, 0..1.
  final Map<String, double> downloading = {};

  late Directory _dir;
  bool _opened = false;

  /// SQLite index of this profile's tracks; null until a profile is open
  /// (and in tests that never open one).
  LocalIndex? index;
  Future<void>? _indexing;

  static String indexFileName(String profile) => profile == 'main' ? 'search.db' : 'search_$profile.db';

  /// Brings the index in line with the collection. Calls made while a
  /// sync is running are folded into one follow-up run.
  Future<void> syncIndex() {
    final db = index;
    if (db == null) return Future.value();
    return _indexing = (_indexing ?? Future.value()).then((_) async {
      try {
        await db.sync(tracks.values.toList());
      } catch (_) {
        // Search falls back to scanning the list if the index is unusable.
      }
    });
  }

  /// Local search: through the index when it is open, otherwise by
  /// scanning the collection.
  Future<List<Track>> searchLocal(String query) async {
    final db = index;
    if (db != null) {
      try {
        await _indexing;
        final ids = await db.search(query);
        return [for (final id in ids) if (tracks[id] != null) tracks[id]!];
      } catch (_) {}
    }
    return filter(tracks.values.toList(), query);
  }
  String _profile = 'main';
  Timer? _saveTimer;
  final _random = Random();

  /// Each profile keeps its own library file and its own music folder.
  /// The first profile ("main") uses the original un-suffixed names.
  static String libraryFileName(String profile) => profile == 'main' ? 'library.json' : 'library_$profile.json';
  static String musicDirName(String profile) => profile == 'main' ? 'music' : 'music_$profile';

  File get _file => File('${_dir.path}/${libraryFileName(_profile)}');
  String get _music => '${_dir.path}/${musicDirName(_profile)}';

  /// Switches to [profile]: saves pending changes of the previous one,
  /// forgets its data and loads the new collection.
  Future<void> open(String profile) async {
    _dir = await getApplicationDocumentsDirectory();
    if (_opened && (_saveTimer?.isActive ?? false)) {
      _saveTimer!.cancel();
      try {
        await _file.writeAsString(jsonEncode(snapshot()));
      } catch (_) {}
    }
    _profile = profile;
    _opened = true;
    tracks.clear();
    favorites.clear();
    plays.clear();
    lastPlayed.clear();
    playlists.clear();
    hidden.clear();
    autoCache = true;
    cacheLimitMb = 2048;
    serverUrl = '';
    serverToken = '';
    searches.clear();
    downloading.clear();
    await Directory(_music).create(recursive: true);
    await _indexing;
    await index?.close().catchError((_) {});
    index = null;
    try {
      index = await LocalIndex.open('${_dir.path}/${indexFileName(profile)}');
    } catch (_) {
      // Without the index, local search scans the list instead.
    }
    if (await _file.exists()) {
      try {
        restore(jsonDecode(await _file.readAsString()) as Map<String, dynamic>);
      } catch (_) {
        // A damaged file must not stop the app from opening.
      }
    }
    notifyListeners();
    unawaited(syncIndex());
    unawaited(trimCache());
  }

  @visibleForTesting
  void restore(Map<String, dynamic> j) {
    for (final t in (j['tracks'] as List? ?? const [])) {
      final track = Track.fromJson(t as Map<String, dynamic>);
      tracks[track.id] = track;
    }
    favorites.addAll((j['favorites'] as List? ?? const []).cast<String>());
    plays.addAll((j['plays'] as Map? ?? const {}).cast<String, int>());
    lastPlayed.addAll((j['lastPlayed'] as Map? ?? const {}).cast<String, int>());
    hidden.addAll((j['hidden'] as List? ?? const []).cast<String>());
    autoCache = j['autoCache'] as bool? ?? true;
    cacheLimitMb = j['cacheLimitMb'] as int? ?? 2048;
    serverUrl = j['serverUrl'] as String? ?? '';
    searches
      ..clear()
      ..addAll((j['searches'] as List? ?? const []).cast<String>());
    serverToken = j['serverToken'] as String? ?? '';
    (j['playlists'] as Map? ?? const {}).forEach((name, ids) {
      playlists[name as String] = (ids as List).cast<String>().toList();
    });
  }

  Map<String, dynamic> snapshot() => {
        'tracks': [for (final t in tracks.values) t.toJson()],
        'favorites': favorites.toList(),
        'plays': plays,
        'lastPlayed': lastPlayed,
        'playlists': playlists,
        'hidden': hidden.toList(),
        'autoCache': autoCache,
        'cacheLimitMb': cacheLimitMb,
        'serverUrl': serverUrl,
        'searches': searches,
        'serverToken': serverToken,
      };

  void _changed() {
    notifyListeners();
    // Nothing to write to until a profile has been opened.
    if (!_opened) return;
    _saveTimer?.cancel();
    final file = _file;
    final data = jsonEncode(snapshot());
    _saveTimer = Timer(const Duration(milliseconds: 400), () async {
      try {
        await file.writeAsString(data);
      } catch (_) {}
      await syncIndex();
    });
  }

  // ---- Lists -------------------------------------------------------------

  List<Track> get all => tracks.values.toList()..sort((a, b) => b.addedAt.compareTo(a.addedAt));
  /// Full tracks only: no radio stations and no search previews.
  List<Track> get songs => all.where((t) => !t.isRadio && !t.isPreview).toList();

  /// A full track in the library that is the same song as [found], if any.
  Track? match(Track found) {
    String norm(String v) => v.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');
    final title = norm(found.title), artist = norm(found.artist);
    if (title.isEmpty) return null;
    for (final t in tracks.values) {
      if (t.isRadio || t.isPreview || norm(t.title) != title) continue;
      final a = norm(t.artist);
      if (a == artist || (a.isNotEmpty && (a.contains(artist) || artist.contains(a)))) return t;
    }
    return null;
  }

  List<Track> get favoriteTracks => all.where((t) => favorites.contains(t.id)).toList();
  List<Track> get downloaded => all.where((t) => t.isLocal).toList();
  List<Track> get stations => all.where((t) => t.isRadio).toList();
  bool isFavorite(Track t) => favorites.contains(t.id);

  /// Filters [source] by words found in the title, artist or album.
  static List<Track> filter(List<Track> source, String query) {
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return source;
    return source.where((t) {
      final hay = '${t.title} ${t.artist} ${t.album}'.toLowerCase();
      return words.every(hay.contains);
    }).toList();
  }

  // ---- Favourites and history --------------------------------------------

  void toggleFavorite(Track t) {
    if (!favorites.remove(t.id)) {
      favorites.add(t.id);
      tracks.putIfAbsent(t.id, () => t);
    }
    _changed();
  }

  @visibleForTesting
  void toggleFavoriteForTest(Track t) {
    favorites.add(t.id);
    tracks[t.id] = t;
  }

  void recordPlay(Track t) {
    plays[t.id] = (plays[t.id] ?? 0) + 1;
    lastPlayed[t.id] = DateTime.now().millisecondsSinceEpoch;
    _changed();
  }

  // ---- Playlists ----------------------------------------------------------

  List<String> get playlistNames => playlists.keys.toList();

  List<Track> playlistTracks(String name) =>
      [for (final id in playlists[name] ?? const <String>[]) if (tracks[id] != null) tracks[id]!];

  /// Returns false when a playlist with this name already exists.
  bool createPlaylist(String name) {
    final clean = name.trim();
    if (clean.isEmpty || playlists.containsKey(clean)) return false;
    playlists[clean] = [];
    _changed();
    return true;
  }

  /// Returns false when the track is already in the playlist.
  bool addToPlaylist(String name, Track t) {
    final ids = playlists.putIfAbsent(name, () => []);
    if (ids.contains(t.id)) return false;
    ids.add(t.id);
    tracks.putIfAbsent(t.id, () => t);
    _changed();
    return true;
  }

  void removeFromPlaylist(String name, Track t) {
    playlists[name]?.remove(t.id);
    _changed();
  }

  void deletePlaylist(String name) {
    playlists.remove(name);
    _changed();
  }

  bool _inPlaylist(String id) => playlists.values.any((ids) => ids.contains(id));

  // ---- Music already on the phone ------------------------------------------

  static const _media = MethodChannel('hamsterfy/media');

  /// Syncs the library with the music files Android knows about: new files
  /// are added, files that disappeared are dropped. Returns the number of
  /// new tracks, or -1 when access to music was not granted. With
  /// [ask] false the permission dialog is never shown.
  Future<int> scanDevice({bool ask = true}) async {
    // Only Android has a system index of music files.
    if (!Platform.isAndroid) return -1;
    var granted = await Permission.audio.isGranted || await Permission.storage.isGranted;
    if (!granted && ask) {
      final audio = await Permission.audio.request();
      final storage = audio.isGranted ? audio : await Permission.storage.request();
      granted = audio.isGranted || storage.isGranted;
    }
    if (!granted) return -1;
    final rows = (await _media.invokeMethod<List<dynamic>>('scan')) ?? const [];
    return applyScan([for (final r in rows) Map<String, dynamic>.from(r as Map)]);
  }

  @visibleForTesting
  int applyScan(List<Map<String, dynamic>> rows) {
    final seen = <String>{};
    var added = 0;
    for (final r in rows) {
      final path = r['path'] as String?;
      // Skip clips shorter than 30 seconds: ringtones and voice notes.
      if (path == null || (r['durationMs'] as int? ?? 0) < 30000) continue;
      final id = 'dev:${r['id']}';
      seen.add(id);
      if (tracks.containsKey(id) || hidden.contains(id)) continue;
      final artist = (r['artist'] as String? ?? '').trim();
      final title = (r['title'] as String? ?? '').trim();
      tracks[id] = Track(
        id: id,
        title: title.isEmpty ? path.split('/').last : title,
        artist: artist.isEmpty || artist == '<unknown>' ? 'Неизвестный исполнитель' : artist,
        album: (r['album'] as String? ?? '').trim(),
        path: path,
        durationMs: r['durationMs'] as int? ?? 0,
      );
      added++;
    }
    final gone = tracks.keys.where((id) => id.startsWith('dev:') && !seen.contains(id)).toList();
    for (final id in gone) {
      tracks.remove(id);
      favorites.remove(id);
      for (final ids in playlists.values) {
        ids.remove(id);
      }
    }
    if (added > 0 || gone.isNotEmpty) _changed();
    return added;
  }

  // ---- Import and download -----------------------------------------------

  static const _audioExt = ['mp3', 'flac', 'm4a', 'aac', 'ogg', 'opus', 'wav'];

  /// Lets the user pick audio files and copies them into the app.
  /// Returns how many tracks were added.
  Future<int> importFiles() async {
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: _audioExt);
    var added = 0;
    for (final f in picked) {
      final ext = (f.extension ?? 'mp3').toLowerCase();
      final id = 'local:${f.name}';
      if (tracks[id]?.isLocal ?? false) continue;
      final dest = File('$_music/${_safe(f.name)}');
      final sink = dest.openWrite();
      await sink.addStream(f.xFile.openRead());
      await sink.close();
      tracks[id] = await _describe(id, dest, fallbackTitle: f.name.replaceAll('.$ext', ''));
      added++;
    }
    if (added > 0) _changed();
    return added;
  }

  Future<Track> _describe(String id, File file, {required String fallbackTitle}) async {
    String title = fallbackTitle, artist = 'Неизвестный исполнитель', album = '', genre = '';
    String? art;
    var durationMs = 0;
    try {
      final meta = readMetadata(file, getImage: true);
      if ((meta.title ?? '').trim().isNotEmpty) title = meta.title!.trim();
      if ((meta.artist ?? '').trim().isNotEmpty) artist = meta.artist!.trim();
      album = (meta.album ?? '').trim();
      genre = meta.genres.map((g) => g.trim()).where((g) => g.isNotEmpty).join(', ');
      durationMs = meta.duration?.inMilliseconds ?? 0;
      if (meta.pictures.isNotEmpty) {
        final cover = File('${file.path}.cover');
        await cover.writeAsBytes(meta.pictures.first.bytes);
        art = cover.path;
      }
    } catch (_) {
      // Files without readable tags still play; they keep the file name.
    }
    return Track(
        id: id, title: title, artist: artist, album: album, genre: genre, path: file.path, art: art, durationMs: durationMs);
  }

  /// Saves a catalog track to the device for offline listening. With [auto]
  /// the file belongs to the listening cache and may be evicted later.
  Future<void> download(Track t, {bool auto = false}) async {
    if (t.isLocal || t.isRadio || t.isPreview || !t.canSave || t.url == null || downloading.containsKey(t.id)) return;
    downloading[t.id] = 0;
    notifyListeners();
    final dest = File('$_music/${_safe(t.id)}.mp3');
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(t.url!)));
      if (res.statusCode != 200) throw Exception('Сервер ответил ${res.statusCode}');
      final total = res.contentLength ?? 0;
      var got = 0;
      final sink = dest.openWrite();
      await for (final chunk in res.stream) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) {
          final p = got / total;
          if (p - (downloading[t.id] ?? 0) > 0.02) {
            downloading[t.id] = p;
            notifyListeners();
          }
        }
      }
      await sink.close();
      t.path = dest.path;
      t.auto = auto;
      t.size = got;
      tracks[t.id] = t;
    } catch (e) {
      if (await dest.exists()) await dest.delete();
      rethrow;
    } finally {
      client.close();
      downloading.remove(t.id);
      _changed();
    }
  }

  /// Removes the file from the device. Catalog tracks stay in the library
  /// as streams if they are favourites; everything else is dropped.
  Future<void> remove(Track t) async {
    final path = t.path;
    if (path != null && !t.isDevice) {
      for (final p in [path, '$path.cover']) {
        final f = File(p);
        if (await f.exists()) await f.delete();
      }
    }
    t.path = null;
    t.auto = false;
    t.size = 0;
    if (t.url == null || !(favorites.contains(t.id) || _inPlaylist(t.id))) {
      tracks.remove(t.id);
      favorites.remove(t.id);
      for (final ids in playlists.values) {
        ids.remove(t.id);
      }
    }
    _changed();
  }

  /// Takes a track out of the library without touching the user's own
  /// files: phone tracks are only hidden, streams are simply forgotten.
  /// Copies the app made itself (imports, downloads) are deleted.
  Future<void> forget(Track t) async {
    if (t.isDevice) {
      hidden.add(t.id);
    } else if (t.path != null) {
      for (final p in [t.path!, '${t.path}.cover']) {
        final f = File(p);
        if (await f.exists()) await f.delete();
      }
    }
    tracks.remove(t.id);
    favorites.remove(t.id);
    for (final ids in playlists.values) {
      ids.remove(t.id);
    }
    _changed();
  }

  /// Brings hidden phone tracks back on the next scan.
  void unhideAll() {
    hidden.clear();
    _changed();
  }

  int get totalPlays => plays.values.fold(0, (a, b) => a + b);

  static String _safe(String s) => s.replaceAll(RegExp(r'[^\w.\-]+', unicode: true), '_');

  // ---- Listening cache ----------------------------------------------------

  List<Track> get cached => tracks.values.where((t) => t.auto && t.isLocal).toList();
  int get cacheBytes => cached.fold(0, (sum, t) => sum + t.size);

  /// Called when a track starts playing: saves it to the cache and makes
  /// room if the cache is over its limit. [playingId] is never evicted.
  Future<void> cacheAfterPlay(Track t) async {
    if (!autoCache || t.isLocal || t.isRadio || t.isPreview || !t.canSave || t.url == null) return;
    try {
      await download(t, auto: true);
    } catch (_) {
      return; // No connection or no space: the track simply stays a stream.
    }
    await trimCache(keepId: t.id);
  }

  /// Cached tracks that must go to fit [limitBytes], least valuable first:
  /// not favourite, played least, heard longest ago.
  List<Track> overLimit(int limitBytes, {String? keepId}) {
    final order = cached.where((t) => t.id != keepId).toList()
      ..sort((a, b) {
        final fav = (favorites.contains(a.id) ? 1 : 0) - (favorites.contains(b.id) ? 1 : 0);
        if (fav != 0) return fav;
        final byPlays = (plays[a.id] ?? 0).compareTo(plays[b.id] ?? 0);
        if (byPlays != 0) return byPlays;
        return (lastPlayed[a.id] ?? 0).compareTo(lastPlayed[b.id] ?? 0);
      });
    var total = cacheBytes;
    final out = <Track>[];
    for (final t in order) {
      if (total <= limitBytes) break;
      out.add(t);
      total -= t.size;
    }
    return out;
  }

  /// Cached tracks nobody played for [days] days (counted from when they
  /// were saved, if they were never played again).
  List<Track> stale({int days = 30, int? now, String? keepId}) {
    final t0 = now ?? DateTime.now().millisecondsSinceEpoch;
    final limit = days * 24 * 3600 * 1000;
    return cached.where((t) {
      if (t.id == keepId) return false;
      final last = math.max(lastPlayed[t.id] ?? 0, t.addedAt);
      return t0 - last > limit;
    }).toList();
  }

  /// Frees space: first drops cached tracks not played for 30 days, then,
  /// if the cache is still over its limit, the least played ones.
  Future<void> trimCache({String? keepId}) async {
    for (final t in stale(keepId: keepId)) {
      await remove(t);
    }
    for (final t in overLimit(cacheLimitMb * 1024 * 1024, keepId: keepId)) {
      await remove(t);
    }
  }

  Future<void> clearCache() async {
    for (final t in cached) {
      await remove(t);
    }
  }

  void setServer(String url, String token) {
    serverUrl = url.trim();
    serverToken = token.trim();
    _changed();
  }

  /// Keeps an automatically cached track for good.
  void pin(Track t) {
    t.auto = false;
    _changed();
  }

  Future<void> setCache({bool? enabled, int? limitMb}) async {
    if (enabled != null) autoCache = enabled;
    if (limitMb != null) cacheLimitMb = limitMb;
    _changed();
    await trimCache();
  }

  // ---- Recommendations ---------------------------------------------------

  /// "My wave": an endless-feeling mix of the collection. Favourites and
  /// often-played tracks come up more, tracks heard in the last two hours
  /// are pushed back, and the same artist never plays twice in a row when
  /// it can be avoided.
  List<Track> wave({int? now}) {
    final t0 = now ?? DateTime.now().millisecondsSinceEpoch;
    double score(Track t) {
      var s = 1.0 + _random.nextDouble() * 2;
      if (favorites.contains(t.id)) s += 1.5;
      s += log(1 + (plays[t.id] ?? 0)) * 0.6;
      final last = lastPlayed[t.id];
      if (last != null && t0 - last < 2 * 3600 * 1000) s -= 3;
      return s;
    }

    final scored = {for (final t in tracks.values) if (!t.isRadio && !t.isPreview) t: score(t)};
    final pool = scored.keys.toList()..sort((a, b) => scored[b]!.compareTo(scored[a]!));
    final out = <Track>[];
    while (pool.isNotEmpty) {
      final i = out.isEmpty ? 0 : pool.indexWhere((t) => t.artist != out.last.artist);
      out.add(pool.removeAt(i < 0 ? 0 : i));
    }
    return out;
  }

  /// Tracks played most often.
  List<Track> get mostPlayed {
    final list = tracks.values.where((t) => !t.isPreview && (plays[t.id] ?? 0) > 0).toList()
      ..sort((a, b) => plays[b.id]!.compareTo(plays[a.id]!));
    return list.take(20).toList();
  }

  /// Tracks not heard for two weeks or never played at all.
  List<Track> forgotten({int? now}) {
    final t0 = now ?? DateTime.now().millisecondsSinceEpoch;
    const twoWeeks = 14 * 24 * 3600 * 1000;
    final list = tracks.values.where((t) => !t.isRadio && !t.isPreview && t0 - (lastPlayed[t.id] ?? 0) > twoWeeks).toList()
      ..sort((a, b) => (lastPlayed[a.id] ?? 0).compareTo(lastPlayed[b.id] ?? 0));
    return list.take(30).toList();
  }

  /// Artists the user likes most, by favourites and plays.
  List<String> get topArtists {
    final weight = <String, double>{};
    for (final t in tracks.values) {
      final w = (favorites.contains(t.id) ? 3 : 0) + (plays[t.id] ?? 0);
      if (w > 0 && !t.isRadio && !t.artist.startsWith('Неизвестный')) {
        weight[t.artist] = (weight[t.artist] ?? 0) + w;
      }
    }
    final names = weight.keys.toList()..sort((a, b) => weight[b]!.compareTo(weight[a]!));
    return names.take(3).toList();
  }
}
