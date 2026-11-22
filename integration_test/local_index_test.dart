// Opens the SQLite index inside the real app runtime (not the test VM) and
// checks a file-backed search.   flutter test integration_test/local_index_test.dart -d linux
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hamsterfy/models.dart';
import 'package:hamsterfy/search/local_index.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('index opens on disk, survives a reopen and searches', (tester) async {
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('hamsterfy_index');
      final path = '${dir.path}/search.db';
      var index = await LocalIndex.open(path);
      await index.sync([
        Track(id: 'a', title: 'Ночной город', artist: 'Северный ветер', genre: 'Synthwave', path: '/m/a.mp3'),
        Track(id: 'b', title: 'Утро', artist: 'Лес', path: '/m/b.mp3'),
      ]);
      expect(await index.search('synth'), ['a']);
      await index.close();
      expect(File(path).existsSync(), isTrue);

      index = await LocalIndex.open(path);
      expect(await index.count(), 2);
      expect(await index.search('ноч'), ['a']);
      expect(await index.suggest('сев'), ['Северный ветер']);
      await index.close();
      // ignore: avoid_print
      print('CHECK index file: ${File(path).lengthSync()} bytes');
      await dir.delete(recursive: true);
    });
  });
}
