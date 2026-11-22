import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'library.dart';
import 'models.dart';

/// Playback queue on top of just_audio, with lock-screen controls.
class Player extends ChangeNotifier {
  Player(this.library) {
    _subs = [
      audio.currentIndexStream.listen((i) {
        if (i == null || i >= queue.length) return;
        final next = queue[i];
        if (next.id != current?.id) {
          current = next;
          library.recordPlay(next);
          unawaited(library.cacheAfterPlay(next));
        }
        notifyListeners();
      }),
      audio.playerStateStream.listen((_) => notifyListeners()),
      audio.shuffleModeEnabledStream.listen((_) => notifyListeners()),
      audio.loopModeStream.listen((_) => notifyListeners()),
    ];
  }

  final Library library;
  final audio = AudioPlayer();
  late final List<StreamSubscription<dynamic>> _subs;

  List<Track> queue = [];
  Track? current;
  String? error;

  bool get playing => audio.playing;
  bool get loading =>
      audio.processingState == ProcessingState.loading || audio.processingState == ProcessingState.buffering;
  int get index => audio.currentIndex ?? 0;

  AudioSource _source(Track t) {
    final art = t.art;
    return AudioSource.uri(
      t.isLocal ? Uri.file(t.path!) : Uri.parse(t.url!),
      tag: MediaItem(
        id: t.id,
        title: t.title,
        artist: t.artist,
        album: t.album,
        artUri: art == null ? null : (art.startsWith('http') ? Uri.parse(art) : Uri.file(art)),
      ),
    );
  }

  /// Replaces the queue and starts playing from [start].
  Future<void> playAll(List<Track> tracks, {int start = 0}) async {
    final playable = tracks.where((t) => t.isLocal || t.url != null).toList();
    if (playable.isEmpty) return;
    final first = tracks[start.clamp(0, tracks.length - 1)];
    final startIndex = playable.indexOf(first).clamp(0, playable.length - 1);
    queue = playable;
    current = null;
    error = null;
    try {
      await audio.setAudioSources([for (final t in playable) _source(t)], initialIndex: startIndex);
      unawaited(audio.play());
    } catch (e) {
      error = 'Не удалось запустить трек. Проверьте файл или подключение к интернету.';
      notifyListeners();
    }
  }

  Timer? _sleepTimer;

  /// When the sleep timer will pause playback, or null when it is off.
  DateTime? sleepAt;

  /// Pauses playback after [after]; null turns the timer off.
  void setSleepTimer(Duration? after) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepAt = null;
    if (after != null) {
      sleepAt = DateTime.now().add(after);
      _sleepTimer = Timer(after, () {
        audio.pause();
        sleepAt = null;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  /// Stops playback and empties the queue, e.g. when the profile changes.
  Future<void> reset() async {
    setSleepTimer(null);
    await audio.stop();
    queue = [];
    current = null;
    error = null;
    notifyListeners();
  }

  Future<void> jumpTo(int i) async {
    await audio.seek(Duration.zero, index: i);
    unawaited(audio.play());
  }

  void toggle() => playing ? audio.pause() : audio.play();
  void next() => audio.seekToNext();
  void previous() => audio.position > const Duration(seconds: 3) ? audio.seek(Duration.zero) : audio.seekToPrevious();
  void toggleShuffle() => audio.setShuffleModeEnabled(!audio.shuffleModeEnabled);
  void cycleLoop() => audio.setLoopMode(switch (audio.loopMode) {
        LoopMode.off => LoopMode.all,
        LoopMode.all => LoopMode.one,
        LoopMode.one => LoopMode.off,
      });

  @override
  void dispose() {
    _sleepTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    audio.dispose();
    super.dispose();
  }
}
