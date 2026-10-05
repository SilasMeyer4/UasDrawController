import 'dart:async';

import 'ros_graph.dart';
import 'ros_transport.dart';

/// Raised when a rosbridge service call fails or never answers.
class RosServiceCallException implements Exception {
  RosServiceCallException(this.service, this.reason);

  final String service;
  final String reason;

  @override
  String toString() => 'Service "$service" failed: $reason';
}

/// Raised when a rosbridge action goal fails, is rejected, or never finishes.
class RosActionException implements Exception {
  RosActionException(this.action, this.reason);

  final String action;
  final String reason;

  @override
  String toString() => 'Action "$action" failed: $reason';
}

/// A running action goal handed back by [RosClient.sendActionGoal].
///
/// Feedback is a broadcast stream that stays open for the life of the goal and
/// closes once the result arrives, so a UI can render progress and tear down its
/// listener from the same place.
class RosActionGoal {
  RosActionGoal({
    required this.action,
    required this.id,
    required this.result,
    required this.feedback,
    required this.onCancel,
  });

  final String action;

  /// rosbridge goal id. Unique per client, never shared with service call ids.
  final String id;

  /// Decoded `values` of the terminal `action_result` frame.
  final Future<Map<String, dynamic>> result;

  /// Decoded `values` of each `action_feedback` frame.
  final Stream<Map<String, dynamic>> feedback;

  /// Sends the abort request for this goal.
  final Future<void> Function() onCancel;

  /// Asks the action server to abort. The goal still terminates through
  /// [result], which then reports the cancellation.
  Future<void> cancel() => onCancel();

  @override
  String toString() => 'RosActionGoal($action, $id)';
}

/// Per-goal bookkeeping held by [RosClient] between goal and result.
class _ActionEntry {
  _ActionEntry(this.id, this.action);

  final String id;
  final String action;
  final Completer<Map<String, dynamic>> result =
      Completer<Map<String, dynamic>>();
  final StreamController<Map<String, dynamic>> _feedback =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get feedback => _feedback.stream;

  void closeFeedback() {
    // Do not await: a broadcast controller's close future only completes once
    // the done event is delivered, which never happens under fake async.
    unawaited(_feedback.close());
  }
}

/// Thin client speaking the rosbridge v2 protocol.
///
/// Lifecycle rules that matter when talking to a real rosbridge:
///  * a topic must be **advertised** before it can be published to;
///  * a topic must be **subscribed** before rosbridge forwards it;
///  * introspection is served by the `rosapi` node under `/rosapi/*`, never
///    under `/rosbridge/*`.
class RosClient {
  RosClient(this._transport);

  final RosTransport _transport;

  final StreamController<Map<String, dynamic>> _incoming =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<String> _errors =
      StreamController<String>.broadcast();
  final Map<String, Completer<Map<String, dynamic>>> _pending =
      <String, Completer<Map<String, dynamic>>>{};
  final Map<String, _ActionEntry> _actions = <String, _ActionEntry>{};
  final Map<String, String> _advertised = <String, String>{};
  final Map<String, String> _subscribed = <String, String>{};

  StreamSubscription<dynamic>? _sub;
  StreamSubscription<String>? _errorSub;

  /// Incoming `publish` frames only, decoded JSON.
  Stream<Map<String, dynamic>> get messages => _incoming.stream;

  /// rosbridge `status` frames and transport failures worth showing to a user.
  Stream<String> get errors => _errors.stream;

  bool get isConnected => _transport.isConnected;

  /// Topics currently advertised by this client.
  Map<String, String> get advertised => Map.unmodifiable(_advertised);

  /// Topics currently subscribed by this client.
  Map<String, String> get subscribed => Map.unmodifiable(_subscribed);

  /// Action goals this client has sent and not yet seen a result for.
  Iterable<RosActionGoal> get activeGoals => _actions.values
      .map((entry) => RosActionGoal(
            action: entry.action,
            id: entry.id,
            result: entry.result.future,
            feedback: entry.feedback,
            onCancel: () => cancelAction(entry.id),
          ))
      .toList(growable: false);

  Future<void> connect(String url, {Duration? timeout}) async {
    await _transport.connect(url, timeout: timeout);
    // Cancel first: reconnecting otherwise stacks listeners on the same stream
    // and every message is dispatched N times.
    await _sub?.cancel();
    await _errorSub?.cancel();
    _sub = _transport.stream().listen(
      _onMessage,
      onError: (Object err) => _emitError('rosbridge stream error: $err'),
      cancelOnError: false,
    );
    _errorSub = _transport.errorStream.listen(_emitError);
  }

  Future<void> disconnect() async {
    await _sub?.cancel();
    await _errorSub?.cancel();
    _sub = null;
    _errorSub = null;
    _advertised.clear();
    _subscribed.clear();
    _failPending('connection closed');
    _failActions('connection closed');
    await _transport.disconnect();
  }

  Future<void> dispose() async {
    await disconnect();
    // Do not await: a broadcast controller's close future only completes once
    // the done event is delivered, which never happens under fake async.
    unawaited(_incoming.close());
    unawaited(_errors.close());
  }

  void _onMessage(dynamic event) {
    if (event is! Map<String, dynamic>) return;
    final op = event['op'];

    if (op == 'status') {
      final level = event['level'] as String? ?? 'info';
      final message = event['message'] as String?;
      if (message != null && message.isNotEmpty) {
        _emitError('rosbridge[$level]: $message');
      }
      return;
    }

    if (op == 'action_result' || op == 'action_feedback') {
      _onActionFrame(op, event);
      return;
    }

    if (op != 'service_response') {
      if (!_incoming.isClosed) _incoming.add(event);
      return;
    }

    final id = event['id'] as String?;
    if (id == null) return;
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) return;

    final service = event['service'] as String? ?? '<unknown>';
    if (event['result'] == false) {
      completer.completeError(
        RosServiceCallException(service, 'rosbridge reported failure'),
      );
      return;
    }
    completer.complete(event);
  }

  Future<Map<String, dynamic>> callService(
    String service,
    String type,
    Map<String, dynamic> args, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!isConnected) {
      throw RosServiceCallException(service, 'not connected to rosbridge');
    }
    final id = _nextId();
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    try {
      await _transport.send(<String, dynamic>{
        'op': 'call_service',
        'id': id,
        'service': service,
        'type': type,
        'args': args,
      });
    } on Object catch (err) {
      _pending.remove(id);
      throw RosServiceCallException(service, 'could not send request: $err');
    }
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      throw RosServiceCallException(
        service,
        'no response within ${timeout.inSeconds}s '
        '(service missing on the ROS side, or a name/type mismatch)',
      );
    } finally {
      // Without this the completer leaks for every timed-out call.
      _pending.remove(id);
    }
  }

  /// Routes an `action_result` / `action_feedback` frame to the goal that
  /// carries its id.
  void _onActionFrame(String op, Map<String, dynamic> event) {
    final id = event['id'] as String?;
    if (id == null) return;
    final entry = _actions[id];
    if (entry == null) return;

    final raw = event['values'];
    final values = raw is Map<String, dynamic> ? raw : const <String, dynamic>{};

    if (op == 'action_feedback') {
      if (!entry._feedback.isClosed) entry._feedback.add(values);
      return;
    }

    if (entry.result.isCompleted) return;
    if (event['result'] == false) {
      entry.result.completeError(
        RosActionException(entry.action, 'rosbridge reported failure'),
      );
    } else {
      entry.result.complete(values);
    }
  }

  /// Sends [goal] to the action server [action] and returns immediately, so
  /// the caller can attach a feedback listener while the goal is still running.
  ///
  /// [timeout] bounds how long the goal may take to produce a *result*.
  /// Feedback never times out: long drawing jobs stay silent between updates.
  Future<RosActionGoal> sendActionGoal(
    String action,
    String type,
    Map<String, dynamic> goal, {
    Duration timeout = const Duration(minutes: 30),
  }) async {
    if (!isConnected) {
      throw RosActionException(action, 'not connected to rosbridge');
    }
    final id = _nextActionId();
    final entry = _ActionEntry(id, action);
    _actions[id] = entry;

    try {
      await _transport.send(<String, dynamic>{
        'op': 'action_goal',
        'id': id,
        'action': action,
        'action_type': type,
        'goal': goal,
      });
    } on Object catch (err) {
      _forgetAction(id);
      throw RosActionException(action, 'could not send goal: $err');
    }

    final result = _awaitResult(entry, timeout);
    // Mark the guarded future as handled even if the caller never awaits it:
    // the UI is free to only listen to feedback. Without this a rejected goal
    // surfaces as an unhandled async error and can crash the zone.
    unawaited(result.then<void>((_) {}, onError: (Object _) {}));
    unawaited(result.then<void>(
      (_) => _forgetAction(id),
      onError: (Object _) => _forgetAction(id),
    ));

    return RosActionGoal(
      action: action,
      id: id,
      result: result,
      feedback: entry.feedback,
      onCancel: () => cancelAction(id),
    );
  }

  /// Asks the server behind the goal with id [goalId] to abort it. No-op when
  /// the goal already finished or was never sent by this client.
  Future<void> cancelAction(String goalId) async {
    final entry = _actions[goalId];
    if (entry == null || !isConnected) return;
    await _transport.send(<String, dynamic>{
      'op': 'action_cancel',
      'id': entry.id,
      'action': entry.action,
    });
  }

  Future<Map<String, dynamic>> _awaitResult(
    _ActionEntry entry,
    Duration timeout,
  ) async {
    try {
      return await entry.result.future.timeout(timeout);
    } on TimeoutException {
      throw RosActionException(
        entry.action,
        'no result within ${timeout.inMinutes}min '
        '(action server missing, or a name/type mismatch)',
      );
    }
  }

  void _forgetAction(String id) {
    final entry = _actions.remove(id);
    entry?.closeFeedback();
  }

  /// Advertises [topic] so it can be published to. Repeat calls are no-ops.
  Future<void> advertise(String topic, String type) async {
    if (!isConnected || _advertised.containsKey(topic)) return;
    _advertised[topic] = type;
    await _transport.send(<String, dynamic>{
      'op': 'advertise',
      'topic': topic,
      'type': type,
    });
  }

  Future<void> unadvertise(String topic) async {
    final type = _advertised.remove(topic);
    if (type == null || !isConnected) return;
    await _transport.send(<String, dynamic>{
      'op': 'unadvertise',
      'topic': topic,
      'type': type,
    });
  }

  /// Subscribes to [topic]. Repeat calls are no-ops.
  ///
  /// [rate] limits how often rosbridge forwards the topic, in Hz.
  Future<void> subscribe(
    String topic,
    String type, {
    double? rate,
    int? throttleRate,
    int? queueLength,
  }) async {
    if (!isConnected || _subscribed.containsKey(topic)) return;
    _subscribed[topic] = type;
    await _transport.send(<String, dynamic>{
      'op': 'subscribe',
      'topic': topic,
      'type': type,
      'rate': ?rate,
      'throttle_rate': ?throttleRate,
      'queue_length': ?queueLength,
    });
  }

  Future<void> unsubscribe(String topic) async {
    final type = _subscribed.remove(topic);
    if (type == null || !isConnected) return;
    await _transport.send(<String, dynamic>{
      'op': 'unsubscribe',
      'topic': topic,
      'type': type,
    });
  }

  /// Drops every subscription made by this client.
  Future<void> unsubscribeAll() async {
    final topics = _subscribed.keys.toList();
    for (final topic in topics) {
      await unsubscribe(topic);
    }
  }

  /// Publishes [msg], advertising [type] first when needed.
  ///
  /// rosbridge silently drops a `publish` for a topic that was never
  /// advertised, so the advertise is done implicitly here.
  Future<void> publish(
    String topic,
    Map<String, dynamic> msg, {
    String? type,
  }) async {
    if (!isConnected) return;
    if (type != null && !_advertised.containsKey(topic)) {
      await advertise(topic, type);
    }
    await _transport.send(<String, dynamic>{
      'op': 'publish',
      'topic': topic,
      'msg': msg,
    });
  }

  /// Asks rosbridge for the current ROS graph.
  ///
  /// Note the `/rosapi/*` service names: those are the real ones. There is no
  /// `/rosbridge/topics`, `/rosbridge/services` or `/rosbridge/nodes`.
  Future<RosGraph> fetchGraph() async {
    final topics = await callService(
      '/rosapi/topics',
      'rosapi_msgs/srv/Topics',
      const <String, dynamic>{},
    );
    final services = await callService(
      '/rosapi/services',
      'rosapi_msgs/srv/Services',
      const <String, dynamic>{},
    );
    final nodes = await callService(
      '/rosapi/nodes',
      'rosapi_msgs/srv/Nodes',
      const <String, dynamic>{},
    );

    return RosGraph(
      topics: _pairs(topics, 'topics'),
      services: _pairs(services, 'services'),
      nodes: _strings(nodes, 'nodes'),
    );
  }

  /// Zips rosapi's parallel `topics`/`types` (or `services`/`types`) arrays
  /// into a map. rosapi returns one type entry per name, possibly empty.
  Map<String, String> _pairs(Map<String, dynamic> response, String key) {
    final values = response['values'];
    if (values is! Map<String, dynamic>) return const {};
    final names = (values[key] as List?)?.whereType<String>().toList() ?? const [];
    final types = (values['types'] as List?)?.cast<Object?>() ?? const [];
    final result = <String, String>{};
    for (var i = 0; i < names.length; i++) {
      final type = i < types.length ? types[i] : null;
      result[names[i]] = type is String ? type : '';
    }
    return result;
  }

  List<String> _strings(Map<String, dynamic> response, String key) {
    final values = response['values'];
    if (values is! Map<String, dynamic>) return const [];
    return (values[key] as List?)?.whereType<String>().toList() ?? const [];
  }

  void _failPending(String reason) {
    if (_pending.isEmpty) return;
    final pending = Map<String, Completer<Map<String, dynamic>>>.from(_pending);
    _pending.clear();
    for (final completer in pending.values) {
      if (completer.isCompleted) continue;
      // The caller may still be suspended on `_transport.send` and therefore not
      // listening yet; without this the error is reported as unhandled.
      completer.future.then<void>((_) {}, onError: (Object _) {});
      completer.completeError(RosServiceCallException('<pending>', reason));
    }
  }

  void _failActions(String reason) {
    if (_actions.isEmpty) return;
    final entries = Map<String, _ActionEntry>.from(_actions);
    _actions.clear();
    for (final entry in entries.values) {
      entry.closeFeedback();
      if (entry.result.isCompleted) continue;
      entry.result.completeError(RosActionException(entry.action, reason));
    }
  }

  void _emitError(String message) {
    if (_errors.isClosed) return;
    _errors.add(message);
  }

  int _seq = 0;
  String _nextId() {
    _seq++;
    return 'call_service:$_seq';
  }

  int _actionSeq = 0;
  String _nextActionId() {
    _actionSeq++;
    return 'action_goal:$_actionSeq';
  }
}