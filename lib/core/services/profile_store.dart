import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/connection_profile.dart';

/// Persists connection profiles (endpoint + ROS bindings) to a JSON file in
/// the platform support directory.
class ProfileStore {
  static const fileName = 'profiles.json';

  Future<File> _getFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$fileName');
  }

  Future<List<ConnectionProfile>> loadProfiles() async {
    try {
      final f = await _getFile();
      if (!await f.exists()) return defaults;
      final text = await f.readAsString();
      final decoded = jsonDecode(text);
      if (decoded is! List) return defaults;
      final profiles = decoded
          .whereType<Map<String, dynamic>>()
          .map(ConnectionProfile.fromJson)
          .toList();
      return profiles.isEmpty ? defaults : profiles;
    } on Object {
      // A corrupt or unreadable file must not stop the app from starting.
      return defaults;
    }
  }

  Future<void> saveProfiles(List<ConnectionProfile> profiles) async {
    final f = await _getFile();
    await f.writeAsString(
      jsonEncode(profiles.map((e) => e.toJson()).toList()),
      flush: true,
    );
  }

  List<ConnectionProfile> get defaults => <ConnectionProfile>[
        ConnectionProfile(
          name: 'Mock (Simulation)',
          wsUrl: 'mock://local',
          isMock: true,
        ),
        ConnectionProfile(
          name: 'ROS 2 host (rosbridge)',
          wsUrl: 'ws://localhost:9090',
        ),
        ConnectionProfile(
          name: 'Drone on LAN (rosbridge)',
          wsUrl: 'ws://192.168.1.10:9090',
        ),
      ];
}