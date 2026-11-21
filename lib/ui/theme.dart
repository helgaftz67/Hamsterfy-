import 'dart:io';

import 'package:flutter/material.dart';

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
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kBg,
    appBarTheme: const AppBarTheme(backgroundColor: kBg, surfaceTintColor: Colors.transparent, centerTitle: false),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: kSurface,
      indicatorColor: kAccent.withValues(alpha: .22),
      height: 64,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
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
  const Cover(this.art, {super.key, this.size = 48, this.radius = 8, this.seed = ''});
  final String? art;
  final double size;
  final double radius;
  final String seed;

  @override
  Widget build(BuildContext context) {
    final hue = (seed.hashCode % 360).abs().toDouble();
    final placeholder = Container(
      width: size,
      height: size,
      color: HSLColor.fromAHSL(1, hue, .35, .28).toColor(),
      child: Icon(Icons.music_note, size: size * .45, color: Colors.white70),
    );
    final a = art;
    Widget child = placeholder;
    if (a != null) {
      child = a.startsWith('http')
          ? Image.network(a, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder)
          : Image.file(File(a), width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder);
    }
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: child);
  }
}

/// One row in any track list: cover, title, artist, state and a menu.
class TrackTile extends StatelessWidget {
  const TrackTile(this.track, {super.key, required this.onTap});
  final Track track;
  final VoidCallback onTap;

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
          leading: Cover(t.art, seed: t.album + t.artist),
          title: Text(t.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: isCurrent ? kAccent : kInk, fontWeight: FontWeight.w500)),
          subtitle: Row(
            children: [
              if (t.isLocal) ...[
                const Icon(Icons.download_done, size: 14, color: kAmber),
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
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'fav', child: Text(fav ? 'Убрать из избранного' : 'В избранное')),
                  if (!t.isLocal && t.url != null && progress == null)
                    const PopupMenuItem(value: 'download', child: Text('Скачать')),
                  if (t.isLocal) const PopupMenuItem(value: 'remove', child: Text('Удалить с устройства')),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
