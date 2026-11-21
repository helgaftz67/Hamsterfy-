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

  /// Cover: a local file path or an http(s) address.
  String? art;
  int durationMs;
  final int addedAt;

  bool get isLocal => path != null;

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
