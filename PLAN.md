# UasDraw Controller App — Project Plan

Companion control application for the **UasDraw** ROS 2 system (drone drawing from G-Code).
Bachelor thesis project, HS Offenburg — Silas Meyer.

- **App repository:** `/home/silas/ros2_workspace/UasDraw/UasDrawControllerApp/` (this folder)
- **ROS 2 workspace:** `/home/silas/ros2_workspace/UasDraw/workspace/` — **read-only for this project, never modified**
- **ROS 2 workspace remote:** `git@git.hs-offenburg.de:iuas-repos/draw-uas.git`
- **Application id:** `com.silasmeyer.uasdraw`
- **Targets:** Linux desktop + Android

---

## 1. Problem statement

The ROS 2 system currently stops at turtlesim. It has no remote control surface, no
flight-control backend, and no way to feed it a file from outside. This app provides
that surface for field testing and for driving the real drone.

The existing ROS graph (as of the last review, `main` @ `2a4c803`):

```
[G-Code file] --> GCodeInterpreterNode  /UasDraw/GCodeInterpreterNode
                 pub /UasDraw/uas_draw/data   uas_draw_interfaces/msg/UasDrawDataBlock
                 500 ms timer, param `init_file`
                        |
                        v
                 TurtleInterpolatorNode  /UasDraw/TurtleInterpolatorNode
                 pub /turtle1/cmd_vel   client /turtle1/set_pen
                        |
                        v
                 turtlesim
```

Known gaps that this project must work around without editing the workspace:

| Gap | Consequence for the app |
|---|---|
| No MAVLink / MAVROS / PX4 offboard node exists | App must not assume any flight topic exists |
| `CreateLoadFileService()` is never called (`src/gcode/src/gcode_interpreter_node.cpp:57`) | `/UasDraw/load_preset_file` will not be discoverable |
| The 500 ms timer lambda captures `data` **by value** | Even a live service could not swap the payload |
| `data` index wraps to `0` forever | A drawing drone would restart the drawing by itself |
| rosbridge is almost certainly not installed in the container | Transport must be verifiable without ROS |
| `UasDrawDataBlock.speed_in_ms`, `type`, arc offsets never populated | Diagnostics view will show zeros — expected, not a bug |

---

## 2. Key architectural decisions

### 2.1 Separate repository, not a colcon package

`UasDrawControllerApp/` is a sibling of `workspace/`, outside colcon's scan root, and is
its own git repository.

Reasons: the ROS repo builds C++20 with CMake and `colcon`, and already pulls `gpr`
from GitHub via `FetchContent`. A Flutter app brings `pubspec.lock`, Gradle and a
multi-gigabyte SDK into the same tree — separate CI, separate versioning, no
cross-contamination. No remote is configured yet; the repo is pushed to GitHub later
at your convenience.

### 2.2 rosbridge WebSocket, not native DDS

ROS 2 does not run on Android, so the app cannot be a native ROS 2 node. `rosbridge`
exposes the ROS graph as a JSON API over a WebSocket, which is the only practical
transport for a phone.

Benefits that matter here:

- The app **never needs the ROS 2 generated interfaces**. `rosbridge` converts any
  message to plain JSON at runtime, so `sensor_msgs/Joy`, `mavros_msgs/SetMode`,
  `std_srvs/Trigger` and `uas_draw_interfaces/UasDrawDataBlock` all work through one
  generic code path. There is no Dart message-generation step.
- Because rosbridge runs on the drone, the app never needs to resolve DDS, multicast
  or `ROS_DOMAIN_ID` itself.

### 2.3 Every ROS name is a configurable binding

The ROS side is unfinished and will change. Rather than hardcoding names, each logical
action maps to a name that is editable in the app and persisted per connection profile:

| Logical action | Default binding | Status today |
|---|---|---|
| Joystick input | `/UasDraw/joy` — `sensor_msgs/msg/Joy` | does not exist |
| Arm | `/UasDraw/arm` — `std_srvs/srv/Trigger` | does not exist |
| Offboard | `/UasDraw/offboard` — `std_srvs/srv/Trigger` | does not exist |
| Land | `/UasDraw/land` — `std_srvs/srv/Trigger` | does not exist |
| Return to launch | `/UasDraw/rtl` — `std_srvs/srv/Trigger` | does not exist |
| Load G-Code content | `/UasDraw/load_gcode_content` — `uas_draw_interfaces/srv/LoadGCodeContent` | does not exist |
| Position setpoint (read-only preview) | `/mavros/setpoint_position/local` | exists if MAVROS runs |
| Battery (read-only) | `/mavros/battery` — `mavros_msgs/msg/BatteryState` | exists if MAVROS runs |
| Vehicle state (read-only) | `/mavros/state` — `mavros_msgs/msg/State` | exists if MAVROS runs |

When the ROS nodes are written later, you either rename them to match or tap once in
Settings. **No Dart code changes.**

### 2.4 Capability discovery and graceful degradation

On connect, the app calls `/rosbridge/topics` and `/rosbridge/services`, diffs the
result against the bindings, and enables only what actually exists. A missing service
produces a disabled control with a "service not found" label — never a crash. This is
what allows the app to run today against a half-finished ROS system.

### 2.5 Built-in simulation backend

Because rosbridge availability is unknown, the app ships a `MockTransport` implementing
the same interface as the WebSocket transport. It fakes the `rosapi` introspection
services, streams synthetic `UasDrawDataBlock` messages, and reports plausible
`/mavros/state` and `/mavros/battery` values.

Purpose: the entire UI can be developed, demoed and tested with no ROS, no Pi and no
drone, and it doubles as a deterministic test harness for the protocol layer.

### 2.6 G-Code upload over the existing socket

rosbridge cannot write files, so uploading requires something on the drone. Rather than
a second daemon and a second port, the app sends the file **as text in a service call**:

```jsonc
{"op": "call_service",
 "service": "/UasDraw/load_gcode_content",
 "type": "uas_draw_interfaces/srv/LoadGCodeContent",
 "args": {"content": "G21\nG90\nF500\nG01 X0 Y0 Z-1\n..."}}
```

This needs roughly five lines of ROS code on the drone side, needs no systemd unit and
no firewall change, and reuses the transport that has to work anyway. G-Code files are
a few kilobytes, well inside rosbridge's limits.

If the service is not present, the Drawing tab states that explicitly instead of failing.

### 2.7 Simulation, SITL and the real drone are the same app

The app addresses ROS only by topic and service **name and type, resolved at runtime**.
It has no knowledge of what consumes the data. The same build works against turtlesim,
Gazebo, PX4 SITL and real hardware — only the names in the bindings change.

---

## 3. Protocol contract

Client to server (rosbridge v2 protocol):

```jsonc
{"op": "subscribe",   "id": "1", "topic": "/mavros/battery", "type": "mavros_msgs/msg/BatteryState", "rate": 2}
{"op": "unsubscribe", "id": "1", "topic": "/mavros/battery", "type": "mavros_msgs/msg/BatteryState"}
{"op": "advertise",   "id": "2", "topic": "/UasDraw/joy", "type": "sensor_msgs/msg/Joy"}
{"op": "unadvertise", "id": "2", "topic": "/UasDraw/joy", "type": "sensor_msgs/msg/Joy"}
{"op": "publish",     "id": "2", "topic": "/UasDraw/joy", "msg": {"axes": [0.0, 0.0, 0.0, 0.0], "buttons": []}}
{"op": "call_service","id": "3", "service": "/UasDraw/arm", "type": "std_srvs/srv/Trigger", "args": {}}
{"op": "set_level",   "level": "ERROR"}
{"op": "status"}
```

Server to client:

```jsonc
{"op": "publish", "topic": "/mavros/battery", "msg": {...}}
{"op": "service_response", "id": "3", "service": "/UasDraw/arm", "values": {"success": true}, "result": true}
{"op": "call_service", "id": "4", "service": "/rosbridge/topics", "type": "rosapi_msgs/srv/Topics", "args": {}}
```

Introspection, which is what makes the dynamic service-call form possible:

```jsonc
{"op": "call_service", "service": "/rosbridge/msg_definition",
 "type": "rosapi_msgs/srv/MessageDefinition",
 "args": {"message_definition": "std_srvs/srv/Trigger"}}
```

returns a ROSDRV text schema (`"bool success\n---\n"`). The app parses that into a typed
field tree, including array bounds and named constants such as the
`TYPE_RAPID=0` style constants in `UasDrawDataBlock`, and builds a form from it.

Default port: `9090`, bound to `0.0.0.0`.

---

## 4. Module layout

```
lib/
  main.dart
  app/                      routing, theme, responsive shell
  core/
    rosbridge/
      ros_transport.dart        Transport interface
      websocket_transport.dart  real rosbridge over WebSocket
      mock_transport.dart       offline simulation
      ros_ops.dart              typed op builders
      ros_client.dart           op dispatch, request/response correlation, reconnect
      introspection.dart        ROSDRV text -> FieldSchema tree
      ros_graph.dart            cached nodes/topics/services
    models/
      connection_profile.dart   name, ws url, transport kind
      bindings.dart             logical action -> topic/service + type
      field_schema.dart         introspected message shape
      joystick_state.dart
    services/
      profile_store.dart        JSON in the app support directory
      connection_manager.dart   ChangeNotifier owning client lifecycle
      safety_settings.dart      max rates, joystick rate, fail-safe prefs
  features/
    connect/                profile picker, connect/disconnect, status
    diagnostics/            nodes, topics, services, parameters
    drawing/                file picker, upload, file list, live data readout
    flight/                 joystick, vehicle commands, telemetry
  widgets/
    virtual_joystick.dart
    message_table.dart
    dynamic_form.dart
```

Third-party packages are limited to `web_socket_channel`, `provider`, `go_router`,
`file_picker` and `path_provider`. There is no rosbridge Dart library on purpose: the
protocol is eight JSON operations, so a small hand-written client avoids any version
coupling to the drone's rosbridge release.

---

## 5. Phases and gates

| Phase | Content | Gate |
|---|---|---|
| P0 | Fedora deps, Flutter stable SDK, JDK 21, `ANDROID_HOME` | `flutter doctor -v` clean |
| P1 | `flutter create`, Android `INTERNET` + cleartext traffic, `git init` | `flutter build linux` and `flutter build apk --debug` |
| P2 | Transport interface, both implementations, op codec, introspection parser, rosgraph cache, stores | `flutter test` green |
| P3 | Diagnostics: profiles, graph lists, live topic viewer, dynamic service form, parameters | manual |
| P4 | Drawing: file picker, content upload, file list, live `UasDrawDataBlock` readout | manual |
| P5 | Flight: virtual joystick, vehicle commands with confirmation, telemetry | manual |
| P6 | Reconnect UX, landscape layout, `README.md` with the ROS-side checklist | manual |

---

## 6. ROS-side checklist (owned by you, deliberately not in this repository)

1. **Check whether rosbridge is installed** in the ROS container:
   ```bash
   podman run --rm -it --net=host osrf/ros:jazzy-desktop-full \
     bash -lc "ls /opt/ros/jazzy/share | grep -i rosbridge"
   ```
   `osrf/ros:jazzy-desktop-full` does not ship `rosbridge_suite`, so expect no output.
   Install with `sudo apt install ros-jazzy-rosbridge-suite`, then confirm these
   services appear: `/rosbridge/topics`, `/rosbridge/services`, `/rosbridge/nodes`,
   `/rosbridge/msg_definition`. `rosapi` must run alongside `rosbridge_websocket` —
   without it the app has no introspection and no dynamic forms.
2. **Fix `LoadFile`** in the workspace: call `CreateLoadFileService()` from the
   `GCodeInterpreterNode` constructor, and hoist the parsed block vector out of the
   timer lambda into a member guarded by a mutex. As written the service is never
   registered and the lambda captures `data` by value.
3. **Add `LoadGCodeContent.srv`** (`string content` / `---` / `bool success`) plus a
   handler that writes the content to disk and reloads, so the Drawing tab works.
4. **Add a teleop node**: subscribe `sensor_msgs/msg/Joy`, publish
   `geometry_msgs/msg/PoseStamped` to `/mavros/setpoint_position/local` at 20 Hz, and
   expose `/UasDraw/{arm,offboard,land,rtl}` as `std_srvs/srv/Trigger`. Position hold
   rather than `/cmd_vel`, because a drawing drone must not drift. Arm only once the
   offboard stream has been primed for about a second.
5. **Add a fail-safe**: if no `Joy` message arrives within a timeout, hold the last
   setpoint or land. The app contributes zeroed axes on touch release and a visible
   connection indicator, but the fail-safe belongs server-side — a phone-side check is
   not a safety check.
6. **Stop the interpreter looping at end of file.** Today `count_` wraps to `0`
   forever. Add a `loop` parameter defaulting to `false`.
7. **Network**: rosbridge binds `0.0.0.0`, so anyone on that network can arm the
   drone. Keep it on a dedicated network or add authentication.

---

## 7. Known risks

| Risk | Mitigation |
|---|---|
| JDK 25 installed but Android Gradle Plugin needs 17/21 | Install JDK 21 and point Flutter at it via `flutter config --jdk-dir` |
| Android 9+ blocks cleartext `ws://` to a LAN address | `usesCleartextTraffic` in the manifest |
| Android SDK has no `cmdline-tools` | Cannot add SDK packages; the two required platforms are already present |
| Joystick latency and dropout over WiFi | Server-side timeout fail-safe, zeroed axes on release, visible link state |
| rosbridge bound to `0.0.0.0` grants full ROS control to the LAN | Dedicated network or authentication |
| ROS side still being written | Configurable bindings plus capability discovery |
