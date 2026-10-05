import 'dart:convert';

/// Whether a [Binding] points at a ROS topic, service or action server.
enum BindingKind { topic, service, action }

/// Maps one logical UI action onto a concrete ROS name, type and (for
/// services and actions) the default request fields to send.
class Binding {
  const Binding({
    required this.name,
    required this.type,
    this.kind = BindingKind.topic,
    this.args = const <String, dynamic>{},
  });

  const Binding.topic(this.name, this.type, {this.args = const <String, dynamic>{}})
      : kind = BindingKind.topic;

  const Binding.service(this.name, this.type, {this.args = const <String, dynamic>{}})
      : kind = BindingKind.service;

  const Binding.action(this.name, this.type, {this.args = const <String, dynamic>{}})
      : kind = BindingKind.action;

  /// Absolute ROS name, e.g. `/UasDraw/arm`.
  final String name;

  /// Fully qualified type, e.g. `std_srvs/srv/Trigger`.
  final String type;

  final BindingKind kind;

  /// Request fields sent with a service call. Callers may override these.
  final Map<String, dynamic> args;

  bool get isService => kind == BindingKind.service;

  bool get isAction => kind == BindingKind.action;

  /// Merges [extra] over the binding defaults.
  Map<String, dynamic> argsWith(Map<String, dynamic> extra) =>
      <String, dynamic>{...args, ...extra};

  Binding copyWith({
    String? name,
    String? type,
    BindingKind? kind,
    Map<String, dynamic>? args,
  }) =>
      Binding(
        name: name ?? this.name,
        type: type ?? this.type,
        kind: kind ?? this.kind,
        args: args ?? this.args,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'type': type,
        'kind': kind.name,
        if (args.isNotEmpty) 'args': args,
      };

  static Binding fromJson(Map<String, dynamic> json) => Binding(
        name: json['name'] as String? ?? '',
        type: json['type'] as String? ?? '',
        // Falls back to `topic` for profiles saved before actions existed.
        kind: BindingKind.values.firstWhere(
          (kind) => kind.name == json['kind'],
          orElse: () => BindingKind.topic,
        ),
        args: (json['args'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      );

  @override
  String toString() => '${kind.name} $name [$type]';
}

/// Logical action keys used throughout the UI.
enum LogicalAction {
  joy,
  drawData,
  arm,
  offboard,
  land,
  rtl,
  loadGcodeContent,
  setpointPositionLocal,
  battery,
  state,
  cancelDrawing,
  pause,
  resume,
  setPen,
  setHome,
  setOrigin,
  setDrawingContext,
  drawPicture,
  bufferStatus,
  rosout,
}

/// A complete set of [Binding]s, keyed by [LogicalAction].
///
/// Nothing in the app hardcodes ROS names any more: every screen resolves a
/// [LogicalAction] through this object, which is stored per connection profile
/// and can be overridden in the UI.
class Bindings {
  Bindings(this._map);

  final Map<LogicalAction, Binding> _map;

  /// Binding for [action], or `null` when the action is not bound.
  Binding? get(LogicalAction action) => _map[action];

  Map<LogicalAction, Binding> get all => Map.unmodifiable(_map);

  Bindings withOverride(LogicalAction action, Binding binding) =>
      Bindings(<LogicalAction, Binding>{..._map, action: binding});

  /// Bindings shared by every preset because they belong to the ROS graph
  /// itself rather than to one node: `/rosout` is where every node logs.
  static Map<LogicalAction, Binding> get _shared =>
      <LogicalAction, Binding>{
        LogicalAction.rosout: const Binding.topic(
          '/rosout',
          'rcl_interfaces/msg/Log',
        ),
      };

  /// Bindings served by the UasDraw drawing node itself.
  ///
  /// Both presets draw through the same node, so these are shared rather than
  /// repeated: only the vehicle commands differ between them.
  static Map<LogicalAction, Binding> get _drawingNode =>
      <LogicalAction, Binding>{
        LogicalAction.loadGcodeContent: const Binding.service(
          '/uas_draw/load_gcode_content',
          'uas_draw_interfaces/srv/LoadGCodeContent',
          args: <String, dynamic>{'content': ''},
        ),
        LogicalAction.cancelDrawing: const Binding.service(
          '/uas_draw/cancel_drawing',
          'uas_draw_interfaces/srv/Cancel',
        ),
        LogicalAction.pause: const Binding.service(
          '/uas_draw/pause',
          'uas_draw_interfaces/srv/Pause',
        ),
        LogicalAction.resume: const Binding.service(
          '/uas_draw/resume',
          'uas_draw_interfaces/srv/Resume',
        ),
        LogicalAction.setPen: const Binding.service(
          '/uas_draw/set_pen',
          'uas_draw_interfaces/srv/SetPen',
        ),
        LogicalAction.setHome: const Binding.service(
          '/uas_draw/set_home',
          'uas_draw_interfaces/srv/SetHome',
        ),
        LogicalAction.setOrigin: const Binding.service(
          '/uas_draw/set_origin',
          'uas_draw_interfaces/srv/SetOrigin',
        ),
        LogicalAction.setDrawingContext: const Binding.service(
          '/uas_draw/set_drawing_context',
          'uas_draw_interfaces/srv/SetDrawingContext',
        ),
        LogicalAction.drawPicture: const Binding.action(
          '/uas_draw/draw_picture',
          'uas_draw_interfaces/action/DrawPicture',
        ),
        LogicalAction.bufferStatus: const Binding.topic(
          '/uas_draw/buffer_status',
          'uas_draw_interfaces/msg/BufferStatus',
        ),
      };

  /// The stock UasDraw workspace: safety wrapper services for commands and
  /// `sensor_msgs/Joy` for manual control.
  ///
  /// This is the recommended setup: the wrapper node owns the failsafes, the
  /// offboard setpoint stream and the PX4 mode encoding, so the app never talks
  /// to the flight controller directly.
  factory Bindings.uasDraw() => Bindings(<LogicalAction, Binding>{
        ..._shared,
        ..._drawingNode,
        LogicalAction.joy: const Binding.topic(
          '/UasDraw/joy',
          'sensor_msgs/msg/Joy',
        ),
        LogicalAction.drawData: const Binding.topic(
          '/uas_draw/data',
          'uas_draw_interfaces/msg/UasDrawDataBlock',
        ),
        LogicalAction.arm: const Binding.service(
          '/UasDraw/arm',
          'std_srvs/srv/Trigger',
        ),
        LogicalAction.offboard: const Binding.service(
          '/UasDraw/offboard',
          'std_srvs/srv/Trigger',
        ),
        LogicalAction.land: const Binding.service(
          '/UasDraw/land',
          'std_srvs/srv/Trigger',
        ),
        LogicalAction.rtl: const Binding.service(
          '/UasDraw/rtl',
          'std_srvs/srv/Trigger',
        ),
        LogicalAction.setpointPositionLocal: const Binding.topic(
          '/mavros/setpoint_position/local',
          'geometry_msgs/msg/PoseStamped',
        ),
        LogicalAction.battery: const Binding.topic(
          '/mavros/battery',
          'mavros_msgs/msg/BatteryState',
        ),
        LogicalAction.state: const Binding.topic(
          '/mavros/state',
          'mavros_msgs/msg/State',
        ),
      });

  /// Talks to MAVROS directly, with no UasDraw wrapper node.
  ///
  /// MAVROS 2.x has **no** `/mavros/set_mode` and no `/mavros/cmd/rtl` service.
  /// Mode changes go through `/mavros/cmd/command` with
  /// `MAV_CMD_DO_SET_MODE` (176) and a PX4 custom mode number:
  /// `POSCTL = 2`, `AUTO.RTL = 5`, `OFFBOARD = 6`.
  ///
  /// Prefer the `uasDraw` preset unless you know you want to own the offboard
  /// setpoint stream and the failsafes yourself.
  factory Bindings.mavros() => Bindings(<LogicalAction, Binding>{
        ..._shared,
        ..._drawingNode,
        LogicalAction.joy: const Binding.topic(
          '/UasDraw/joy',
          'sensor_msgs/msg/Joy',
        ),
        LogicalAction.drawData: const Binding.topic(
          '/uas_draw/data',
          'uas_draw_interfaces/msg/UasDrawDataBlock',
        ),
        LogicalAction.arm: const Binding.service(
          '/mavros/cmd/arming',
          'mavros_msgs/srv/CommandBool',
          args: <String, dynamic>{'value': true},
        ),
        LogicalAction.offboard: const Binding.service(
          '/mavros/cmd/command',
          'mavros_msgs/srv/CommandLong',
          args: <String, dynamic>{
            'broadcast': false,
            'command': 176,
            'confirmation': 0,
            'param1': 0,
            'param2': 6,
            'param3': 0,
            'param4': 0,
            'param5': 0,
            'param6': 0,
            'param7': 0,
          },
        ),
        LogicalAction.land: const Binding.service(
          '/mavros/cmd/land',
          'mavros_msgs/srv/CommandTOL',
          args: <String, dynamic>{
            'min_pitch': 0.0,
            'yaw': 0.0,
            'latitude': 0.0,
            'longitude': 0.0,
            'altitude': 0.0,
          },
        ),
        LogicalAction.rtl: const Binding.service(
          '/mavros/cmd/command',
          'mavros_msgs/srv/CommandLong',
          args: <String, dynamic>{
            'broadcast': false,
            'command': 176,
            'confirmation': 0,
            'param1': 0,
            'param2': 5,
            'param3': 0,
            'param4': 0,
            'param5': 0,
            'param6': 0,
            'param7': 0,
          },
        ),
        LogicalAction.setpointPositionLocal: const Binding.topic(
          '/mavros/setpoint_position/local',
          'geometry_msgs/msg/PoseStamped',
        ),
        LogicalAction.battery: const Binding.topic(
          '/mavros/battery',
          'mavros_msgs/msg/BatteryState',
        ),
        LogicalAction.state: const Binding.topic(
          '/mavros/state',
          'mavros_msgs/msg/State',
        ),
      });

  /// Named presets the UI offers.
  static final Map<String, Bindings> presets = <String, Bindings>{
    'uasDraw': Bindings.uasDraw(),
    'mavros': Bindings.mavros(),
  };

  static String presetName(Bindings bindings) {
    final encoded = jsonEncode(bindings.toJson());
    for (final entry in presets.entries) {
      if (jsonEncode(entry.value.toJson()) == encoded) return entry.key;
    }
    return 'custom';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        for (final entry in _map.entries)
          entry.key.name: entry.value.toJson(),
      };

  static Bindings fromJson(Map<String, dynamic> json) => Bindings(
        <LogicalAction, Binding>{
          for (final entry in json.entries)
            if (LogicalAction.values.asNameMap().containsKey(entry.key))
              LogicalAction.values.asNameMap()[entry.key]!:
                  Binding.fromJson((entry.value as Map).cast<String, dynamic>()),
        },
      );
}