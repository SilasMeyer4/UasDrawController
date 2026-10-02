/// Binding of logical action to concrete ROS names/types.
class Binding {
  final String topic;
  final String type;
  final String? service;

  Binding({required this.topic, required this.type, this.service});
}

/// Logical action keys used throughout the UI.
enum LogicalAction {
  joy,
  arm,
  offboard,
  land,
  rtl,
  loadGcodeContent,
  setpointPositionLocal,
  battery,
  state,
}

class Bindings {
  final Map<LogicalAction, Binding> map;

  Bindings(this.map);

  Bindings.defaults()
      : map = {
          LogicalAction.joy: Binding(
            topic: '/UasDraw/joy',
            type: 'sensor_msgs/msg/Joy',
          ),
          LogicalAction.arm: Binding(
            service: '/UasDraw/arm',
            topic: '/UasDraw/arm', // not a topic; service stored separately
            type: 'std_srvs/srv/Trigger',
          ),
          LogicalAction.offboard: Binding(
            service: '/UasDraw/offboard',
            topic: '/UasDraw/offboard',
            type: 'std_srvs/srv/Trigger',
          ),
          LogicalAction.land: Binding(
            service: '/UasDraw/land',
            topic: '/UasDraw/land',
            type: 'std_srvs/srv/Trigger',
          ),
          LogicalAction.rtl: Binding(
            service: '/UasDraw/rtl',
            topic: '/UasDraw/rtl',
            type: 'std_srvs/srv/Trigger',
          ),
          LogicalAction.loadGcodeContent: Binding(
            service: '/UasDraw/load_gcode_content',
            topic: '/UasDraw/load_gcode_content',
            type: 'uas_draw_interfaces/srv/LoadGCodeContent',
          ),
          LogicalAction.setpointPositionLocal: Binding(
            topic: '/mavros/setpoint_position/local',
            type: 'geometry_msgs/msg/PoseStamped',
          ),
          LogicalAction.battery: Binding(
            topic: '/mavros/battery',
            type: 'mavros_msgs/msg/BatteryState',
          ),
          LogicalAction.state: Binding(
            topic: '/mavros/state',
            type: 'mavros_msgs/msg/State',
          ),
        };

  Binding get(LogicalAction a) => map[a] ?? Binding(topic: '', type: '');
}
