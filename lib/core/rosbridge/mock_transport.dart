import 'dart:async';
import 'dart:convert';
import 'ros_transport.dart';

/// Built-in simulation backend that mimics the rosbridge v2 protocol.
/// Used for development and testing without a running ROS system.
class MockTransport implements RosTransport {
  final StreamController<dynamic> _controller = StreamController<dynamic>.broadcast();
  bool _connected = false;
  Timer? _batteryTimer;
  Timer? _dataTimer;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect(String url, {Duration? timeout}) async {
    if (_connected) return;
    _connected = true;

    // Simulate rosapi introspection responses on demand by listening to
    // service calls sent by the client. The mock does not blindly emit
    // unsolicited responses; instead, it reacts to call_service ops for
    // rosbridge introspection and common topics.
    _controller.stream.listen((event) {
      if (event is! Map<String, dynamic>) return;
      final op = event['op'] as String?;
      if (op != 'call_service') return;

      final service = event['service'] as String?;
      final id = event['id'] as String?;
      if (id == null) return;

      switch (service) {
        case '/rosbridge/topics':
          _controller.add(<String, dynamic>{
            'op': 'service_response',
            'id': id,
            'service': '/rosbridge/topics',
            'values': {
              'topics': [
                '/UasDraw/uas_draw/data',
                '/UasDraw/joy',
                '/mavros/battery',
                '/mavros/state',
                '/mavros/setpoint_position/local',
                '/turtle1/cmd_vel',
                '/turtle1/pose',
              ],
              'types': [
                'uas_draw_interfaces/msg/UasDrawDataBlock',
                'sensor_msgs/msg/Joy',
                'mavros_msgs/msg/BatteryState',
                'mavros_msgs/msg/State',
                'geometry_msgs/msg/PoseStamped',
                'geometry_msgs/msg/Twist',
                'turtlesim/msg/Pose',
              ],
            },
            'result': true,
          });
          break;
        case '/rosbridge/services':
          _controller.add(<String, dynamic>{
            'op': 'service_response',
            'id': id,
            'service': '/rosbridge/services',
            'values': {
              'services': [
                '/UasDraw/arm',
                '/UasDraw/offboard',
                '/UasDraw/land',
                '/UasDraw/rtl',
                '/UasDraw/load_preset_file',
                '/UasDraw/load_gcode_content',
                '/mavros/cmd/arming',
                '/mavros/set_mode',
                '/rosbridge/topics',
                '/rosbridge/services',
                '/rosbridge/nodes',
                '/rosbridge/msg_definition',
              ],
              'types': [
                'std_srvs/srv/Trigger',
                'std_srvs/srv/Trigger',
                'std_srvs/srv/Trigger',
                'std_srvs/srv/Trigger',
                'uas_draw_interfaces/srv/LoadFile',
                'uas_draw_interfaces/srv/LoadGCodeContent',
                'mavros_msgs/srv/CommandBool',
                'mavros_msgs/srv/SetMode',
                'rosapi_msgs/srv/Topics',
                'rosapi_msgs/srv/Services',
                'rosapi_msgs/srv/Nodes',
                'rosapi_msgs/srv/MessageDefinition',
              ],
            },
            'result': true,
          });
          break;
        case '/rosbridge/nodes':
          _controller.add(<String, dynamic>{
            'op': 'service_response',
            'id': id,
            'service': '/rosbridge/nodes',
            'values': {
              'nodes': [
                '/UasDraw/GCodeInterpreterNode',
                '/UasDraw/TurtleInterpolatorNode',
                '/turtle1',
                '/rosbridge_websocket',
                '/rosapi',
              ],
            },
            'result': true,
          });
          break;
        case '/rosbridge/msg_definition':
          final args = event['args'] as Map<String, dynamic>?;
          final md = args?['message_definition'] as String?;
          _controller.add(<String, dynamic>{
            'op': 'service_response',
            'id': id,
            'service': '/rosbridge/msg_definition',
            'values': {
              'message_definition': _msgDef(md),
            },
            'result': true,
          });
          break;
        default:
          _controller.add(<String, dynamic>{
            'op': 'service_response',
            'id': id,
            'service': service,
            'values': {'success': true},
            'result': true,
          });
          break;
      }
    });

    // Simulate periodic telemetry
    _batteryTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _controller.add(<String, dynamic>{
        'op': 'publish',
        'topic': '/mavros/battery',
        'msg': {
          'voltage': 14.8,
          'current': 2.5,
          'percentage': 85,
          'cell_voltage': [3.7, 3.7, 3.7, 3.7],
        },
      });
    });

    _dataTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _controller.add(<String, dynamic>{
        'op': 'publish',
        'topic': '/UasDraw/uas_draw/data',
        'msg': {
          'type': 1,
          'x': 1.0,
          'y': 1.0,
          'z': -0.5,
          'arc_center_offset_x': 0.0,
          'arc_center_offset_y': 0.0,
          'arc_center_offset_z': 0.0,
          'speed_in_ms': 0.0,
          'is_drawing': true,
        },
      });
    });

    _controller.add(<String, dynamic>{
      'op': 'status',
      'connected': true,
    });
  }

  @override
  Future<void> disconnect() async {
    _batteryTimer?.cancel();
    _dataTimer?.cancel();
    _batteryTimer = null;
    _dataTimer = null;
    _connected = false;
  }

  @override
  Stream<dynamic> stream() => _controller.stream;

  @override
  Future<void> send(dynamic payload) async {
    if (!_connected) return;
    if (payload is String) {
      try {
        _controller.add(jsonDecode(payload));
      } catch (_) {
        _controller.add(payload);
      }
    } else {
      _controller.add(payload);
    }
  }
}

/// Return minimal ROSDRV text for a small set of common message definitions
/// used by the app. Unknown definitions fall back to an empty string, which
/// the introspection layer treats as "unknown type" (form will be skipped).
String _msgDef(String? md) {
  switch (md) {
    case 'std_srvs/srv/Trigger':
      return 'bool success\n---\nbool success\nstring message\n';
    case 'uas_draw_interfaces/srv/LoadFile':
      return 'string file_path\n---\nbool success\n';
    case 'uas_draw_interfaces/srv/LoadGCodeContent':
      return 'string content\n---\nbool success\n';
    case 'sensor_msgs/msg/Joy':
      return 'std_msgs/Header header\nfloat32[] axes\nint32[] buttons\n';
    case 'mavros_msgs/msg/State':
      return 'std_msgs/Header header\nbool connected\nbool armed\nbool guided\nbool manual_input\nenum state\nstring mode\n';
    case 'mavros_msgs/msg/BatteryState':
      return 'std_msgs/Header header\nfloat32 voltage\nfloat32 current\nfloat32 percentage\n';
    case 'uas_draw_interfaces/msg/UasDrawDataBlock':
      return 'uint8 TYPE_RAPID=0\nuint8 TYPE_LINEAR=1\nuint8 TYPE_CLOCKWISE_ARC=2\nuint8 TYPE_COUNTER_CLOCK_WISE_ARC=3\nuint8 type\nfloat64 x\nfloat64 y\nfloat64 z\nfloat64 arc_center_offset_x\nfloat64 arc_center_offset_y\nfloat64 arc_center_offset_z\nfloat64 speed_in_ms\nbool is_drawing\n';
    default:
      return '';
  }
}

/// Helper to fire-and-forget a delayed callback without returning a Future
/// that callers must await.
void unawaited(Future<void> future) {}
