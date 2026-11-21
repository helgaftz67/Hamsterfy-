/// A single playable track: either a file stored on the device, a stream
/// from the open catalog, or both (a downloaded catalog track).
class Track {
  Track({
    required this.id,
    required this.title,
    required this.artist,
    this.album = '',
    this.url,
    this.path,
    this.art,
    this.durationMs = 0,
    this.auto = false,
    this.size = 0,
    this.link,
    this.canSave = true,
    int? addedAt,
  }) : addedAt = addedAt ?? DateTime.now().millisecondsSinceEpoch;

  final String id;
  final String title;
  final String artist;
  final String album;

  /// Remote stream address, if the track comes from the catalog.
  final String? url;

  /// Local file path, if the track is on the device.
  String? path;

  /// Store page where the full track can be played, for search previews.
  final String? link;

  /// Cover: a local file path or an http(s) address.
  String? art;
  int durationMs;
  final int addedAt;

  /// True when the file was saved automatically by the listening cache and
  /// may be removed again to free space. False for explicit downloads.
  bool auto;

  /// Size of the saved file in bytes, 0 when unknown.
  int size;

  bool get isLocal => path != null;

  /// A live internet radio station: an endless stream that cannot be saved.
  bool get isRadio => id.startsWith('radio:');

  /// Whether the app may keep an offline copy (cache or download).
  final bool canSave;

  /// A track streamed in full from Audius.
  bool get isAudius => id.startsWith('au:');

  /// Listed for information only: there is nothing the app may play.
  bool get isUnavailable => path == null && url == null;

  /// A song found by the world search: only its 30-second preview plays.
  bool get isPreview => id.startsWith('it:');

  /// A file found on the phone by the system scan. The app never deletes it.
  bool get isDevice => id.startsWith('dev:');

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'url': url,
        'path': path,
        'art': art,
        'durationMs': durationMs,
        'addedAt': addedAt,
        'auto': auto,
        'size': size,
        'link': link,
        'canSave': canSave,
      };

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        artist: j['artist'] as String? ?? '',
        album: j['album'] as String? ?? '',
        url: j['url'] as String?,
        path: j['path'] as String?,
        art: j['art'] as String?,
        durationMs: j['durationMs'] as int? ?? 0,
        addedAt: j['addedAt'] as int?,
        auto: j['auto'] as bool? ?? false,
        size: j['size'] as int? ?? 0,
        link: j['link'] as String?,
        canSave: j['canSave'] as bool? ?? true,
      );
}

/// A release in the open catalog.
class Album {
  Album({required this.id, required this.title, required this.artist});
  final String id;
  final String title;
  final String artist;
  String get art => 'https://archive.org/services/img/$id';
}
