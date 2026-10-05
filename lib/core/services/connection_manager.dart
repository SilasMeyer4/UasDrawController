import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/bindings.dart';
import '../models/connection_profile.dart';
import '../rosbridge/mock_transport.dart';
import '../rosbridge/ros_client.dart';
import '../rosbridge/ros_graph.dart';
import '../rosbridge/ros_transport.dart';
import '../rosbridge/websocket_transport.dart';

/// Owns the connection lifecycle and exposes the ROS graph plus per-action
/// capability discovery to the UI.
class ConnectionManager extends ChangeNotifier {
  ConnectionProfile? _profile;
  RosClient? _client;
  RosGraph _graph = const RosGraph();
  final Set<LogicalAction> _available = <LogicalAction>{};
  bool _connecting = false;
  String? _error;
  String? _graphError;
  String? _notice;
  StreamSubscription<String>? _messageErrors;

  ConnectionProfile? get profile => _profile;
  RosGraph get graph => _graph;
  bool get isConnected => _client?.isConnected ?? false;
  bool get isConnecting => _connecting;
  String? get error => _error;
  String? get graphError => _graphError;
  String? get notice => _notice;

  /// Actions whose ROS target actually exists in the graph (or that cannot be
  /// discovered, in which case every action is assumed available).
  bool isAvailable(LogicalAction action) =>
      _graph.isEmpty || _available.contains(action);

  Set<LogicalAction> get available => Set.unmodifiable(_available);

  RosClient? get client => _client;

  Future<void> connect(ConnectionProfile profile) async {
    _connecting = true;
    _error = null;
    _graphError = null;
    _notice = profile.isMock
        ? 'Using the built-in simulation: no ROS system is contacted.'
        : null;
    notifyListeners();

    await _teardown();

    final RosTransport transport = profile.isMock
        ? MockTransport()
        : WebSocketTransport();
    final client = RosClient(transport);
    _client = client;
    _profile = profile;

    try {
      if (profile.isMock) {
        await client.connect('mock://local');
      } else {
        await client.connect(
          profile.wsUrl,
          timeout: const Duration(seconds: 5),
        );
      }
      _messageErrors = client.errors.listen((message) {
        _notice = message;
        notifyListeners();
      });
      await refreshGraph();
    } on Object catch (err) {
      _error = err.toString();
      await _teardown();
      _profile = profile;
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

  /// Re-reads the ROS graph. Introspection is served by the `rosapi` node, so
  /// a failure here means rosbridge is up but rosapi is missing.
  Future<void> refreshGraph() async {
    final client = _client;
    if (client == null || !client.isConnected) return;
    try {
      _graph = await client.fetchGraph();
      _graphError = null;
      _discoverCapabilities();
    } on Object catch (err) {
      _graph = const RosGraph();
      _available.clear();
      _graphError = err.toString();
    }
    notifyListeners();
  }

  void _discoverCapabilities() {
    _available.clear();
    final bindings = _profile?.bindings;
    if (bindings == null) return;
    for (final action in LogicalAction.values) {
      final binding = bindings.get(action);
      if (binding == null || binding.name.isEmpty) continue;
      // Action servers are invisible to rosapi: `ros2 service list` hides the
      // hidden `_action/*` services they create, so an action binding is
      // assumed present and only fails when a goal is actually sent.
      if (binding.isAction) {
        _available.add(action);
        continue;
      }
      final present = binding.isService
          ? _graph.hasService(binding.name)
          : _graph.hasTopic(binding.name);
      if (present) _available.add(action);
    }
  }

  /// Drops every subscription and closes the socket, but keeps the profile so
  /// the UI can show what it was connected to.
  Future<void> disconnect() async {
    await _teardown();
    notifyListeners();
  }

  Future<void> _teardown() async {
    await _messageErrors?.cancel();
    _messageErrors = null;
    final client = _client;
    _client = null;
    _graph = const RosGraph();
    _available.clear();
    _notice = null;
    if (client != null) {
      await client.dispose();
    }
  }

  @override
  void dispose() {
    unawaited(_teardown());
    super.dispose();
  }
}