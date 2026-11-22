import 'package:flutter_test/flutter_test.dart';
import 'package:hamsterfy/models.dart';
import 'package:hamsterfy/search/local_index.dart';

Track t(String id, String title, String artist, {String album = '', String genre = ''}) =>
    Track(id: id, title: title, artist: artist, album: album, genre: genre, path: '/m/$id.mp3');

void main() {
  late LocalIndex index;

  setUp(() async => index = await LocalIndex.open());
  tearDown(() => index.close());

  final library = [
    t('1', 'Ночной город', 'Северный ветер', album: 'Огни', genre: 'Synthwave'),
    t('2', 'Ночь без сна', 'Тихие волны', album: 'Берег', genre: 'Ambient'),
    t('3', 'Город засыпает', 'Северный ветер', album: 'Огни', genre: 'Synthwave'),
    t('4', 'Ёлка у реки', 'Лес', genre: 'Folk'),
    t('5', "Don't Stop", 'The Runners', album: 'Miles', genre: 'Rock'),
  ];

  test('finds by title, artist, album and genre, by word prefix', () async {
    expect(await index.sync(library), 5);
    expect(await index.count(), 5);
    Future<Set<String>> ids(String q) async => (await index.search(q)).toSet();

    expect(await ids('ночной'), {'1'});
    expect(await ids('ноч'), {'1', '2'}); // prefix of "ночной" and "ночь"
    expect(await ids('северный'), {'1', '3'}); // artist
    expect(await ids('огни'), {'1', '3'}); // album
    expect(await ids('synthwave'), {'1', '3'}); // genre
    expect(await ids('SYNTH'), {'1', '3'}); // case and prefix
    expect(await ids('город север'), {'1', '3'}); // words from different fields
    expect(await ids('город ноч'), {'1'}); // every word must match
    expect(await ids('елка'), {'4'}); // ё and е are the same
    expect(await ids("don't stop"), {'5'}); // punctuation is ignored
    expect(await ids('runners miles rock'), {'5'});
    expect(await ids('zzz'), isEmpty);
    expect(await ids('   '), isEmpty);
    expect(await ids('ород'), isEmpty); // not the start of a word
  });

  test('sync adds, rewrites and removes; unchanged rows are not touched', () async {
    await index.sync(library);
    expect(await index.sync(library), 0);
    final edited = [
      ...library.where((x) => x.id != '2' && x.id != '5'),
      t('5', "Don't Stop", 'The Runners', album: 'Miles', genre: 'Indie'), // genre changed
      t('6', 'Новый трек', 'Лес'),
    ];
    expect(await index.sync(edited), 3); // one removed, one rewritten, one added
    expect(await index.count(), 5);
    expect(await index.search('ночь'), isEmpty); // removed
    expect(await index.search('rock'), isEmpty); // old genre is gone
    expect(await index.search('indie'), ['5']);
    expect((await index.search('лес')).toSet(), {'4', '6'});
    expect(await index.sync(const []), 5);
    expect(await index.count(), 0);
  });

  test('suggestions continue the word being typed, artists first', () async {
    await index.sync(library);
    expect(await index.suggest('сев'), ['Северный ветер']);
    expect(await index.suggest('ноч'), ['Ночной город', 'Ночь без сна']);
    expect(await index.suggest('гор'), ['Город засыпает', 'Ночной город']);
    // Second word narrows the offer to that artist's titles.
    expect(await index.suggest('северный гор'), ['Город засыпает', 'Ночной город']);
    expect(await index.suggest('северный ветер'), isEmpty); // already typed in full
    expect(await index.suggest(''), isEmpty);
    expect(await index.suggest('zzz'), isEmpty);
  });

  test('stays fast on a large library', () async {
    final many = [
      for (var i = 0; i < 5000; i++) t('n$i', 'Песня номер $i', 'Артист ${i % 50}', album: 'Альбом ${i % 200}', genre: 'Жанр ${i % 10}'),
    ];
    await index.sync(many);
    final watch = Stopwatch()..start();
    final found = await index.search('песня 4999');
    watch.stop();
    expect(found, ['n4999']);
    expect(watch.elapsedMilliseconds, lessThan(300));
  });
}
