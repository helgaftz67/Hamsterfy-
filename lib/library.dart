import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// The user's collection: tracks, favourites, listening history and
/// downloads. Everything is kept on the device in one JSON file.
class Library extends ChangeNotifier {
  final Map<String, Track> tracks = {};
  final Set<String> favorites = {};
  final Map<String, int> plays = {};
  final Map<String, int> lastPlayed = {};

  /// Download progress per track id, 0..1.
  final Map<String, double> downloading = {};

  late Directory _dir;
  Timer? _saveTimer;
  final _random = Random();

  File get _file => File('${_dir.path}/library.json');

  Future<void> load() async {
    _dir = await getApplicationDocumentsDirectory();
    await Directory('${_dir.path}/music').create(recursive: true);
    if (!await _file.exists()) return;
    try {
      restore(jsonDecode(await _file.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      // A damaged file must not stop the app from opening.
    }
    notifyListeners();
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
  }

  Map<String, dynamic> snapshot() => {
        'tracks': [for (final t in tracks.values) t.toJson()],
        'favorites': favorites.toList(),
        'plays': plays,
        'lastPlayed': lastPlayed,
      };

  void _changed() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () async {
      try {
        await _file.writeAsString(jsonEncode(snapshot()));
      } catch (_) {}
    });
  }

  // ---- Lists -------------------------------------------------------------

  List<Track> get all => tracks.values.toList()..sort((a, b) => b.addedAt.compareTo(a.addedAt));
  List<Track> get favoriteTracks => all.where((t) => favorites.contains(t.id)).toList();
  List<Track> get downloaded => all.where((t) => t.isLocal).toList();
  bool isFavorite(Track t) => favorites.contains(t.id);

  // ---- Favourites and history --------------------------------------------

  void toggleFavorite(Track t) {
    if (!favorites.remove(t.id)) {
      favorites.add(t.id);
      tracks.putIfAbsent(t.id, () => t);
    }
    _changed();
  }

  void recordPlay(Track t) {
    plays[t.id] = (plays[t.id] ?? 0) + 1;
    lastPlayed[t.id] = DateTime.now().millisecondsSinceEpoch;
    _changed();
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
      final dest = File('${_dir.path}/music/${_safe(f.name)}');
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
    String title = fallbackTitle, artist = 'Неизвестный исполнитель', album = '';
    String? art;
    var durationMs = 0;
    try {
      final meta = readMetadata(file, getImage: true);
      if ((meta.title ?? '').trim().isNotEmpty) title = meta.title!.trim();
      if ((meta.artist ?? '').trim().isNotEmpty) artist = meta.artist!.trim();
      album = (meta.album ?? '').trim();
      durationMs = meta.duration?.inMilliseconds ?? 0;
      if (meta.pictures.isNotEmpty) {
        final cover = File('${file.path}.cover');
        await cover.writeAsBytes(meta.pictures.first.bytes);
        art = cover.path;
      }
    } catch (_) {
      // Files without readable tags still play; they keep the file name.
    }
    return Track(id: id, title: title, artist: artist, album: album, path: file.path, art: art, durationMs: durationMs);
  }

  /// Saves a catalog track to the device for offline listening.
  Future<void> download(Track t) async {
    if (t.isLocal || t.url == null || downloading.containsKey(t.id)) return;
    downloading[t.id] = 0;
    notifyListeners();
    final dest = File('${_dir.path}/music/${_safe(t.id)}.mp3');
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
    if (path != null) {
      for (final p in [path, '$path.cover']) {
        final f = File(p);
        if (await f.exists()) await f.delete();
      }
    }
    t.path = null;
    if (t.url == null || !favorites.contains(t.id)) {
      tracks.remove(t.id);
      favorites.remove(t.id);
    }
    _changed();
  }

  static String _safe(String s) => s.replaceAll(RegExp(r'[^\w.\-]+', unicode: true), '_');

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

    final scored = {for (final t in tracks.values) t: score(t)};
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
    final list = tracks.values.where((t) => (plays[t.id] ?? 0) > 0).toList()
      ..sort((a, b) => plays[b.id]!.compareTo(plays[a.id]!));
    return list.take(20).toList();
  }

  /// Tracks not heard for two weeks or never played at all.
  List<Track> forgotten({int? now}) {
    final t0 = now ?? DateTime.now().millisecondsSinceEpoch;
    const twoWeeks = 14 * 24 * 3600 * 1000;
    final list = tracks.values.where((t) => t0 - (lastPlayed[t.id] ?? 0) > twoWeeks).toList()
      ..sort((a, b) => (lastPlayed[a.id] ?? 0).compareTo(lastPlayed[b.id] ?? 0));
    return list.take(30).toList();
  }

  /// Artists the user likes most, by favourites and plays.
  List<String> get topArtists {
    final weight = <String, double>{};
    for (final t in tracks.values) {
      final w = (favorites.contains(t.id) ? 3 : 0) + (plays[t.id] ?? 0);
      if (w > 0 && !t.artist.startsWith('Неизвестный')) {
        weight[t.artist] = (weight[t.artist] ?? 0) + w;
      }
    }
    final names = weight.keys.toList()..sort((a, b) => weight[b]!.compareTo(weight[a]!));
    return names.take(3).toList();
  }
}
