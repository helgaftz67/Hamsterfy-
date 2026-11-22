import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hamsterfy/models.dart';
import 'package:hamsterfy/search/search_service.dart';

Track local(String id, String title, String artist, {String album = ''}) =>
    Track(id: 'dev:$id', title: title, artist: artist, album: album, path: '/m/$id.mp3');
Track stream(String id, String title, String artist) =>
    Track(id: 'au:$id', title: title, artist: artist, url: 'https://x/$id');
Track preview(String id, String title, String artist) =>
    Track(id: 'it:$id', title: title, artist: artist, url: 'https://p/$id');
Track locked(String id, String title, String artist) => Track(id: 'au:$id', title: title, artist: artist);

void main() {
  group('SearchText', () {
    test('normalize: case, ё, punctuation, spaces', () {
      expect(SearchText.normalize('  Ёлка —  «Прованс»!! '), 'елка прованс');
      expect(SearchText.normalize("Don't  Stop"), 'don t stop');
      expect(SearchText.normalize('!!!'), '');
    });

    test('baseTitle drops brackets, featuring and remaster tails', () {
      expect(SearchText.baseTitle('Night Drive (Remastered 2011)'), 'night drive');
      expect(SearchText.baseTitle('Night Drive [Live at Wembley]'), 'night drive');
      expect(SearchText.baseTitle('Night Drive feat. Someone'), 'night drive');
      expect(SearchText.baseTitle('Night Drive - 2009 Remaster'), 'night drive');
      expect(SearchText.baseTitle('Night Drive - Part Two'), 'night drive part two');
      expect(SearchText.baseTitle('(Intro)'), 'intro');
    });

    test('variant tells recordings apart', () {
      expect(SearchText.variant('Night Drive'), '');
      expect(SearchText.variant('Night Drive (Remix)'), 'remix');
      expect(SearchText.variant('Night Drive - Live'), 'live');
      expect(SearchText.variant('Ночь (Акустика)'), 'acoustic');
      expect(SearchText.variant('Night Drive (Live Remix)'), 'live+remix');
    });

    test('mainArtist and songKey', () {
      expect(SearchText.mainArtist('Kavi feat. Someone'), 'kavi');
      expect(SearchText.mainArtist('Kavi & Lo'), 'kavi');
      expect(SearchText.mainArtist('Kavi, Lo'), 'kavi');
      expect(SearchText.songKey(stream('1', 'Night Drive (Remastered)', 'Kavi feat. X')),
          SearchText.songKey(preview('2', 'night drive', 'KAVI')));
      expect(SearchText.songKey(stream('1', 'Night Drive (Remix)', 'Kavi')),
          isNot(SearchText.songKey(stream('2', 'Night Drive', 'Kavi'))));
    });
  });

  group('score', () {
    test('exact beats partial; artist+title beats title alone', () {
      final exactBoth = SearchService.score('kavi night drive', stream('1', 'Night Drive', 'Kavi'));
      final exactTitle = SearchService.score('night drive', stream('1', 'Night Drive', 'Kavi'));
      final exactArtist = SearchService.score('kavi', stream('1', 'Night Drive', 'Kavi'));
      final partial = SearchService.score('night', stream('1', 'Night Drive', 'Kavi'));
      final prefix = SearchService.score('nig', stream('1', 'Night Drive', 'Kavi'));
      final none = SearchService.score('zebra', stream('1', 'Night Drive', 'Kavi'));
      expect(exactBoth, greaterThan(exactTitle));
      expect(exactTitle, greaterThan(exactArtist));
      expect(exactArtist, greaterThan(partial));
      expect(partial, greaterThan(prefix));
      expect(prefix, greaterThan(0));
      expect(none, 0);
    });

    test('query order and punctuation do not matter', () {
      final a = SearchService.score('Night Drive — Kavi', stream('1', 'Night Drive', 'Kavi'));
      final b = SearchService.score('kavi night drive', stream('1', 'Night Drive', 'Kavi'));
      expect(a, b);
      expect(a, 120);
    });

    test('remix and live drop below the original unless asked for', () {
      final original = SearchService.score('night drive', stream('1', 'Night Drive', 'Kavi'));
      final remix = SearchService.score('night drive', stream('2', 'Night Drive (Remix)', 'Kavi'));
      final askedRemix = SearchService.score('night drive remix', stream('2', 'Night Drive (Remix)', 'Kavi'));
      final plainWhenRemixAsked = SearchService.score('night drive remix', stream('1', 'Night Drive', 'Kavi'));
      expect(original, greaterThan(remix));
      expect(askedRemix, greaterThan(plainWhenRemixAsked));
    });

    test('a longer title that merely contains the query stays below the exact one', () {
      final exact = SearchService.score('lofi type beat', stream('1', 'Lofi Type Beat', 'Tezi'));
      final longer = SearchService.score('lofi type beat', stream('2', 'Lofi Type Beat  Love me', 'Beats Love'));
      final spread = SearchService.score('lofi type beat', stream('3', 'Type Beat Sessions', 'Lofi Crew'));
      // Title "Lofi" by the artist "Type Beat" is the exact pair the query
      // spells out, so it ranks as one (less the "instrumental" penalty).
      final pair = SearchService.score('lofi type beat', stream('4', 'Lofi (Beat Instrumental)', 'Type Beat'));
      expect(exact, 100);
      expect(longer, lessThan(exact));
      expect(spread, lessThan(exact));
      expect(longer, greaterThan(0));
      expect(spread, greaterThan(0));
      expect(pair, 106);
    });

    test('a half-matching query still finds something, but lower', () {
      final half = SearchService.score('night zebra', stream('1', 'Night Drive', 'Kavi'));
      final whole = SearchService.score('night drive', stream('1', 'Night Drive', 'Kavi'));
      expect(half, greaterThan(0));
      expect(half, lessThan(whole));
    });
  });

  group('merge and rank', () {
    SearchHit hit(Track t, SearchSource s, [double score = 100]) =>
        SearchHit(t, s, SearchService.availabilityOf(t), score);

    test('duplicates collapse to the copy that plays best', () {
      final merged = SearchService.merge([
        hit(preview('p', 'Night Drive', 'Kavi'), SearchSource.previews, 100),
        hit(stream('s', 'Night Drive (Remastered)', 'Kavi feat. X'), SearchSource.audius, 90),
        hit(local('l', 'night drive', 'KAVI'), SearchSource.local, 95),
        hit(stream('r', 'Night Drive (Remix)', 'Kavi'), SearchSource.audius, 80),
      ]);
      expect(merged.length, 2);
      final song = merged.firstWhere((h) => h.track.id == 'dev:l');
      expect(song.availability, Availability.offline);
      expect(song.source, SearchSource.local);
      expect(song.alsoIn, {SearchSource.audius, SearchSource.previews});
      expect(song.score, 100); // keeps the best relevance among the copies
      expect(merged.any((h) => h.track.id == 'au:r'), isTrue);
    });

    test('rank: relevance first, then playability; zero scores are dropped', () {
      final ranked = SearchService.rank([
        hit(preview('p', 'B', 'x'), SearchSource.previews, 100),
        hit(stream('s', 'A', 'x'), SearchSource.audius, 100),
        hit(local('l', 'C', 'x'), SearchSource.local, 100),
        hit(locked('u', 'D', 'x'), SearchSource.audius, 100),
        hit(local('weak', 'E', 'x'), SearchSource.local, 40),
        hit(stream('zero', 'F', 'x'), SearchSource.audius, 0),
      ]);
      expect(ranked.map((h) => h.track.id), ['dev:l', 'au:s', 'it:p', 'au:u', 'dev:weak']);
    });
  });

  group('SearchService', () {
    test('sources run in parallel and results are merged and ranked', () async {
      final started = <SearchSource>[];
      final gate = Completer<void>();
      Future<List<Track>> slow(SearchSource s, List<Track> tracks) async {
        started.add(s);
        await gate.future;
        return tracks;
      }

      final service = SearchService(
        sources: [
          TrackSource(SearchSource.local, (q) => slow(SearchSource.local, [local('1', 'Night Drive', 'Kavi')])),
          TrackSource(SearchSource.audius, (q) => slow(SearchSource.audius, [stream('2', 'Night Drive', 'Kavi'), stream('3', 'Night Sky', 'Lo')])),
          TrackSource(SearchSource.previews, (q) => slow(SearchSource.previews, [preview('4', 'Night Drive (Live)', 'Kavi')])),
        ],
        albumSearch: (q) async => [Album(id: 'rel', title: 'Night Tapes', artist: 'Lo')],
      );
      final pending = service.search('night drive');
      await Future<void>.delayed(Duration.zero);
      // Every source was asked before any of them answered.
      expect(started.toSet(), {SearchSource.local, SearchSource.audius, SearchSource.previews});
      gate.complete();
      final r = await pending;
      expect(r.problems, isEmpty);
      expect(r.albums.single.title, 'Night Tapes');
      expect(r.hits.map((h) => h.track.id), ['dev:1', 'it:4', 'au:3']);
      expect(r.hits.first.alsoIn, {SearchSource.audius});
      expect(r.hits.first.availability, Availability.offline);
    });

    test('a failing and a slow source are reported; the rest still answers', () async {
      final service = SearchService(
        sources: [
          TrackSource(SearchSource.local, (q) async => [local('1', 'Night Drive', 'Kavi')]),
          TrackSource(SearchSource.audius, (q) async => throw Exception('Audius ответил 503')),
          TrackSource(SearchSource.previews, (q) => Completer<List<Track>>().future,
              timeout: const Duration(milliseconds: 60)),
          TrackSource(SearchSource.server, (q) async => throw const FormatException('SocketException: Failed host lookup')),
        ],
        albumSearch: (q) async => throw StateError('boom'),
        albumTimeout: const Duration(milliseconds: 60),
      );
      final r = await service.search('night');
      expect(r.hits.single.track.id, 'dev:1');
      final bySource = {for (final p in r.problems) p.source: p.message};
      expect(bySource[SearchSource.audius], 'Audius ответил 503');
      expect(bySource[SearchSource.previews], 'не ответил за 0 с');
      expect(bySource[SearchSource.server], 'нет связи с источником');
      expect(bySource.containsKey(SearchSource.archive), isTrue);
      expect(r.problems.first.toString(), startsWith('Audius: '));
    });

    test('an empty or punctuation-only query asks nobody', () async {
      var asked = 0;
      final service = SearchService(sources: [
        TrackSource(SearchSource.local, (q) async {
          asked++;
          return [];
        }),
      ]);
      expect((await service.search('   ')).isEmpty, isTrue);
      expect((await service.search('?!')).isEmpty, isTrue);
      expect(asked, 0);
    });
  });
}
