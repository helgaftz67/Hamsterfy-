// Live end-to-end check on the desktop audio engine: search Audius, start a
// real track, seek to the middle and confirm playback keeps advancing.
//
//   flutter test integration_test/audius_playback_test.dart -d linux
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hamsterfy/audius.dart';
import 'package:hamsterfy/library.dart';
import 'package:hamsterfy/player.dart';
import 'package:http/io_client.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

Future<void> waitFor(bool Function() ok, String what, {int seconds = 60}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!ok()) {
    if (DateTime.now().isAfter(end)) fail('Не дождались: $what');
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('search → play → seek to the middle', (tester) async {
    await tester.runAsync(() async {
      JustAudioMediaKit.ensureInitialized();
      final io = HttpClient()..findProxy = HttpClient.findProxyFromEnvironment;
      const query = String.fromEnvironment('QUERY', defaultValue: 'lofi');

      final found = await Audius(client: IOClient(io)).search(query);
      final track = found.firstWhere((t) => !t.isUnavailable && t.durationMs > 120000 && t.durationMs < 600000);
      // ignore: avoid_print
      print('CHECK track: "${track.title}" — ${track.artist}, ${track.durationMs ~/ 1000} s, ${track.link}');

      final library = Library()..autoCache = false;
      final player = Player(library);
      await player.playAll([track]);
      await waitFor(() => player.playing && player.audio.position > const Duration(seconds: 2), 'начало воспроизведения');
      // ignore: avoid_print
      print('CHECK started: position ${player.audio.position.inSeconds} s, duration ${player.audio.duration?.inSeconds} s');

      final middle = Duration(milliseconds: track.durationMs ~/ 2);
      await player.audio.seek(middle);
      // ignore: avoid_print
      print('CHECK seek to ${middle.inSeconds} s');
      await waitFor(() => player.audio.position > middle + const Duration(seconds: 5), 'продолжение после перемотки');
      // ignore: avoid_print
      print('CHECK after seek: position ${player.audio.position.inSeconds} s, playing ${player.playing}');
      expect(player.playing, isTrue);
      expect(player.error, isNull);
      await player.audio.stop();
    });
  });
}
