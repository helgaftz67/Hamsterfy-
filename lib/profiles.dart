import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'library.dart';
import 'player.dart';

/// A local account. Each one has its own collection, favourites, history
/// and downloads. Nothing leaves the device.
class Profile {
  Profile({required this.id, required this.name, this.pinHash});
  final String id;
  final String name;

  /// SHA-256 of the id and PIN, or null when the profile has no PIN.
  final String? pinHash;

  bool get hasPin => pinHash != null;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'pinHash': pinHash};

  factory Profile.fromJson(Map<String, dynamic> j) =>
      Profile(id: j['id'] as String, name: j['name'] as String, pinHash: j['pinHash'] as String?);
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

  Future<void> load() async {
    _dir = await getApplicationDocumentsDirectory();
    if (await _file.exists()) {
      try {
        final raw = jsonDecode(await _file.readAsString()) as List;
        list.addAll(raw.map((p) => Profile.fromJson(p as Map<String, dynamic>)));
      } catch (_) {}
    }
    // A single profile without a PIN opens straight away.
    if (list.length == 1 && !list.first.hasPin) await select(list.first);
  }

  Future<void> _save() => _file.writeAsString(jsonEncode([for (final p in list) p.toJson()]));

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
    notifyListeners();
  }

  /// Returns to the "who is listening" screen.
  Future<void> signOut() async {
    await player.reset();
    current = null;
    notifyListeners();
  }

  /// Deletes a profile with its collection and downloaded files.
  Future<void> delete(Profile p) async {
    if (current?.id == p.id) await signOut();
    list.removeWhere((x) => x.id == p.id);
    await _save();
    final lib = File('${_dir.path}/${Library.libraryFileName(p.id)}');
    final music = Directory('${_dir.path}/${Library.musicDirName(p.id)}');
    if (await lib.exists()) await lib.delete();
    if (await music.exists()) await music.delete(recursive: true);
    notifyListeners();
  }
}
