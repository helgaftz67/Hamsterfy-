import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hamsterfy/lyrics.dart';
import 'package:hamsterfy/models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('LRC lines are parsed in time order and found by position', () {
    final l = Lyrics(synced: Lyrics.parseLrc('[00:12.50] second\n[00:01.2]first\nno stamp\n[01:02:03] third'));
    expect(l.synced.map((x) => x.text), ['first', 'second', 'third']);
    expect(l.synced[0].at, const Duration(milliseconds: 1200));
    expect(l.synced[2].at, const Duration(minutes: 1, seconds: 2, milliseconds: 30));
    expect(l.lineAt(Duration.zero), -1);
    expect(l.lineAt(const Duration(seconds: 13)), 1);
  });

  test('uploader-style titles are read as "artist - song"', () {
    final t = Track(id: 'au:1', title: 'Band - Song Name (Official Video)', artist: 'uploader');
    expect(LyricsService.candidates(t), [('Band', 'Song Name'), ('uploader', 'Band - Song Name')]);
  });

  test('picks the cut of matching length and drops timings of another cut', () {
    final body = jsonEncode([
      {'duration': 300, 'plainLyrics': 'long', 'syncedLyrics': '[00:01.00] long'},
      {'duration': 201, 'plainLyrics': 'right', 'syncedLyrics': '[00:01.00] right'},
      {'duration': 200, 'plainLyrics': '', 'syncedLyrics': ''},
    ]);
    final l = LyricsService.pick(body, 200000)!;
    expect(l.plain, 'right');
    expect(l.synced.single.text, 'right');
    expect(LyricsService.pick(body, 100000)!.synced, isEmpty);
    expect(LyricsService.pick('[]', 0), isNull);
  });

  test('tries the next reading of the tags, caches the answer, reports failures', () async {
    final asked = <String>[];
    var fail = false;
    final service = LyricsService(client: MockClient((req) async {
      asked.add('${req.url.queryParameters['artist_name']}|${req.url.queryParameters['track_name']}');
      if (fail) return http.Response('down', 503);
      if (req.url.queryParameters['artist_name'] == 'Band') return http.Response('[]', 200);
      return http.Response.bytes(utf8.encode(jsonEncode([{'plainLyrics': 'слова'}])), 200);
    }));
    final t = Track(id: 'x', title: 'Band - Song', artist: 'uploader');
    expect((await service.find(t))!.plain, 'слова');
    await service.find(t);
    expect(asked, ['Band|Song', 'uploader|Band - Song']);
    fail = true;
    expect(() => service.find(Track(id: 'y', title: 'Other', artist: 'a')), throwsException);
  });
}
