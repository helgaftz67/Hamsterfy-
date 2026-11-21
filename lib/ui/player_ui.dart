import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../main.dart';
import 'theme.dart';

/// Compact player shown above the tab bar while something is queued.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final t = player.current;
        if (t == null) return const SizedBox.shrink();
        return Material(
          color: kSunken,
          child: InkWell(
            onTap: () => Navigator.of(context, rootNavigator: true)
                .push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const PlayerPage())),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  child: Row(
                    children: [
                      Cover(t.art, size: 40, radius: 6, seed: t.album + t.artist),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(t.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: kMuted, fontSize: 12.5)),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: library.isFavorite(t) ? 'Убрать из избранного' : 'В избранное',
                        onPressed: () => library.toggleFavorite(t),
                        icon: ListenableBuilder(
                          listenable: library,
                          builder: (_, _) => Icon(
                            library.isFavorite(t) ? Icons.favorite : Icons.favorite_border,
                            color: library.isFavorite(t) ? kAccent : kMuted,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: player.playing ? 'Пауза' : 'Играть',
                        onPressed: player.toggle,
                        icon: Icon(player.playing ? Icons.pause : Icons.play_arrow, size: 30),
                      ),
                    ],
                  ),
                ),
                StreamBuilder<Duration>(
                  stream: player.audio.positionStream,
                  builder: (_, snap) {
                    final total = player.audio.duration?.inMilliseconds ?? 0;
                    final pos = snap.data?.inMilliseconds ?? 0;
                    return LinearProgressIndicator(
                      value: total == 0 ? 0 : (pos / total).clamp(0, 1).toDouble(),
                      minHeight: 2,
                      backgroundColor: Colors.transparent,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Full-screen player with the queue in a bottom sheet.
class PlayerPage extends StatelessWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([player, library]),
      builder: (context, _) {
        final t = player.current;
        if (t == null) {
          return Scaffold(appBar: AppBar(), body: const Center(child: Text('Ничего не играет')));
        }
        final fav = library.isFavorite(t);
        final hue = ((t.album + t.artist).hashCode % 360).abs().toDouble();
        return Scaffold(
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [HSLColor.fromAHSL(1, hue, .4, .22).toColor(), kBg],
                stops: const [0, .7],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                            tooltip: 'Свернуть',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.keyboard_arrow_down, size: 30)),
                        Expanded(
                          child: Text(t.album.isEmpty ? 'Сейчас играет' : t.album,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: kMuted, fontSize: 13)),
                        ),
                        IconButton(
                            tooltip: 'Очередь',
                            onPressed: () => _showQueue(context),
                            icon: const Icon(Icons.queue_music)),
                      ],
                    ),
                    Expanded(
                      child: Center(
                        child: LayoutBuilder(builder: (_, c) {
                          final side = c.biggest.shortestSide.clamp(120.0, 360.0);
                          return Cover(t.art, size: side, radius: 16, seed: t.album + t.artist);
                        }),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text(t.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: kMuted, fontSize: 15)),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: fav ? 'Убрать из избранного' : 'В избранное',
                          onPressed: () => library.toggleFavorite(t),
                          icon: Icon(fav ? Icons.favorite : Icons.favorite_border,
                              size: 28, color: fav ? kAccent : kInk),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const _Seek(),
                    if (player.error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(player.error!, style: const TextStyle(color: kAmber, fontSize: 13)),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          tooltip: 'Перемешать',
                          onPressed: player.toggleShuffle,
                          icon: Icon(Icons.shuffle, color: player.audio.shuffleModeEnabled ? kAccent : kMuted),
                        ),
                        IconButton(
                            tooltip: 'Предыдущий',
                            onPressed: player.previous,
                            icon: const Icon(Icons.skip_previous, size: 40)),
                        SizedBox(
                          width: 72,
                          height: 72,
                          child: IconButton.filled(
                            tooltip: player.playing ? 'Пауза' : 'Играть',
                            onPressed: player.toggle,
                            icon: player.loading && !player.playing
                                ? const SizedBox(
                                    width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3, color: kBg))
                                : Icon(player.playing ? Icons.pause : Icons.play_arrow, size: 40),
                          ),
                        ),
                        IconButton(
                            tooltip: 'Следующий', onPressed: player.next, icon: const Icon(Icons.skip_next, size: 40)),
                        IconButton(
                          tooltip: 'Повтор',
                          onPressed: player.cycleLoop,
                          icon: Icon(
                            player.audio.loopMode == LoopMode.one ? Icons.repeat_one : Icons.repeat,
                            color: player.audio.loopMode == LoopMode.off ? kMuted : kAccent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showQueue(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kSurface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .6,
        maxChildSize: .92,
        builder: (context, scroll) => ListenableBuilder(
          listenable: player,
          builder: (context, _) => ListView.builder(
            controller: scroll,
            itemCount: player.queue.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text('Далее', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                );
              }
              final t = player.queue[i - 1];
              final isCurrent = i - 1 == player.index;
              return ListTile(
                leading: Cover(t.art, size: 40, radius: 6, seed: t.album + t.artist),
                title: Text(t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: isCurrent ? kAccent : kInk)),
                subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: isCurrent ? const Icon(Icons.graphic_eq, color: kAccent) : null,
                onTap: () => player.jumpTo(i - 1),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Seek extends StatefulWidget {
  const _Seek();

  @override
  State<_Seek> createState() => _SeekState();
}

class _SeekState extends State<_Seek> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.audio.positionStream,
      builder: (context, snap) {
        final total = player.audio.duration ?? Duration(milliseconds: player.current?.durationMs ?? 0);
        final max = total.inMilliseconds.toDouble();
        final pos = (_drag ?? (snap.data?.inMilliseconds ?? 0).toDouble()).clamp(0.0, max <= 0 ? 0.0 : max);
        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                overlayShape: SliderComponentShape.noOverlay,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                min: 0,
                max: max <= 0 ? 1 : max,
                value: pos,
                onChanged: max <= 0 ? null : (v) => setState(() => _drag = v),
                onChangeEnd: (v) {
                  player.audio.seek(Duration(milliseconds: v.round()));
                  setState(() => _drag = null);
                },
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(formatDuration(Duration(milliseconds: pos.round())),
                    style: const TextStyle(color: kMuted, fontSize: 12, fontFeatures: [FontFeature.tabularFigures()])),
                Text(formatDuration(total),
                    style: const TextStyle(color: kMuted, fontSize: 12, fontFeatures: [FontFeature.tabularFigures()])),
              ],
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}
