import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hamsterfy/audius.dart';
import 'package:hamsterfy/catalog.dart';
import 'package:hamsterfy/library.dart';
import 'package:hamsterfy/models.dart';
import 'package:hamsterfy/player.dart';
import 'package:hamsterfy/profiles.dart';
import 'package:hamsterfy/radio.dart';
import 'package:hamsterfy/songs.dart';

class FakePlayer implements Player {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('Catalog parsing', () {
    test('search results tolerate list and missing fields', () {
      const body = '{"response":{"docs":['
          '{"identifier":"rel1","title":"First","creator":["A","B"]},'
          '{"identifier":"rel2"}]}}';
      final albums = Catalog.parseSearch(body);
      expect(albums.length, 2);
      expect(albums[0].artist, 'A');
      expect(albums[1].title, 'rel2');
      expect(albums[0].art, 'https://archive.org/services/img/rel1');
    });

    test('tracks: mp3 only, originals preferred, ordered, url encoded', () {
      const body = '{"files":['
          '{"name":"02 b song.mp3","source":"original","track":"2","title":"B","length":"3:05"},'
          '{"name":"01_a.mp3","source":"original","track":"1/2","length":"61.5"},'
          '{"name":"01_a_64kb.mp3","source":"derivative","format":"64Kbps MP3"},'
          '{"name":"cover.jpg","source":"original"}]}';
      final tracks = Catalog.parseTracks(body, Album(id: 'rel', title: 'Rel', artist: 'Art'));
      expect(tracks.map((t) => t.title), ['01 a', 'B']);
      expect(tracks[0].durationMs, 61500);
      expect(tracks[1].durationMs, 185000);
      expect(tracks[1].url, 'https://archive.org/download/rel/02%20b%20song.mp3');
      expect(tracks[0].artist, 'Art');
    });
  });

  group('Library recommendations', () {
    Library seeded() {
      final lib = Library();
      for (var i = 0; i < 6; i++) {
        final t = Track(id: 't$i', title: 'T$i', artist: i < 3 ? 'X' : 'Y', path: '/x/$i.mp3', addedAt: i);
        lib.tracks[t.id] = t;
      }
      return lib;
    }

    test('wave contains every track once and avoids artist repeats', () {
      final lib = seeded();
      final wave = lib.wave();
      expect(wave.map((t) => t.id).toSet().length, 6);
      for (var i = 1; i < wave.length; i++) {
        expect(wave[i].artist == wave[i - 1].artist, isFalse);
      }
    });

    test('recently played tracks go to the back of the wave', () {
      final lib = seeded();
      const now = 1000 * 3600 * 1000;
      lib.lastPlayed['t0'] = now - 60 * 1000;
      for (var n = 0; n < 20; n++) {
        expect(lib.wave(now: now).first.id == 't0', isFalse);
      }
    });

    test('library search matches every word across title, artist and album', () {
      final list = [
        Track(id: 'a', title: 'Night Drive', artist: 'Kavi', album: 'Roads'),
        Track(id: 'b', title: 'Morning', artist: 'Night Owls', album: 'Dawn'),
      ];
      expect(Library.filter(list, 'night').length, 2);
      expect(Library.filter(list, 'NIGHT roads').single.id, 'a');
      expect(Library.filter(list, '  ').length, 2);
      expect(Library.filter(list, 'zzz'), isEmpty);
    });

    test('profiles keep separate files and PIN check works', () {
      expect(Library.libraryFileName('main'), 'library.json');
      expect(Library.libraryFileName('p1'), 'library_p1.json');
      expect(Library.musicDirName('p1'), 'music_p1');
      final p = Profile(id: 'p1', name: 'Оля', pinHash: Profiles.hashPin('p1', '1234'));
      final profiles = Profiles(Library(), FakePlayer());
      expect(profiles.checkPin(p, '1234'), isTrue);
      expect(profiles.checkPin(p, '0000'), isFalse);
      expect(profiles.checkPin(Profile(id: 'x', name: 'Без пина'), ''), isTrue);
    });

    test('device scan adds new files, skips short clips, drops vanished ones', () {
      final lib = Library();
      Map<String, dynamic> row(int id, int ms) =>
          {'id': id, 'title': 'S$id', 'artist': '<unknown>', 'album': '', 'durationMs': ms, 'path': '/m/$id.mp3'};
      expect(lib.applyScan([row(1, 200000), row(2, 5000), row(3, 180000)]), 2);
      expect(lib.tracks.keys.toSet(), {'dev:1', 'dev:3'});
      expect(lib.tracks['dev:1']!.artist, 'Неизвестный исполнитель');
      lib.favorites.add('dev:3');
      expect(lib.applyScan([row(1, 200000)]), 0);
      expect(lib.tracks.keys.toSet(), {'dev:1'});
      expect(lib.favorites, isEmpty);
    });

    test('playlists: create, add once, list in order, survive snapshot', () {
      final lib = seeded();
      expect(lib.createPlaylist('Дорога'), isTrue);
      expect(lib.createPlaylist('Дорога'), isFalse);
      expect(lib.addToPlaylist('Дорога', lib.tracks['t2']!), isTrue);
      expect(lib.addToPlaylist('Дорога', lib.tracks['t0']!), isTrue);
      expect(lib.addToPlaylist('Дорога', lib.tracks['t0']!), isFalse);
      final copy = Library()..restore(lib.snapshot());
      expect(copy.playlistTracks('Дорога').map((t) => t.id), ['t2', 't0']);
      copy.removeFromPlaylist('Дорога', copy.tracks['t2']!);
      expect(copy.playlistTracks('Дорога').single.id, 't0');
    });

    test('radio: stations deduplicated, sorted by listeners, never in the wave', () {
      final stations = RadioDirectory.parse([
        {'stationuuid': 'a', 'name': 'Low', 'url_resolved': 'http://x/low', 'clickcount': 1, 'tags': 'rock,pop', 'country': 'RU', 'favicon': 'http://x/i.png'},
        {'stationuuid': 'b', 'name': 'High', 'url_resolved': 'https://x/high', 'clickcount': 9, 'tags': '', 'country': '', 'favicon': 'https://x/i.png'},
        {'stationuuid': 'a', 'name': 'Low again', 'url_resolved': 'http://x/low', 'clickcount': 1},
        {'stationuuid': 'c', 'name': 'Broken', 'url_resolved': ''},
      ]);
      expect(stations.map((t) => t.title), ['High', 'Low']);
      expect(stations[1].artist, 'Радио · RU · rock, pop');
      expect(stations[1].art, isNull);
      expect(stations[0].isRadio, isTrue);
      final lib = seeded()..toggleFavoriteForTest(stations[0]);
      expect(lib.wave().any((t) => t.isRadio), isFalse);
      expect(lib.stations.single.title, 'High');
    });

    test('cache eviction: least played first, favourites last, playing track kept', () {
      final lib = Library();
      for (final (id, plays) in [('a', 5), ('b', 0), ('c', 2), ('d', 1)]) {
        lib.tracks[id] = Track(id: id, title: id, artist: 'X', url: 'https://x/$id', path: '/c/$id', auto: true, size: 100);
        lib.plays[id] = plays;
      }
      lib.tracks['pinned'] = Track(id: 'pinned', title: 'p', artist: 'X', url: 'https://x/p', path: '/c/p', size: 1000);
      lib.favorites.add('b');
      expect(lib.cacheBytes, 400);
      expect(lib.overLimit(400), isEmpty);
      expect(lib.overLimit(200).map((t) => t.id), ['d', 'c']);
      expect(lib.overLimit(200, keepId: 'd').map((t) => t.id), ['c', 'a']);
      expect(lib.overLimit(0).map((t) => t.id), ['d', 'c', 'a', 'b']);
      final copy = Library()..restore(lib.snapshot());
      expect(copy.cacheBytes, 400);
      expect(copy.cacheLimitMb, 2048);
    });

    test('removing a phone track hides it for good until unhidden', () async {
      final lib = Library();
      Map<String, dynamic> row(int id) =>
          {'id': id, 'title': 'S$id', 'artist': 'A', 'album': '', 'durationMs': 200000, 'path': '/m/$id.mp3'};
      lib.applyScan([row(1), row(2)]);
      lib.favorites.add('dev:1');
      await lib.forget(lib.tracks['dev:1']!);
      expect(lib.tracks.keys, ['dev:2']);
      expect(lib.favorites, isEmpty);
      expect(lib.applyScan([row(1), row(2)]), 0);
      expect(lib.tracks.keys, ['dev:2']);
      final copy = Library()..restore(lib.snapshot());
      expect(copy.hidden, {'dev:1'});
      copy.unhideAll();
      expect(copy.applyScan([row(1), row(2)]), 1);
    });

    test('world search: previews parsed, matched to owned tracks, kept out of mixes', () {
      const body = '{"resultCount":2,"results":['
          '{"trackId":7,"trackName":"Night Drive","artistName":"Kavi","collectionName":"Roads","previewUrl":"https://a/p.m4a","artworkUrl100":"https://i/100x100bb.jpg","trackTimeMillis":200000,"trackViewUrl":"https://music/x"},'
          '{"trackId":8,"trackName":"No preview","artistName":"Z"}]}';
      final found = SongSearch.parse(body);
      expect(found.single.id, 'it:7');
      expect(found.single.isPreview, isTrue);
      expect(found.single.art, 'https://i/600x600bb.jpg');
      expect(found.single.link, 'https://music/x');
      final lib = Library();
      expect(lib.match(found.single), isNull);
      lib.tracks['own'] = Track(id: 'own', title: 'night drive!', artist: 'KAVI feat. Someone', path: '/m/n.mp3');
      expect(lib.match(found.single)!.id, 'own');
      lib.toggleFavoriteForTest(found.single);
      expect(lib.songs.map((t) => t.id), ['own']);
      expect(lib.wave().map((t) => t.id), ['own']);
      expect(lib.favoriteTracks.single.id, 'it:7');
      final copy = Library()..restore(lib.snapshot());
      expect(copy.tracks['it:7']!.link, 'https://music/x');
    });

    test('audius: only freely streamable tracks get a stream address', () {
      Map<String, dynamic> row(String id, Map<String, dynamic> extra) => {
            'id': id,
            'title': ' Song $id ',
            'duration': 125,
            'permalink': '/artist/song-$id',
            'user': {'name': 'Artist', 'handle': 'artist'},
            'artwork': {'150x150': 'https://c/150.jpg', '480x480': 'https://c/480.jpg'},
            'is_streamable': true,
            'is_stream_gated': false,
            'is_delete': false,
            'is_unlisted': false,
            'access': {'stream': true, 'download': true},
            'allowed_api_keys': null,
            'is_downloadable': false,
            ...extra,
          };
      final body = '{"data":${jsonEncode([
            row('ok', {'is_downloadable': true}),
            row('notStreamable', {'is_streamable': false}),
            row('gated', {'is_stream_gated': true}),
            row('noAccess', {'access': {'stream': false}}),
            row('keyOnly', {'allowed_api_keys': ['abc']}),
            row('deleted', {'is_delete': true}),
          ])}}';
      final tracks = Audius.parse(body);
      expect(tracks.length, 6);
      final ok = tracks.first;
      expect(ok.id, 'au:ok');
      expect(ok.title, 'Song ok');
      expect(ok.artist, 'Artist');
      expect(ok.durationMs, 125000);
      expect(ok.art, 'https://c/480.jpg');
      expect(ok.url, 'https://api.audius.co/v1/tracks/ok/stream?app_name=Hamsterfy');
      expect(ok.link, 'https://audius.co/artist/song-ok');
      expect(ok.canSave, isTrue);
      expect(ok.isUnavailable, isFalse);
      expect(tracks.skip(1).every((t) => t.url == null && t.isUnavailable), isTrue);
      final copy = Track.fromJson(tracks[1].toJson());
      expect(copy.canSave, isFalse);
    });

    test('snapshot round-trips favourites and plays', () {
      final lib = seeded();
      lib.favorites.add('t1');
      lib.plays['t1'] = 4;
      final copy = Library()..restore(lib.snapshot());
      expect(copy.favoriteTracks.single.id, 't1');
      expect(copy.mostPlayed.single.id, 't1');
      expect(copy.topArtists, ['X']);
      expect(copy.forgotten().length, 6);
    });
  });
}
