import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../main.dart';
import '../models.dart';
import 'theme.dart';

String _seed(Track t) => t.album + t.artist;

/// Floating card above the tab bar, tinted by the current artwork.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final t = player.current;
        if (t == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
          child: ArtColorBuilder(
            art: t.art,
            seed: _seed(t),
            builder: (context, color) => Material(
              color: Color.lerp(color, kBg, .35),
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              elevation: 6,
              shadowColor: Colors.black,
              child: InkWell(
                onTap: () => Navigator.of(context, rootNavigator: true).push(_playerRoute()),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 2, 8),
                      child: Row(
                        children: [
                          Cover(t.art, size: 42, radius: 8, seed: _seed(t)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                                Text(t.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: Colors.white.withValues(alpha: .7), fontSize: 12.5)),
                              ],
                            ),
                          ),
                          ListenableBuilder(
                            listenable: library,
                            builder: (_, _) {
                              final fav = library.isFavorite(t);
                              return IconButton(
                                tooltip: fav ? 'Убрать из избранного' : 'В избранное',
                                onPressed: () {
                                  HapticFeedback.lightImpact();
                                  library.toggleFavorite(t);
                                },
                                icon: Icon(fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                    color: fav ? kAccent : Colors.white),
                              );
                            },
                          ),
                          IconButton(
                            tooltip: player.playing ? 'Пауза' : 'Играть',
                            onPressed: player.toggle,
                            icon: Icon(player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                size: 32, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    if (!t.isRadio)
                      StreamBuilder<Duration>(
                        stream: player.audio.positionStream,
                        builder: (_, snap) {
                          final total = player.audio.duration?.inMilliseconds ?? 0;
                          final pos = snap.data?.inMilliseconds ?? 0;
                          return LinearProgressIndicator(
                            value: total == 0 ? 0 : (pos / total).clamp(0, 1).toDouble(),
                            minHeight: 2,
                            color: Colors.white,
                            backgroundColor: Colors.white.withValues(alpha: .15),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

Route<void> _playerRoute() => PageRouteBuilder(
      fullscreenDialog: true,
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, _, _) => const PlayerPage(),
      transitionsBuilder: (_, anim, _, child) => SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic)),
        child: child,
      ),
    );

/// Full-screen player: blurred artwork backdrop, large cover that breathes
/// with play and pause, and the queue in a bottom sheet.
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
        final provider = artProvider(t.art);
        return Scaffold(
          backgroundColor: Colors.black,
          body: GestureDetector(
            // Swipe down to close, like a sheet.
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) > 500) Navigator.pop(context);
            },
            child: ArtColorBuilder(
              art: t.art,
              seed: _seed(t),
              builder: (context, color) => Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [color, Color.lerp(color, Colors.black, .78)!],
                      ),
                    ),
                  ),
                  if (provider != null)
                    Opacity(
                      opacity: .5,
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70, tileMode: TileMode.mirror),
                        child: Image(image: provider, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
                      ),
                    ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black.withValues(alpha: .10), Colors.black.withValues(alpha: .62)],
                      ),
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 26),
                      child: Column(
                        children: [
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              IconButton(
                                  tooltip: 'Свернуть',
                                  onPressed: () => Navigator.pop(context),
                                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 34, color: Colors.white)),
                              Expanded(
                                child: Column(
                                  children: [
                                    Text(t.isRadio ? 'РАДИО' : (t.isPreview ? 'ФРАГМЕНТ · 30 СЕКУНД' : 'СЕЙЧАС ИГРАЕТ'),
                                        style: TextStyle(
                                            color: Colors.white.withValues(alpha: .7),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 1.4)),
                                    if (t.album.isNotEmpty && !t.isRadio)
                                      Text(t.album,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                              IconButton(
                                  tooltip: 'Очередь',
                                  onPressed: () => _showQueue(context),
                                  icon: const Icon(Icons.queue_music_rounded, color: Colors.white)),
                            ],
                          ),
                          Expanded(
                            child: Center(
                              child: LayoutBuilder(builder: (_, c) {
                                final side = c.biggest.shortestSide.clamp(120.0, 380.0);
                                return AnimatedScale(
                                  scale: player.playing ? 1 : .86,
                                  duration: const Duration(milliseconds: 420),
                                  curve: Curves.easeOutBack,
                                  child: Cover(t.art, size: side, radius: 18, seed: _seed(t), shadow: true),
                                );
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
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 24,
                                            height: 1.15,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -.4)),
                                    const SizedBox(height: 4),
                                    Text(t.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: Colors.white.withValues(alpha: .72),
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              _LikeButton(fav: fav, onTap: () => library.toggleFavorite(t)),
                            ],
                          ),
                          const SizedBox(height: 14),
                          if (t.isRadio) const _LiveBadge() else const _Seek(),
                          if (t.isAudius && t.link != null)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                style: TextButton.styleFrom(
                                    foregroundColor: Colors.white70, padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
                                onPressed: () => openLink(context, t.link!),
                                icon: const Icon(Icons.open_in_new_rounded, size: 15),
                                label: const Text('Музыка с Audius', style: TextStyle(fontSize: 12.5)),
                              ),
                            ),
                          if (t.isPreview && t.link != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)),
                                onPressed: () => openLink(context, t.link!),
                                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                                label: const Text('Слушать целиком в Apple Music'),
                              ),
                            ),
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
                                icon: Icon(Icons.shuffle_rounded,
                                    color:
                                        player.audio.shuffleModeEnabled ? kAccent : Colors.white.withValues(alpha: .7)),
                              ),
                              IconButton(
                                  tooltip: 'Предыдущий',
                                  onPressed: player.previous,
                                  icon: const Icon(Icons.skip_previous_rounded, size: 46, color: Colors.white)),
                              _PlayButton(playing: player.playing, loading: player.loading, onTap: player.toggle),
                              IconButton(
                                  tooltip: 'Следующий',
                                  onPressed: player.next,
                                  icon: const Icon(Icons.skip_next_rounded, size: 46, color: Colors.white)),
                              IconButton(
                                tooltip: 'Повтор',
                                onPressed: player.cycleLoop,
                                icon: Icon(
                                  player.audio.loopMode == LoopMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                                  color: player.audio.loopMode == LoopMode.off
                                      ? Colors.white.withValues(alpha: .7)
                                      : kAccent,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 30),
                        ],
                      ),
                    ),
                  ),
                ],
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
                  child: Text('Далее', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                );
              }
              final t = player.queue[i - 1];
              final isCurrent = i - 1 == player.index;
              return ListTile(
                leading: Cover(t.art, size: 44, radius: 6, seed: _seed(t)),
                title: Text(t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: isCurrent ? kAccent : kInk, fontWeight: FontWeight.w600)),
                subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: isCurrent ? const Icon(Icons.graphic_eq_rounded, color: kAccent) : null,
                onTap: () => player.jumpTo(i - 1),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.loading, required this.onTap});
  final bool playing;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: playing ? 'Пауза' : 'Играть',
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 8,
        shadowColor: Colors.black,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: SizedBox(
            width: 76,
            height: 76,
            child: Center(
              child: loading && !playing
                  ? const SizedBox(
                      width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.black))
                  : AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                      child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          key: ValueKey(playing), size: 44, color: Colors.black),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Heart that pops when a track is liked.
class _LikeButton extends StatelessWidget {
  const _LikeButton({required this.fav, required this.onTap});
  final bool fav;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: fav ? 'Убрать из избранного' : 'В избранное',
      onPressed: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      icon: TweenAnimationBuilder<double>(
        key: ValueKey(fav),
        tween: Tween(begin: fav ? 1.45 : 1, end: 1),
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutBack,
        builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
        child: Icon(fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            size: 30, color: fav ? kAccent : Colors.white),
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22, top: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(20)),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 8, color: Color(0xFFFF5A6E)),
                SizedBox(width: 6),
                Text('ПРЯМОЙ ЭФИР',
                    style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1)),
              ],
            ),
          ),
        ],
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
    const time = TextStyle(
        color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]);
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
                trackHeight: _drag == null ? 4 : 7,
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white.withValues(alpha: .22),
                thumbColor: Colors.white,
                overlayShape: SliderComponentShape.noOverlay,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: _drag == null ? 5 : 8),
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
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(formatDuration(Duration(milliseconds: pos.round())), style: time),
                Text('-${formatDuration(total - Duration(milliseconds: pos.round()))}', style: time),
              ],
            ),
            const SizedBox(height: 10),
          ],
        );
      },
    );
  }
}
