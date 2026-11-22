import 'dart:io';

import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models.dart';
import 'search_service.dart';

/// SQLite index of the tracks in the user's library, for instant search by
/// title, artist, album and genre.
///
/// Every word of those fields is stored in `terms`, so a query word is
/// matched by prefix with an index range scan: typing "ноч" finds
/// "Ночной город" without reading the whole table. The library itself
/// stays the source of truth; the index is rebuilt from it at any time.
class LocalIndex {
  LocalIndex._(this._db);
  final Database _db;

  static const _fields = ['title', 'artist', 'album', 'genre'];

  /// Opens the index at [path], or in memory when [path] is null.
  static Future<LocalIndex> open([String? path]) async {
    final DatabaseFactory factory;
    if (Platform.isAndroid || Platform.isIOS) {
      factory = mobile.databaseFactory;
    } else {
      sqfliteFfiInit();
      factory = databaseFactoryFfi;
    }
    final db = await factory.openDatabase(
      path ?? inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        singleInstance: path != null,
        onCreate: (db, _) async {
          await db.execute('CREATE TABLE tracks('
              'id TEXT PRIMARY KEY, title TEXT NOT NULL, artist TEXT NOT NULL, '
              'album TEXT NOT NULL, genre TEXT NOT NULL, stamp TEXT NOT NULL)');
          await db.execute('CREATE TABLE terms(term TEXT NOT NULL, track_id TEXT NOT NULL, field INTEGER NOT NULL)');
          await db.execute('CREATE INDEX terms_term ON terms(term)');
          await db.execute('CREATE INDEX terms_track ON terms(track_id)');
        },
      ),
    );
    return LocalIndex._(db);
  }

  Future<void> close() => _db.close();

  /// What a track looks like to the index; unchanged tracks are skipped.
  static String _stamp(Track t) => '${t.title}\u0001${t.artist}\u0001${t.album}\u0001${t.genre}';

  /// Makes the index match [tracks]: adds new ones, rewrites changed ones,
  /// removes the rest. Returns how many rows were written or removed.
  Future<int> sync(Iterable<Track> tracks) async {
    final wanted = {for (final t in tracks) t.id: t};
    final existing = {
      for (final row in await _db.query('tracks', columns: ['id', 'stamp'])) row['id'] as String: row['stamp'] as String,
    };
    final gone = existing.keys.where((id) => !wanted.containsKey(id)).toList();
    final changed = wanted.values.where((t) => existing[t.id] != _stamp(t)).toList();
    if (gone.isEmpty && changed.isEmpty) return 0;

    await _db.transaction((txn) async {
      final batch = txn.batch();
      for (final id in [...gone, ...changed.map((t) => t.id)]) {
        batch.delete('terms', where: 'track_id = ?', whereArgs: [id]);
      }
      for (final id in gone) {
        batch.delete('tracks', where: 'id = ?', whereArgs: [id]);
      }
      for (final t in changed) {
        batch.insert(
          'tracks',
          {'id': t.id, 'title': t.title, 'artist': t.artist, 'album': t.album, 'genre': t.genre, 'stamp': _stamp(t)},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        final values = [t.title, t.artist, t.album, t.genre];
        for (var field = 0; field < _fields.length; field++) {
          for (final word in SearchText.words(values[field]).toSet()) {
            batch.insert('terms', {'term': word, 'track_id': t.id, 'field': field});
          }
        }
      }
      await batch.commit(noResult: true);
    });
    return gone.length + changed.length;
  }

  Future<int> count() async => mobile.Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM tracks')) ?? 0;

  /// Upper bound for a prefix range: every string starting with [prefix]
  /// sorts below it.
  static String _after(String prefix) => '$prefix\u{10FFFF}';

  /// Ids of tracks where every query word starts some word of the title,
  /// artist, album or genre.
  Future<List<String>> search(String query, {int limit = 200}) async {
    final words = SearchText.words(query).toSet().toList();
    if (words.isEmpty) return const [];
    // One sub-select per word, intersected: all words must match.
    final sql = StringBuffer('SELECT id FROM tracks WHERE ');
    final args = <Object>[];
    for (var i = 0; i < words.length; i++) {
      if (i > 0) sql.write(' AND ');
      sql.write('id IN (SELECT track_id FROM terms WHERE term >= ? AND term < ?)');
      args..add(words[i])..add(_after(words[i]));
    }
    sql.write(' LIMIT ?');
    args.add(limit);
    return [for (final row in await _db.rawQuery(sql.toString(), args)) row['id'] as String];
  }

  /// Artists and titles to offer while the user types, most common first.
  Future<List<String>> suggest(String typed, {int limit = 6}) async {
    final words = SearchText.words(typed);
    if (words.isEmpty) return const [];
    final ids = await search(typed, limit: 400);
    if (ids.isEmpty) return const [];
    final marks = List.filled(ids.length, '?').join(',');
    final rows = await _db.rawQuery('SELECT title, artist FROM tracks WHERE id IN ($marks)', ids);
    final last = words.last;
    final counts = <String, int>{};
    void offer(String text, int weight) {
      final clean = text.trim();
      if (clean.isEmpty || clean.startsWith('Неизвестный')) return;
      // Offer only what continues the word being typed.
      if (!SearchText.words(clean).any((w) => w.startsWith(last))) return;
      counts[clean] = (counts[clean] ?? 0) + weight;
    }

    for (final row in rows) {
      offer(row['artist'] as String, 3);
      offer(row['title'] as String, 1);
    }
    final typedNorm = SearchText.normalize(typed);
    final out = counts.keys.where((s) => SearchText.normalize(s) != typedNorm).toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        return byCount != 0 ? byCount : a.toLowerCase().compareTo(b.toLowerCase());
      });
    return out.take(limit).toList();
  }
}
