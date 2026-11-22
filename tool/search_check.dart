// Runs the unified search against the live catalogs and prints the ranked
// result with sources.   dart run tool/search_check.dart "query"
import 'dart:io';

import 'package:hamsterfy/audius.dart';
import 'package:hamsterfy/catalog.dart';
import 'package:hamsterfy/models.dart';
import 'package:hamsterfy/search/search_service.dart';
import 'package:hamsterfy/songs.dart';
import 'package:http/io_client.dart';

Future<void> main(List<String> args) async {
  final query = args.isEmpty ? 'lofi' : args.join(' ');
  final client = IOClient(HttpClient()..findProxy = HttpClient.findProxyFromEnvironment);
  // Two tracks stand in for the device library.
  final mine = [
    Track(id: 'dev:1', title: 'Lofi Type Beat', artist: '[bsdu]', path: '/m/1.mp3'),
    Track(id: 'dev:2', title: 'Совсем другое', artist: 'Кто-то', path: '/m/2.mp3'),
  ];
  final service = SearchService(
    sources: [
      TrackSource(SearchSource.local, (q) async => mine.where((t) => SearchService.score(q, t) > 0).toList()),
      TrackSource(SearchSource.audius, Audius(client: client).search),
      TrackSource(SearchSource.previews, SongSearch(client: client).search),
      TrackSource(SearchSource.server, (q) async => throw Exception('сервер выключен')),
    ],
    albumSearch: Catalog(client: client).search,
  );
  final watch = Stopwatch()..start();
  final r = await service.search(query);
  stdout.writeln('"$query": ${r.hits.length} треков, ${r.albums.length} релизов за ${watch.elapsedMilliseconds} мс');
  final by = <String, int>{};
  for (final h in r.hits) {
    by['${h.source.label}/${h.availability.label}'] = (by['${h.source.label}/${h.availability.label}'] ?? 0) + 1;
  }
  stdout.writeln('по источникам: $by');
  stdout.writeln('склеено дубликатов: ${r.hits.where((h) => h.alsoIn.isNotEmpty).length}');
  for (final h in r.hits.take(8)) {
    final also = h.alsoIn.isEmpty ? '' : ' (+${h.alsoIn.map((s) => s.label).join(', ')})';
    stdout.writeln('  ${h.score.toStringAsFixed(0).padLeft(3)}  [${h.source.label} · ${h.availability.label}]$also  ${h.track.title} — ${h.track.artist}');
  }
  for (final p in r.problems) {
    stdout.writeln('  ! $p');
  }
  exit(0);
}
