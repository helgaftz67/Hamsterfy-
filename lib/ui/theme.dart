import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../models.dart';

const kBg = Color(0xFF121019);
const kSurface = Color(0xFF1C1926);
const kSunken = Color(0xFF262233);
const kAccent = Color(0xFFA796FF);
const kAmber = Color(0xFFFFB938);
const kMuted = Color(0xFFA39FBC);
const kInk = Color(0xFFECEAF5);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: kAccent, brightness: Brightness.dark).copyWith(
    surface: kBg,
    primary: kAccent,
    onPrimary: const Color(0xFF15121F),
    secondary: kAmber,
    surfaceContainer: kSurface,
    surfaceContainerHigh: kSunken,
    onSurface: kInk,
    onSurfaceVariant: kMuted,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'Manrope');
  return base.copyWith(
    scaffoldBackgroundColor: kBg,
    textTheme: base.textTheme.apply(bodyColor: kInk, displayColor: kInk),
    appBarTheme: const AppBarTheme(
      backgroundColor: kBg,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: 'Manrope', fontSize: 20, fontWeight: FontWeight.w700, color: kInk),
    ),
    // iOS-style slide between screens on every platform.
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: kBg,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      height: 60,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontFamily: 'Manrope',
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: states.contains(WidgetState.selected) ? kInk : kMuted,
          )),
      iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(size: 26, color: states.contains(WidgetState.selected) ? kInk : kMuted)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kInk,
        foregroundColor: kBg,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        textStyle: const TextStyle(fontFamily: 'Manrope', fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kInk,
        side: BorderSide(color: kInk.withValues(alpha: .28)),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        textStyle: const TextStyle(fontFamily: 'Manrope', fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: kSurface,
      selectedColor: kInk,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      showCheckmark: false,
      labelStyle: const TextStyle(fontFamily: 'Manrope', fontWeight: FontWeight.w600, fontSize: 13.5),
      secondaryLabelStyle: const TextStyle(fontFamily: 'Manrope', fontWeight: FontWeight.w700, color: kBg),
    ),
    listTileTheme: const ListTileThemeData(
      subtitleTextStyle: TextStyle(fontFamily: 'Manrope', color: kMuted, fontSize: 13),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: kInk,
      contentTextStyle: const TextStyle(fontFamily: 'Manrope', color: kBg, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

/// Large screen title used at the top of every tab.
const kTitle = TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1.1);

ImageProvider? artProvider(String? art) {
  if (art == null) return null;
  return art.startsWith('http') ? NetworkImage(art) : FileImage(File(art)) as ImageProvider;
}

Color seedColor(String seed) => HSLColor.fromAHSL(1, (seed.hashCode % 360).abs().toDouble(), .42, .30).toColor();

final Map<String, Color> _artColors = {};

/// A deep colour taken from the artwork, for backgrounds behind white text.
/// Falls back to a colour derived from [seed] when there is no artwork.
Future<Color> artColor(String? art, String seed) async {
  final provider = artProvider(art);
  if (provider == null) return seedColor(seed);
  final known = _artColors[art!];
  if (known != null) return known;
  try {
    final scheme = await ColorScheme.fromImageProvider(provider: provider, brightness: Brightness.dark);
    final hsl = HSLColor.fromColor(scheme.primary);
    final color = hsl.withSaturation((hsl.saturation * .9).clamp(.25, .7)).withLightness(.30).toColor();
    return _artColors[art] = color;
  } catch (_) {
    return seedColor(seed);
  }
}

/// Rebuilds with the artwork colour, animating from the seed colour.
class ArtColorBuilder extends StatelessWidget {
  const ArtColorBuilder({super.key, required this.art, required this.seed, required this.builder});
  final String? art;
  final String seed;
  final Widget Function(BuildContext, Color) builder;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Color>(
      key: ValueKey('$art|$seed'),
      future: artColor(art, seed),
      initialData: _artColors[art] ?? seedColor(seed),
      builder: (context, snap) => TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: snap.data),
        duration: const Duration(milliseconds: 500),
        builder: (context, color, _) => builder(context, color ?? snap.data!),
      ),
    );
  }
}

String formatDuration(Duration d) {
  final m = d.inMinutes, s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

void toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Square cover with a coloured placeholder when a track has no artwork.
class Cover extends StatelessWidget {
  const Cover(this.art, {super.key, this.size = 48, this.radius = 8, this.seed = '', this.shadow = false});
  final String? art;
  final double size;
  final double radius;
  final String seed;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final base = seedColor(seed);
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [HSLColor.fromColor(base).withLightness(.42).toColor(), HSLColor.fromColor(base).withLightness(.20).toColor()],
        ),
      ),
      child: Icon(Icons.music_note_rounded, size: size * .42, color: Colors.white.withValues(alpha: .75)),
    );
    final provider = artProvider(art);
    final image = provider == null
        ? placeholder
        : Image(
            image: provider,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => placeholder,
            frameBuilder: (_, child, frame, sync) => sync
                ? child
                : Stack(children: [
                    placeholder,
                    AnimatedOpacity(
                        opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 250), child: child),
                  ]),
          );
    final clipped = ClipRRect(borderRadius: BorderRadius.circular(radius), child: image);
    if (!shadow) return clipped;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .45), blurRadius: size * .16, offset: Offset(0, size * .07))],
      ),
      child: clipped,
    );
  }
}

/// One row in any track list: cover, title, artist, state and a menu.
class TrackTile extends StatelessWidget {
  const TrackTile(this.track, {super.key, required this.onTap, this.playlist});
  final Track track;
  final VoidCallback onTap;

  /// Set when the row is shown inside a playlist, to offer removal from it.
  final String? playlist;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([library, player]),
      builder: (context, _) {
        final t = library.tracks[track.id] ?? track;
        final isCurrent = player.current?.id == t.id;
        final progress = library.downloading[t.id];
        final fav = library.isFavorite(t);
        return ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.only(left: 16, right: 4),
          leading: Cover(t.art, size: 50, radius: 6, seed: t.album + t.artist),
          title: Text(t.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: isCurrent ? kAccent : kInk, fontWeight: FontWeight.w600, fontSize: 15.5)),
          subtitle: Row(
            children: [
              if (t.isRadio) ...[
                const Icon(Icons.sensors, size: 14, color: kAmber),
                const SizedBox(width: 4),
              ] else if (t.isLocal) ...[
                Icon(t.auto ? Icons.cached : Icons.download_done, size: 14, color: kAmber),
                const SizedBox(width: 4),
              ],
              Expanded(child: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (progress != null)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(value: progress == 0 ? null : progress, strokeWidth: 2.5),
                )
              else if (fav)
                const Icon(Icons.favorite, size: 18, color: kAccent),
              PopupMenuButton<String>(
                tooltip: 'Действия с треком',
                onSelected: (v) async {
                  switch (v) {
                    case 'fav':
                      HapticFeedback.lightImpact();
                      library.toggleFavorite(t);
                    case 'download':
                      try {
                        await library.download(t);
                        if (context.mounted) toast(context, 'Трек скачан');
                      } catch (_) {
                        if (context.mounted) toast(context, 'Не удалось скачать. Проверьте интернет и попробуйте снова.');
                      }
                    case 'remove':
                      await library.remove(t);
                    case 'forget':
                      await library.forget(t);
                      if (context.mounted) {
                        toast(context, t.isDevice ? 'Убрано из медиатеки. Файл остался на телефоне' : 'Убрано из медиатеки');
                      }
                    case 'pin':
                      library.pin(t);
                      if (context.mounted) toast(context, 'Трек сохранён и не будет удалён при очистке кэша');
                    case 'playlist':
                      if (context.mounted) await addToPlaylistDialog(context, t);
                    case 'unlist':
                      library.removeFromPlaylist(playlist!, t);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'fav', child: Text(fav ? 'Убрать из избранного' : 'В избранное')),
                  const PopupMenuItem(value: 'playlist', child: Text('Добавить в плейлист')),
                  if (playlist != null) const PopupMenuItem(value: 'unlist', child: Text('Убрать из плейлиста')),
                  if (!t.isLocal && !t.isRadio && t.url != null && progress == null)
                    const PopupMenuItem(value: 'download', child: Text('Скачать')),
                  if (t.isLocal && t.auto) const PopupMenuItem(value: 'pin', child: Text('Сохранить навсегда')),
                  if (t.isLocal && t.url != null)
                    const PopupMenuItem(value: 'remove', child: Text('Удалить скачанный файл')),
                  if (library.tracks.containsKey(t.id))
                    const PopupMenuItem(value: 'forget', child: Text('Убрать из медиатеки')),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Asks for a name and creates a playlist. Returns the name, or null.
Future<String?> newPlaylistDialog(BuildContext context) {
  final name = TextEditingController();
  String? error;
  return showDialog<String>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, setState) {
        void submit() {
          final clean = name.text.trim();
          if (clean.isEmpty) {
            setState(() => error = 'Введите название');
          } else if (!library.createPlaylist(clean)) {
            setState(() => error = 'Такой плейлист уже есть');
          } else {
            Navigator.pop(d, clean);
          }
        }

        return AlertDialog(
          title: const Text('Новый плейлист'),
          content: TextField(
            controller: name,
            autofocus: true,
            maxLength: 40,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: 'Название', errorText: error, border: const OutlineInputBorder()),
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Отмена')),
            FilledButton(onPressed: submit, child: const Text('Создать')),
          ],
        );
      },
    ),
  );
}

/// Lets the user pick a playlist for [t], or create a new one.
Future<void> addToPlaylistDialog(BuildContext context, Track t) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: kSurface,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            leading: const Icon(Icons.add, color: kAccent),
            title: const Text('Новый плейлист'),
            onTap: () => Navigator.pop(sheet, '\u0000new'),
          ),
          for (final name in library.playlistNames)
            ListTile(
              leading: const Icon(Icons.queue_music),
              title: Text(name),
              subtitle: Text('Треков: ${library.playlists[name]!.length}'),
              onTap: () => Navigator.pop(sheet, name),
            ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  final name = choice == '\u0000new' ? await newPlaylistDialog(context) : choice;
  if (name == null || !context.mounted) return;
  toast(context, library.addToPlaylist(name, t) ? 'Добавлено в «$name»' : 'Этот трек уже есть в «$name»');
}
