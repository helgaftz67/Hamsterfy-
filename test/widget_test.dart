import 'package:flutter_test/flutter_test.dart';
import 'package:hamsterfy/catalog.dart';
import 'package:hamsterfy/library.dart';
import 'package:hamsterfy/models.dart';

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
          '{"name":"01_a_64kb.mp3","source":"derivative"},'
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
