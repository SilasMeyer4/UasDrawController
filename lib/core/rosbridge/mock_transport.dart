import 'dart:async';

import 'ros_transport.dart';

/// Offline simulation backend that mimics rosbridge closely enough to be
/// useful as a test double and as the "Mock (Simulation)" connection profile.
///
/// Fidelity rules deliberately mirror `rosbridge_suite`:
///  * introspection lives under `/rosapi/*`;
///  * `publish` on a topic that was never advertised is dropped;
///  * topic messages are only forwarded to topics the client subscribed to;
///  * frames the client sends are never echoed back as incoming traffic.
class MockTransport implements RosTransport {
  MockTransport();

  final StreamController<dynamic> _incoming =
      StreamController<dynamic>.broadcast();
  final StreamController<String> _errors =
      StreamController<String>.broadcast();
  final Set<String> _subscribed = <String>{};
  final Set<String> _advertised = <String>{};
  /// Goals that were asked to stop and whose next feedback tick must be turned
  /// into a cancelled result instead.
  final Set<String> _cancelledGoals = <String>{};
  bool _connected = false;
  Timer? _batteryTimer;
  Timer? _dataTimer;
  Timer? _bufferTimer;
  Timer? _rosoutTimer;

  /// Every frame the client sent, in order. Useful in tests.
  final List<Map<String, dynamic>> sentOps = <Map<String, dynamic>>[];

  @override
  bool get isConnected => _connected;

  @override
  Stream<dynamic> stream() => _incoming.stream;

  @override
  Stream<String> get errorStream => _errors.stream;

  @override
  Future<void> connect(String url, {Duration? timeout}) async {
    if (_connected) return;
    _connected = true;
    _subscribed.clear();
    _advertised.clear();
    _cancelledGoals.clear();
    sentOps.clear();
    _emit(<String, dynamic>{'op': 'status', 'level': 'info', 'message': 'mock rosbridge ready'});
  }

  @override
  Future<void> disconnect() async {
    _stopSimulation();
    // Invalidates any in-flight fake goal chain.
    _goalGeneration++;
    _subscribed.clear();
    _advertised.clear();
    _cancelledGoals.clear();
    _connected = false;
  }

  @override
  Future<void> send(dynamic payload) async {
    if (!_connected) return;
    final op = payload is Map<String, dynamic> ? payload : null;
    if (op == null) {
      _emitError('mock: dropping a non-JSON frame');
      return;
    }
    sentOps.add(op);
    _handle(op);
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    // Do not await: a broadcast controller's close future only completes once
    // the done event is delivered, which never happens under fake async.
    unawaited(_incoming.close());
    unawaited(_errors.close());
  }

  void _handle(Map<String, dynamic> op) {
    switch (op['op']) {
      case 'call_service':
        _callService(op);
      case 'advertise':
        final topic = op['topic'];
        if (topic is String) _advertised.add(topic);
      case 'unadvertise':
        final topic = op['topic'];
        if (topic is String) _advertised.remove(topic);
      case 'subscribe':
        final topic = op['topic'];
        if (topic is String) {
          _subscribed.add(topic);
          _startSimulation();
        }
      case 'unsubscribe':
        final topic = op['topic'];
        if (topic is String) {
          _subscribed.remove(topic);
          if (_subscribed.isEmpty) _stopSimulation();
        }
      case 'publish':
        final topic = op['topic'];
        if (topic is! String) return;
        if (!_advertised.contains(topic)) {
          _emitError("rosbridge[warning]: publish: topic '$topic' is not advertised");
        }
      case 'action_goal':
        _startGoal(op);
      case 'action_cancel':
        final id = op['id'];
        if (id is String) _cancelledGoals.add(id);
    }
  }

  void _callService(Map<String, dynamic> op) {
    final id = op['id'] as String?;
    final service = op['service'] as String?;
    if (id == null || service == null) return;

    void respond(Map<String, dynamic> values) {
      _emit(<String, dynamic>{
        'op': 'service_response',
        'id': id,
        'service': service,
        'values': values,
        'result': true,
      });
    }

    switch (service) {
      case '/rosapi/topics':
        respond(<String, dynamic>{
          'topics': _topics.keys.toList(),
          'types': [for (final t in _topics.keys) _topics[t]],
        });
      case '/rosapi/services':
        respond(<String, dynamic>{
          'services': _services.keys.toList(),
          'types': [for (final s in _services.keys) _services[s]],
        });
      case '/rosapi/nodes':
        respond(<String, dynamic>{
          'nodes': const [
            '/UasDraw/gcode_interpreter',
            '/rosapi',
            '/rosbridge_websocket',
          ],
        });
      case '/rosapi/message_details':
        final args = op['args'] as Map<String, dynamic>?;
        final type = args?['type'] as String? ?? '';
        respond(<String, dynamic>{
          'typedefs_full_text': [rosdrvFor(type)],
        });
      case '/uas_draw/load_gcode_content':
        final args = op['args'] as Map<String, dynamic>?;
        final content = args?['content'] as String? ?? '';
        respond(<String, dynamic>{
          'operation_result': <String, dynamic>{
            'was_successful': content.trim().isNotEmpty,
            'message': content.trim().isEmpty ? 'empty g-code payload' : '',
          },
        });
      case '/uas_draw/pause':
      case '/uas_draw/resume':
      case '/uas_draw/set_pen':
      case '/uas_draw/set_drawing_context':
        // These reply with a field literally named `result`.
        respond(<String, dynamic>{
          'result': <String, dynamic>{'was_successful': true, 'message': ''},
        });
      case '/uas_draw/cancel_drawing':
        _goalGeneration++;
        respond(<String, dynamic>{
          'operation_result': <String, dynamic>{
            'was_successful': true,
            'message': 'drawing cancelled',
          },
        });
      case '/uas_draw/set_home':
        respond(<String, dynamic>{
          'position': <String, dynamic>{'x': 0.0, 'y': 0.0, 'z': 0.0},
        });
      case '/uas_draw/set_origin':
        respond(<String, dynamic>{
          'position': <String, dynamic>{'x': 50.0, 'y': 50.0, 'z': -0.5},
        });
      default:
        if (_services.containsKey(service)) {
          respond(<String, dynamic>{'success': true, 'message': ''});
        } else {
          _emit(<String, dynamic>{
            'op': 'service_response',
            'id': id,
            'service': service,
            'values': const <String, dynamic>{},
            'result': false,
          });
        }
    }
  }

  /// Fake `DrawPicture` action server: streams a handful of feedback frames,
  /// then either succeeds or reports the cancellation.
  ///
  /// A goal advances through chained [Future.delayed] calls rather than a
  /// periodic timer, so it always terminates on its own. [goalGeneration]
  /// invalidates the chain of any previous goal: only the newest one keeps
  /// ticking, and a disconnect stops the chain without leaving a timer behind.
  void _startGoal(Map<String, dynamic> op) {
    final id = op['id'] as String?;
    final action = op['action'] as String?;
    if (id == null || action == null) return;

    void result(bool success, Map<String, dynamic> values) {
      _cancelledGoals.remove(id);
      _emit(<String, dynamic>{
        'op': 'action_result',
        'id': id,
        'action': action,
        'values': values,
        'result': success,
      });
    }

    if (!_actions.containsKey(action)) {
      // rosbridge rejects goals for unknown action servers.
      result(false, const <String, dynamic>{});
      return;
    }
    final generation = ++_goalGeneration;
    _stepGoal(id, action, generation, 0, result);
  }

  void _stepGoal(
    String id,
    String action,
    int generation,
    int step,
    void Function(bool, Map<String, dynamic>) result,
  ) {
    Future<void>.delayed(_goalTick, () {
      if (!_connected || generation != _goalGeneration) return;
      if (_cancelledGoals.contains(id)) {
        result(false, <String, dynamic>{
          'result': <String, dynamic>{
            'was_successful': false,
            'message': 'drawing cancelled',
          },
        });
        return;
      }
      if (step >= _goalSteps) {
        result(true, <String, dynamic>{
          'result': <String, dynamic>{
            'was_successful': true,
            'message': 'picture drawn',
          },
        });
        return;
      }
      final line = (step + 1) * _goalLinesPerStep;
      _emit(<String, dynamic>{
        'op': 'action_feedback',
        'id': id,
        'action': action,
        'values': <String, dynamic>{
          'current_line': line,
          'progress': (line / _goalTotalLines).clamp(0.0, 1.0),
          'active_pen': <String, dynamic>{'type': 0, 'length_in_cm': 2.0},
        },
      });
      _stepGoal(id, action, generation, step + 1, result);
    });
  }

  /// Incremented per goal so stale feedback chains stop on their next tick.
  int _goalGeneration = 0;

  /// Delay between two fake feedback frames.
  static const Duration _goalTick = Duration(milliseconds: 120);

  /// Feedback frames a fake picture takes to draw.
  static const int _goalSteps = 12;

  /// G-code lines the fake job walks through, used to scale `progress`.
  static const int _goalLinesPerStep = 10;
  static const int _goalTotalLines = _goalSteps * _goalLinesPerStep;

  /// Fake vehicle + drawing node data, forwarded only to subscribers.
  ///
  /// The timers exist only while something is subscribed: nothing is emitted
  /// to an unsubscribed client anyway, and idle timers would burn CPU and leak
  /// into widget tests as pending FakeTimers.
  void _startSimulation() {
    if (_batteryTimer != null || !_connected) return;
    _batteryTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _forward(<String, dynamic>{
        'op': 'publish',
        'topic': '/mavros/battery',
        'msg': <String, dynamic>{
          'header': <String, dynamic>{'stamp': <String, dynamic>{'sec': 0, 'nanosec': 0}, 'frame_id': ''},
          'voltage': 14.8,
          'current': 2.5,
          'charge': -1.0,
          'capacity': -1.0,
          'design_capacity': -1.0,
          'percentage': 85.0,
          'power_supply_status': 0,
          'power_supply_health': 0,
          'power_supply_technology': 0,
          'present': true,
          'cell_voltage': [3.7, 3.7, 3.7, 3.7],
          'cell_temperature': [],
          'location': '',
          'serial_number': '',
        },
      });
    });

    _dataTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _forward(<String, dynamic>{
        'op': 'publish',
        'topic': '/uas_draw/data',
        'msg': <String, dynamic>{
          'type': 1,
          // UasDrawDataBlock carries a nested geometry_msgs/Point, but the arc
          // centre offset as three flat float64 fields.
          'position': <String, dynamic>{'x': 1.0, 'y': 1.0, 'z': -0.5},
          'arc_center_offset_x': 0.0,
          'arc_center_offset_y': 0.0,
          'arc_center_offset_z': 0.0,
          'speed_in_ms': 0.0,
          'is_drawing': true,
        },
      });
    });

    // Free capacity of the drawing buffer, drifting down so the UI has a
    // non-trivial number to render.
    var free = 256;
    _bufferTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      free = (free - 8).clamp(0, 256);
      _forward(<String, dynamic>{
        'op': 'publish',
        'topic': '/uas_draw/buffer_status',
        'msg': <String, dynamic>{'free_capacity': free},
      });
    });

    // Stand-in for /rosout: cycles through a few severities so the log tail has
    // something with colour in it.
    var tick = 0;
    _rosoutTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      final record = _fakeLogs[tick % _fakeLogs.length];
      tick++;
      _forward(<String, dynamic>{
        'op': 'publish',
        'topic': '/rosout',
        'msg': <String, dynamic>{
          'stamp': <String, dynamic>{'sec': 0, 'nanosec': 0},
          'level': record.level,
          'name': record.node,
          'msg': record.text,
          'file': 'mock_transport.dart',
          'function': '_startSimulation',
          'line': 0,
        },
      });
    });
  }

  static const List<({int level, String node, String text})> _fakeLogs =
      <({int level, String node, String text})>[
    (level: 20, node: '/uas_draw/gcode_interpreter', text: 'G-code loaded, 7 commands'),
    (level: 30, node: '/uas_draw/gcode_interpreter', text: 'M00 reached, holding for operator'),
    (level: 20, node: '/UasDraw/safety', text: 'offboard setpoint stream nominal'),
    (level: 40, node: '/uas_draw/gcode_interpreter', text: 'buffer underrun, line 42 stalled'),
    (level: 20, node: '/mavros', text: 'connected to 192.168.1.10:14550'),
  ];

  void _stopSimulation() {
    _batteryTimer?.cancel();
    _dataTimer?.cancel();
    _bufferTimer?.cancel();
    _rosoutTimer?.cancel();
    _batteryTimer = null;
    _dataTimer = null;
    _bufferTimer = null;
    _rosoutTimer = null;
  }

  void _forward(Map<String, dynamic> frame) {
    final topic = frame['topic'] as String?;
    if (topic == null || !_subscribed.contains(topic)) return;
    _emit(frame);
  }

  void _emit(Map<String, dynamic> frame) {
    if (!_incoming.isClosed) _incoming.add(frame);
  }

  void _emitError(String message) {
    if (!_errors.isClosed) _errors.add(message);
  }

  static const Map<String, String> _topics = <String, String>{
    '/rosout': 'rcl_interfaces/msg/Log',
    '/uas_draw/data': 'uas_draw_interfaces/msg/UasDrawDataBlock',
    '/uas_draw/buffer_status': 'uas_draw_interfaces/msg/BufferStatus',
    '/UasDraw/joy': 'sensor_msgs/msg/Joy',
    '/mavros/battery': 'mavros_msgs/msg/BatteryState',
    '/mavros/state': 'mavros_msgs/msg/State',
  };

  static const Map<String, String> _services = <String, String>{
    '/UasDraw/arm': 'std_srvs/srv/Trigger',
    '/UasDraw/offboard': 'std_srvs/srv/Trigger',
    '/UasDraw/land': 'std_srvs/srv/Trigger',
    '/UasDraw/rtl': 'std_srvs/srv/Trigger',
    '/uas_draw/load_gcode_content': 'uas_draw_interfaces/srv/LoadGCodeContent',
    '/uas_draw/cancel_drawing': 'uas_draw_interfaces/srv/Cancel',
    '/uas_draw/pause': 'uas_draw_interfaces/srv/Pause',
    '/uas_draw/resume': 'uas_draw_interfaces/srv/Resume',
    '/uas_draw/set_pen': 'uas_draw_interfaces/srv/SetPen',
    '/uas_draw/set_home': 'uas_draw_interfaces/srv/SetHome',
    '/uas_draw/set_origin': 'uas_draw_interfaces/srv/SetOrigin',
    '/uas_draw/set_drawing_context':
        'uas_draw_interfaces/srv/SetDrawingContext',
    '/mavros/cmd/arming': 'mavros_msgs/srv/CommandBool',
  };

  /// Action servers the fake graph serves.
  ///
  /// rosapi does not expose action servers, so this map is only consulted when
  /// a goal actually arrives.
  static const Map<String, String> _actions = <String, String>{
    '/uas_draw/draw_picture': 'uas_draw_interfaces/action/DrawPicture',
  };
}

/// ROSDRV text for the handful of types the simulation knows about.
///
/// Only used by the mock `/rosapi/message_details` stand-in.
String rosdrvFor(String type) => switch (type) {
      'std_srvs/srv/Trigger' => 'string message\n'
          '---\n'
          'bool success\n'
          'string message\n',
      'uas_draw_interfaces/srv/LoadGCodeContent' => 'string content\n'
          '---\n'
          'uas_draw_interfaces/Result operation_result\n',
      'uas_draw_interfaces/srv/Pause' => '\n'
          '---\n'
          'uas_draw_interfaces/Result result\n',
      'uas_draw_interfaces/srv/Resume' => '\n'
          '---\n'
          'uas_draw_interfaces/Result result\n',
      'uas_draw_interfaces/srv/SetPen' => 'uas_draw_interfaces/Pen pen\n'
          '---\n'
          'uas_draw_interfaces/Result result\n',
      'uas_draw_interfaces/srv/SetDrawingContext' =>
        'uas_draw_interfaces/UasDrawContext context\n'
            '---\n'
            'uas_draw_interfaces/Result result\n',
      'uas_draw_interfaces/srv/SetHome' => '\n'
          '---\n'
          'geometry_msgs/Point position\n',
      'uas_draw_interfaces/srv/SetOrigin' => '\n'
          '---\n'
          'geometry_msgs/Point position\n',
      'uas_draw_interfaces/action/DrawPicture' => '\n'
          '---\n'
          'uint32 current_line\n'
          'float32 progress\n'
          'uas_draw_interfaces/Pen active_pen\n'
          '---\n'
          'uas_draw_interfaces/Result result\n',
      'uas_draw_interfaces/Result' => 'bool was_successful\n'
          'string message\n',
      'uas_draw_interfaces/Pen' => 'uint8 type\n'
          'float64 length_in_cm\n',
      'uas_draw_interfaces/BufferStatus' => 'uint32 free_capacity\n',
      'uas_draw_interfaces/Vector2D' => 'float64 x\n'
          'float64 y\n',
      'uas_draw_interfaces/Canvas' =>
        'uas_draw_interfaces/Vector2D dimensions_in_cm\n',
      'uas_draw_interfaces/UasDrawContext' =>
        'uas_draw_interfaces/Canvas canvas\n'
            'bool scale_picture\n'
            'uas_draw_interfaces/Pen pen\n',
      'sensor_msgs/msg/Joy' => 'std_msgs/Header header\n'
          'float32[] axes\n'
          'int32[] buttons\n',
      'geometry_msgs/msg/Point' => 'float64 x\n'
          'float64 y\n'
          'float64 z\n',
      _ => '',
    };