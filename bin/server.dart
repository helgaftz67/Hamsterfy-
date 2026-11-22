// Hamsterfy personal music server.
//
//   dart run bin/server.dart --music "D:\Music" --port 8787 --token secret
//
// Or build a single program: dart compile exe bin/server.dart -o hamsterfy-server
import 'dart:io';

import 'package:hamsterfy/server/music_server.dart';
import 'package:http/io_client.dart';

String? _arg(List<String> args, String name) {
  final i = args.indexOf('--$name');
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln('Hamsterfy Server\n'
        '  --music ПАПКА   папка с музыкой (по умолчанию ./music)\n'
        '  --port НОМЕР    порт (по умолчанию 8787)\n'
        '  --token КЛЮЧ    ключ доступа; без него сервер открыт всем в сети');
    return;
  }
  final port = int.tryParse(_arg(args, 'port') ?? '') ?? 8787;
  final folder = Directory(_arg(args, 'music') ?? 'music').absolute;
  final token = _arg(args, 'token') ?? Platform.environment['HAMSTERFY_TOKEN'];

  // Honour system proxy settings for the catalog lookups.
  final io = HttpClient()..findProxy = HttpClient.findProxyFromEnvironment;
  final server = MusicServer(music: folder, token: token, client: IOClient(io));

  try {
    final n = await server.scan();
    stdout.writeln('Папка с музыкой: ${folder.path} — треков: $n');
  } on ApiError catch (e) {
    server.log('scan', e.message);
    stdout.writeln('ВНИМАНИЕ: ${e.message}. Сервер запустится без своих треков.');
  }

  try {
    await server.start(port: port);
  } on SocketException catch (e) {
    stderr.writeln('Не удалось занять порт $port: ${e.message}. Возможно, сервер уже запущен; выберите другой порт через --port.');
    exit(1);
  }
  stdout.writeln('Сервер работает: http://localhost:$port/');
  for (final iface in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
    for (final a in iface.addresses) {
      if (!a.isLoopback) stdout.writeln('В домашней сети:   http://${a.address}:$port/');
    }
  }
  if (token == null || token.isEmpty) {
    stdout.writeln('Ключ доступа не задан: сервер ответит любому устройству в сети. Задайте --token, если это не подходит.');
  }
}
