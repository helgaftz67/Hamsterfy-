import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'library.dart';
import 'player.dart';

/// A local account. Each one has its own collection, favourites, history
/// and downloads. Nothing leaves the device.
class Profile {
  Profile({required this.id, required this.name, this.pinHash, this.avatar});
  final String id;
  final String name;

  /// SHA-256 of the id and PIN, or null when the profile has no PIN.
  final String? pinHash;

  /// Path of the profile picture inside the app's storage, if one is set.
  String? avatar;

  bool get hasPin => pinHash != null;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'pinHash': pinHash, 'avatar': avatar};

  factory Profile.fromJson(Map<String, dynamic> j) =>
      Profile(id: j['id'] as String, name: j['name'] as String, pinHash: j['pinHash'] as String?, avatar: j['avatar'] as String?);
}

class Profiles extends ChangeNotifier {
  Profiles(this.library, this.player);
  final Library library;
  final Player player;

  final List<Profile> list = [];
  Profile? current;
  late Directory _dir;

  File get _file => File('${_dir.path}/profiles.json');

  static String hashPin(String id, String pin) => sha256.convert(utf8.encode('$id:$pin')).toString();

  /// Id of the account that stays signed in between launches.
  String? _signedIn;

  Future<void> load() async {
    _dir = await getApplicationDocumentsDirectory();
    if (await _file.exists()) {
      try {
        restore(jsonDecode(await _file.readAsString()));
      } catch (_) {}
    }
    // Whoever was signed in stays signed in until they sign out themselves:
    // the PIN is asked only when choosing an account on the start screen.
    final remembered = list.where((p) => p.id == _signedIn).firstOrNull;
    if (remembered != null) {
      await select(remembered);
    } else if (list.length == 1 && !list.first.hasPin) {
      await select(list.first);
    }
  }

  /// Reads the stored accounts. Older versions stored a bare list.
  @visibleForTesting
  void restore(dynamic raw) {
    final rows = raw is List ? raw : (raw['profiles'] as List? ?? const []);
    list.addAll(rows.map((p) => Profile.fromJson(p as Map<String, dynamic>)));
    if (raw is Map) _signedIn = raw['signedIn'] as String?;
  }

  @visibleForTesting
  Map<String, dynamic> snapshot() => {'profiles': [for (final p in list) p.toJson()], 'signedIn': _signedIn};

  @visibleForTesting
  String? get signedInId => _signedIn;

  Future<void> _save() => _file.writeAsString(jsonEncode(snapshot()));

  /// Creates a profile and signs into it. The very first profile takes over
  /// any collection made before profiles existed.
  Future<Profile> create(String name, {String? pin}) async {
    final id = list.isEmpty ? 'main' : 'p${DateTime.now().millisecondsSinceEpoch}';
    final profile = Profile(
      id: id,
      name: name.trim(),
      pinHash: (pin == null || pin.isEmpty) ? null : hashPin(id, pin),
    );
    list.add(profile);
    await _save();
    await select(profile);
    return profile;
  }

  bool checkPin(Profile p, String pin) => !p.hasPin || p.pinHash == hashPin(p.id, pin);

  Future<void> select(Profile p) async {
    await player.reset();
    await library.open(p.id);
    current = p;
    _signedIn = p.id;
    await _save();
    notifyListeners();
  }

  /// Lets the user pick a picture and makes it the avatar of [p].
  /// Returns false when nothing was picked.
  Future<bool> pickAvatar(Profile p) async {
    final picked = await FilePicker.pickFile(type: FileType.image);
    if (picked == null) return false;
    // A new file name each time, so the old picture is not served from cache.
    final ext = (picked.extension ?? 'jpg').toLowerCase();
    final dest = File('${_dir.path}/avatar_${p.id}_${DateTime.now().millisecondsSinceEpoch}.$ext');
    final sink = dest.openWrite();
    await sink.addStream(picked.xFile.openRead());
    await sink.close();
    await _dropAvatar(p);
    p.avatar = dest.path;
    await _save();
    notifyListeners();
    return true;
  }

  Future<void> removeAvatar(Profile p) async {
    await _dropAvatar(p);
    p.avatar = null;
    await _save();
    notifyListeners();
  }

  Future<void> _dropAvatar(Profile p) async {
    final old = p.avatar;
    if (old != null && await File(old).exists()) await File(old).delete();
  }

  /// Returns to the "who is listening" screen.
  Future<void> signOut() async {
    await player.reset();
    current = null;
    _signedIn = null;
    await _save();
    notifyListeners();
  }

  /// Deletes a profile with its collection and downloaded files.
  Future<void> delete(Profile p) async {
    if (current?.id == p.id) await signOut();
    list.removeWhere((x) => x.id == p.id);
    await _dropAvatar(p);
    await _save();
    final lib = File('${_dir.path}/${Library.libraryFileName(p.id)}');
    final music = Directory('${_dir.path}/${Library.musicDirName(p.id)}');
    if (await lib.exists()) await lib.delete();
    if (await music.exists()) await music.delete(recursive: true);
    notifyListeners();
  }
}
