import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../lyrics.dart';
import '../main.dart';
import '../models.dart';
import 'glass.dart';
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
          padding: const EdgeInsets.only(bottom: 8),
          child: ArtColorBuilder(
            art: t.art,
            seed: _seed(t),
            builder: (context, color) => Dismissible(
              // Swipe the capsule sideways to change the track.
              key: ValueKey('mini-${t.id}'),
              confirmDismiss: (direction) async {
                HapticFeedback.selectionClick();
                direction == DismissDirection.endToStart ? player.next() : player.previous();
                return false;
              },
              child: Pressable(
                label: 'Открыть плеер: ${t.title}',
                onTap: () => Navigator.of(context, rootNavigator: true).push(_playerRoute()),
                child: Glass(
                  radius: 31,
                  tint: Color.lerp(color, const Color(0xFF2B2429), .45),
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
                        child: Row(
                          children: [
                            Cover(t.art, size: 46, radius: 23, seed: _seed(t)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(t.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                                  Text(t.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: Colors.white.withValues(alpha: .72), fontSize: 12.5)),
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
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                player.toggle();
                              },
                              icon: Container(
                                width: 40,
                                height: 40,
                                decoration: const BoxDecoration(color: kCream, shape: BoxShape.circle),
                                child: Icon(player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    size: 26, color: Colors.black),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Progress as a thin line of light along the bottom edge.
                      if (!t.isRadio)
                        Positioned(
                          left: 30,
                          right: 30,
                          bottom: 0,
                          child: StreamBuilder<Duration>(
                            stream: player.audio.positionStream,
                            builder: (_, snap) {
                              final total = player.audio.duration?.inMilliseconds ?? 0;
                              final pos = snap.data?.inMilliseconds ?? 0;
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: total == 0 ? 0 : (pos / total).clamp(0, 1).toDouble(),
                                  minHeight: 2.5,
                                  color: Colors.white,
                                  backgroundColor: Colors.white.withValues(alpha: .14),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Opens the full-screen player.
void openPlayer(BuildContext context) => Navigator.of(context, rootNavigator: true).push(_playerRoute());

/// The queue in a bottom sheet, from anywhere.
void showQueueSheet(BuildContext context) => const PlayerPage()._showQueue(context);

/// Desktop player: one wide glass bar with the track, transport, seek and
/// the secondary controls side by side.
class DesktopPlayerBar extends StatelessWidget {
  const DesktopPlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([player, library]),
      builder: (context, _) {
        final t = player.current;
        if (t == null) return const SizedBox.shrink();
        final fav = library.isFavorite(t);
        Color dim(bool on) => on ? kAccent : Colors.white.withValues(alpha: .7);
        return ArtColorBuilder(
          art: t.art,
          seed: _seed(t),
          builder: (context, color) => Glass(
            radius: 28,
            tint: Color.lerp(color, const Color(0xFF2B2429), .5),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: SizedBox(
              height: 68,
              child: Row(
                children: [
                  // Track: click to open the full player.
                  Expanded(
                    flex: 3,
                    child: Pressable(
                      label: 'Открыть плеер: ${t.title}',
                      onTap: () => openPlayer(context),
                      child: Row(
                        children: [
                          Cover(t.art, size: 60, radius: 14, seed: _seed(t)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                                Text(t.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: Colors.white.withValues(alpha: .72), fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: fav ? 'Убрать из избранного' : 'В избранное',
                    onPressed: () => library.toggleFavorite(t),
                    icon: Icon(fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        color: fav ? kAccent : Colors.white),
                  ),
                  // Transport and seek in the middle.
                  Expanded(
                    flex: 5,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                                tooltip: 'Предыдущий',
                                visualDensity: VisualDensity.compact,
                                onPressed: player.previous,
                                icon: const Icon(Icons.skip_previous_rounded, size: 28, color: Colors.white)),
                            const SizedBox(width: 6),
                            Pressable(
                              label: player.playing ? 'Пауза' : 'Играть',
                              onTap: player.toggle,
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: const BoxDecoration(color: kCream, shape: BoxShape.circle),
                                child: Icon(player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    size: 26, color: Colors.black),
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                                tooltip: 'Следующий',
                                visualDensity: VisualDensity.compact,
                                onPressed: player.next,
                                icon: const Icon(Icons.skip_next_rounded, size: 28, color: Colors.white)),
                          ],
                        ),
                        if (t.isRadio)
                          const Text('ПРЯМОЙ ЭФИР',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1))
                        else
                          const _CompactSeek(),
                      ],
                    ),
                  ),
                  // Secondary controls on the right.
                  Expanded(
                    flex: 3,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                            tooltip: 'Перемешать',
                            onPressed: player.toggleShuffle,
                            icon: Icon(Icons.shuffle_rounded, size: 21, color: dim(player.audio.shuffleModeEnabled))),
                        IconButton(
                          tooltip: 'Повтор',
                          onPressed: player.cycleLoop,
                          icon: Icon(
                              player.audio.loopMode == LoopMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                              size: 21,
                              color: dim(player.audio.loopMode != LoopMode.off)),
                        ),
                        IconButton(
                            tooltip: 'Текст песни',
                            onPressed: () => showLyricsSheet(context),
                            icon: const Icon(Icons.lyrics_outlined, size: 21, color: Colors.white70)),
                        IconButton(
                            tooltip: 'Таймер сна',
                            onPressed: () => _showSleepTimer(context),
                            icon: Icon(Icons.bedtime_outlined,
                                size: 21, color: player.sleepAt == null ? Colors.white70 : kAmber)),
                        IconButton(
                            tooltip: 'Очередь',
                            onPressed: () => showQueueSheet(context),
                            icon: const Icon(Icons.queue_music_rounded, size: 22, color: Colors.white70)),
                      ],
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
}

/// One-line seek bar with the times at its ends.
class _CompactSeek extends StatefulWidget {
  const _CompactSeek();

  @override
  State<_CompactSeek> createState() => _CompactSeekState();
}

class _CompactSeekState extends State<_CompactSeek> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    const time = TextStyle(color: Colors.white70, fontSize: 11, fontFeatures: [FontFeature.tabularFigures()]);
    return StreamBuilder<Duration>(
      stream: player.audio.positionStream,
      builder: (context, snap) {
        final total = player.audio.duration ?? Duration(milliseconds: player.current?.durationMs ?? 0);
        final max = total.inMilliseconds.toDouble();
        final pos = (_drag ?? (snap.data?.inMilliseconds ?? 0).toDouble()).clamp(0.0, max <= 0 ? 0.0 : max);
        return Row(
          children: [
            SizedBox(width: 38, child: Text(formatDuration(Duration(milliseconds: pos.round())), style: time, textAlign: TextAlign.right)),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white.withValues(alpha: .22),
                  thumbColor: Colors.white,
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                  thumbShape: RoundSliderThumbShape(enabledThumbRadius: _drag == null ? 4 : 6),
                ),
                child: SizedBox(
                  height: 18,
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
              ),
            ),
            SizedBox(width: 38, child: Text(formatDuration(total), style: time)),
          ],
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
                    child: Center(
                     child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
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
                              if (!t.isRadio)
                                IconButton(
                                    tooltip: 'Текст песни',
                                    onPressed: () => showLyricsSheet(context),
                                    icon: const Icon(Icons.lyrics_outlined, color: Colors.white)),
                              IconButton(
                                  tooltip: 'Таймер сна',
                                  onPressed: () => _showSleepTimer(context),
                                  icon: Icon(Icons.bedtime_outlined,
                                      color: player.sleepAt == null ? Colors.white : kAmber)),
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
                                return GestureDetector(
                                  // Flick the cover sideways to change the track.
                                  onHorizontalDragEnd: (d) {
                                    final v = d.primaryVelocity ?? 0;
                                    if (v.abs() < 300) return;
                                    HapticFeedback.selectionClick();
                                    v < 0 ? player.next() : player.previous();
                                  },
                                  child: AnimatedScale(
                                    scale: player.playing ? 1 : .86,
                                    duration: const Duration(milliseconds: 420),
                                    curve: Curves.easeOutBack,
                                    child: AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 320),
                                      switchInCurve: Curves.easeOutCubic,
                                      transitionBuilder: (child, a) => FadeTransition(
                                        opacity: a,
                                        child: ScaleTransition(scale: Tween(begin: .92, end: 1.0).animate(a), child: child),
                                      ),
                                      child: Cover(t.art,
                                          key: ValueKey(t.id), size: side, radius: 22, seed: _seed(t), shadow: true),
                                    ),
                                  ),
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
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _Pill(_sourceLabel(t)),
                              if (player.sleepAt != null) ...[
                                const SizedBox(width: 6),
                                _Pill('сон через ${_minutesLeft(player.sleepAt!)} мин', icon: Icons.bedtime_rounded),
                              ],
                            ],
                          ),
                          const SizedBox(height: 12),
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
                          Glass(
                            radius: 34,
                            tint: Color.lerp(color, Colors.black, .35),
                            strength: .8,
                            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (t.isRadio) const _LiveBadge() else const _Seek(),
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
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                        ],
                      ),
                      ),
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

int _minutesLeft(DateTime at) {
  final left = at.difference(DateTime.now());
  return left.isNegative ? 0 : (left.inSeconds / 60).ceil();
}

/// Where the sound comes from and in what form, like a quality badge.
String _sourceLabel(Track t) {
  if (t.isRadio) return 'Радио';
  if (t.isPreview) return 'Фрагмент';
  if (t.isLocal) {
    final dot = t.path!.lastIndexOf('.');
    final ext = dot < 0 ? '' : t.path!.substring(dot + 1).toUpperCase();
    final known = const {'MP3', 'FLAC', 'M4A', 'AAC', 'OGG', 'OPUS', 'WAV'}.contains(ext);
    return known ? '$ext · на устройстве' : 'На устройстве';
  }
  if (t.isServer) return 'Мой сервер';
  if (t.isAudius) return 'Audius · поток';
  return 'Поток';
}

void _showSleepTimer(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheet) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: SafeArea(
        child: Glass(
          radius: 30,
          padding: const EdgeInsets.fromLTRB(8, 18, 8, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(14, 0, 14, 2),
                child: Text('Таймер сна', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: Text(
                  player.sleepAt == null
                      ? 'Музыка сама встанет на паузу через выбранное время.'
                      : 'Пауза через ${_minutesLeft(player.sleepAt!)} мин.',
                  style: const TextStyle(color: kMuted),
                ),
              ),
              for (final minutes in const [15, 30, 45, 60])
                ListTile(
                  leading: const Icon(Icons.bedtime_outlined),
                  title: Text('$minutes минут'),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    player.setSleepTimer(Duration(minutes: minutes));
                    Navigator.pop(sheet);
                  },
                ),
              if (player.sleepAt != null)
                ListTile(
                  leading: const Icon(Icons.timer_off_outlined, color: kAmber),
                  title: const Text('Выключить таймер'),
                  onTap: () {
                    player.setSleepTimer(null);
                    Navigator.pop(sheet);
                  },
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {this.icon});
  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: .18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: kAmber), const SizedBox(width: 5)],
          Text(text,
              style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .2)),
        ],
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
        color: kCream,
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


/// Lyrics of the current track in a glass sheet. Timed lyrics follow the
/// song and a tap on a line jumps there.
void showLyricsSheet(BuildContext context, {LyricsService? service}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    isScrollControlled: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: .86,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Glass(
              radius: 36,
              blur: 40,
              child: ListenableBuilder(
                listenable: player,
                builder: (context, _) {
                  final t = player.current;
                  if (t == null) return const SizedBox.shrink();
                  return _LyricsView(key: ValueKey(t.id), track: t, service: service ?? lyrics);
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _LyricsView extends StatefulWidget {
  const _LyricsView({super.key, required this.track, required this.service});
  final Track track;
  final LyricsService service;

  @override
  State<_LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<_LyricsView> {
  late Future<Lyrics?> _load = widget.service.find(widget.track);
  final _keys = <int, GlobalKey>{};
  int _shown = -1;

  void _follow(int line) {
    if (line == _shown || line < 0) return;
    _shown = line;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[line]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            alignment: .38, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
      }
    });
  }

  Widget _message(IconData icon, String title, String body, {VoidCallback? retry}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 44, color: kMuted),
              const SizedBox(height: 14),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(body, textAlign: TextAlign.center, style: const TextStyle(color: kMuted, height: 1.35)),
              if (retry != null) ...[
                const SizedBox(height: 16),
                FilledButton(onPressed: retry, child: const Text('Повторить')),
              ],
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        Center(
          child: Container(
            width: 38,
            height: 5,
            decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(3)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(26, 16, 26, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.4)),
              const SizedBox(height: 2),
              Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kMuted)),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<Lyrics?>(
            future: _load,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator(color: kCream));
              }
              if (snap.hasError) {
                return _message(Icons.cloud_off_rounded, 'Не удалось загрузить текст',
                    'Сервис текстов не ответил. Проверьте интернет.',
                    retry: () => setState(() => _load = widget.service.find(t)));
              }
              final l = snap.data;
              if (l == null || l.isEmpty) {
                return _message(Icons.lyrics_outlined, 'Текста пока нет', 'Для этой песни в открытой базе текстов ничего не нашлось.');
              }
              if (l.instrumental && l.plain.trim().isEmpty && l.synced.isEmpty) {
                return _message(Icons.piano_rounded, 'Инструментал', 'В этой композиции нет слов.');
              }
              if (l.synced.isEmpty) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(26, 6, 26, 40),
                  child: SelectableText(l.plain,
                      style: const TextStyle(fontSize: 19, height: 1.6, fontWeight: FontWeight.w600, color: kInk)),
                );
              }
              return StreamBuilder<Duration>(
                stream: player.audio.positionStream,
                builder: (context, pos) {
                  final now = l.lineAt(pos.data ?? Duration.zero);
                  _follow(now);
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(26, 6, 26, 220),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < l.synced.length; i++)
                          Pressable(
                            key: _keys.putIfAbsent(i, GlobalKey.new),
                            onTap: () => player.audio.seek(l.synced[i].at),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 260),
                                style: TextStyle(
                                  fontFamily: 'Manrope',
                                  fontSize: 24,
                                  height: 1.25,
                                  letterSpacing: -.4,
                                  fontWeight: FontWeight.w800,
                                  color: i == now ? kInk : (i < now ? Colors.white30 : Colors.white54),
                                ),
                                child: Text(l.synced[i].text.isEmpty ? '♪' : l.synced[i].text),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
