import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/connection_profile.dart';
import '../rosbridge/ros_client.dart';
import '../rosbridge/ros_transport.dart';
import '../rosbridge/websocket_transport.dart';
import '../rosbridge/mock_transport.dart';
import '../rosbridge/ros_graph.dart';

/// Manages connection lifecycle and exposes the current graph/state.
class ConnectionManager extends ChangeNotifier {
  ConnectionProfile? _profile;
  RosClient? _client;
  RosGraph _graph = RosGraph();
  bool _connecting = false;
  String? _error;

  ConnectionProfile? get profile => _profile;
  RosGraph get graph => _graph;
  bool get isConnected => _client?.isConnected ?? false;
  bool get isConnecting => _connecting;
  String? get error => _error;

  Future<void> connect(ConnectionProfile profile) async {
    _connecting = true;
    _error = null;
    notifyListeners();

    try {
      await disconnect();

      final transport = profile.isMock
          ? MockTransport()
          : WebSocketTransport() as RosTransport;
      final client = RosClient(transport);
      _client = client;
      _profile = profile;

      if (profile.isMock) {
        await client.connect('mock://local');
      } else {
        await client.connect(profile.wsUrl, timeout: const Duration(seconds: 5));
      }

      // Fetch graph
      try {
        _graph = await client.fetchGraph();
      } catch (_) {
        _graph = RosGraph();
      }
      notifyListeners();
    } catch (e) {
      _error = e.toString();
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    await _client?.disconnect();
    _client = null;
    _graph = RosGraph();
    notifyListeners();
  }

  RosClient? get client => _client;
}
