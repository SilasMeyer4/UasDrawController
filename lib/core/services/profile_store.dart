import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/connection_profile.dart';

/// Persists connection profiles to disk (JSON).
class ProfileStore {
  static const _fileName = 'profiles.json';

  Future<File> _getFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<List<ConnectionProfile>> loadProfiles() async {
    try {
      final f = await _getFile();
      if (!await f.exists()) return _defaults();
      final text = await f.readAsString();
      final list = jsonDecode(text) as List<dynamic>;
      return list.map((e) => ConnectionProfile.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return _defaults();
    }
  }

  Future<void> saveProfiles(List<ConnectionProfile> profiles) async {
    final f = await _getFile();
    await f.writeAsString(jsonEncode(profiles.map((e) => e.toJson()).toList()));
  }

  List<ConnectionProfile> _defaults() {
    return [
      ConnectionProfile(name: 'Mock (Simulation)', wsUrl: 'mock://local', isMock: true),
      ConnectionProfile(name: 'SITL / Workstation', wsUrl: 'ws://localhost:9090'),
      ConnectionProfile(name: 'Drone (LAN)', wsUrl: 'ws://192.168.1.10:9090'),
    ];
  }
}
