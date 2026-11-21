// End-to-end check of the Audius integration against the live service,
// using the same code the app runs: search → pick a playable track →
// resolve its stream → read real audio bytes.
//
//   dart run tool/audius_check.dart "query"
import 'dart:io';

import 'package:hamsterfy/audius.dart';
import 'package:http/io_client.dart';

Future<void> main(List<String> args) async {
  final query = args.isEmpty ? 'lofi' : args.join(' ');
  final io = HttpClient()..findProxy = HttpClient.findProxyFromEnvironment;
  final client = IOClient(io);

  stdout.writeln('1. Запрос: "$query"');
  final found = await Audius(client: client).search(query);
  final playable = found.where((t) => !t.isUnavailable).toList();
  stdout.writeln('2. Найдено треков: ${found.length}, из них со свободным прослушиванием: ${playable.length}');
  if (playable.isEmpty) {
    stdout.writeln('   Нет треков для проверки.');
    exit(1);
  }
  final t = playable.first;
  stdout.writeln('3. Выбран трек: «${t.title}» — ${t.artist}, ${t.durationMs ~/ 1000} с');
  stdout.writeln('   Страница: ${t.link}');

  try {
    final cover = await client.get(Uri.parse(t.art!));
    stdout.writeln('4. Обложка: HTTP ${cover.statusCode}, ${cover.headers['content-type']}, ${cover.bodyBytes.length} байт');
  } catch (e) {
    stdout.writeln('4. Обложка: ${Uri.parse(t.art!).host} недоступен из этой сети ($e)');
  }

  // The player does exactly this: GET the stream address, follow the redirect.
  final req = await io.getUrl(Uri.parse(t.url!));
  req.headers.set('Range', 'bytes=0-262143');
  final res = await req.close();
  final bytes = <int>[];
  await for (final chunk in res) {
    bytes.addAll(chunk);
  }
  final hops = res.redirects.map((r) => r.location.host).join(' → ');
  stdout.writeln('5. Поток: HTTP ${res.statusCode} (перенаправление на $hops)');
  stdout.writeln('   Тип: ${res.headers.value('content-type')}, диапазон: ${res.headers.value('content-range')}');
  final id3 = bytes.length > 3 && String.fromCharCodes(bytes.take(3)) == 'ID3';
  final frame = bytes.length > 2 && bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0;
  stdout.writeln('6. Получено ${bytes.length} байт, начало файла: ${id3 ? 'ID3-тег MP3' : (frame ? 'кадр MP3' : 'неизвестно')}');
  await File(args.length > 1 ? args[1] : '/tmp/audius_sample.mp3').writeAsBytes(bytes);
  client.close();
  exit(res.statusCode == 206 || res.statusCode == 200 ? 0 : 1);
}
