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
          leading: Cover(t.art, seed: t.album + t.artist),
          title: Text(t.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: isCurrent ? kAccent : kInk, fontWeight: FontWeight.w500)),
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
                  if (t.isLocal && !t.isDevice)
                    const PopupMenuItem(value: 'remove', child: Text('Удалить с устройства')),
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
