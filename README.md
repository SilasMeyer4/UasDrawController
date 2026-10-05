# UasDrawController

> **Disclaimer:** This application was **AI-generated** and is currently **in development**. It is **not intended for general use** at this time. Use at your own risk.

A Flutter-based mobile/desktop controller for the [UasDraw](https://github.com/SilasMeyer4/uas-draw) ROS 2 system. It provides remote control, G-code upload, telemetry and diagnostics over rosbridge WebSocket.

> Note: The [UasDraw](https://github.com/SilasMeyer4/uas-draw) repository is **private** at the moment.

## Features

- Cross-platform: Linux desktop + Android
- Connect to ROS 2 via `rosbridge_suite` (WebSocket)
- Named connection profiles with per-profile topic/service bindings
- Diagnostics: nodes, topics, services, and which bindings are actually present
- Drawing: G-code upload via service call (`/UasDraw/load_gcode_content`), live pen position
- Flight: virtual joystick publishing `sensor_msgs/Joy` at 20 Hz, plus vehicle commands
- Offline simulation (`MockTransport`) for development without ROS

## ROS 2 Setup

The controller speaks rosbridge, so it needs a running rosbridge server on the
drone/Pi. Default URL: `ws://<host>:9090`.

### 1. rosbridge_server

```bash
sudo apt update
sudo apt install ros-jazzy-rosbridge-suite

# Auto-start on boot:
sudo apt install ros-jazzy-ros2launch
```

```bash
ros2 launch rosbridge_server rosbridge_websocket_launch.xml
```

This also starts `rosapi`, which the app uses for introspection. Verify:

```bash
ros2 service list | grep rosapi
# /rosapi/topics
# /rosapi/services
# /rosapi/nodes
```

### 2. UasDraw workspace

Build and source the ROS workspace so the `/UasDraw/*` topics and services exist:

```bash
cd /home/silas/ros2_workspace/UasDraw/workspace
colcon build
source install/setup.bash
```

### 3. MAVROS (only needed for the direct-MAVROS binding preset)

```bash
sudo apt install ros-jazzy-mavros ros-jazzy-mavros-msgs
ros2 launch mavros mavros_node.launch
```

### 4. MAVLink and PX4

rosbridge is a ROS graph client only. For real flight you must additionally run
a MAVLink link between ROS and the flight controller. PX4 SITL plus a local
MAVLink bridge is a common setup:

```bash
# PX4 SITL (in the PX4 repo, separate terminal)
make px4_sitl_default

# MAVLink bridge to PX4's local UDP port
ros2 launch mavlink_router mavlink_router.launch
# or, to MAVROS from PX4's TCP port
ros2 run mavros mavros_node --ros-args -r fcu_url:=tcp://127.0.0.1:5760
```

Confirm MAVROS is connected before arming anything:

```bash
ros2 topic echo /mavros/state --once
```

### Running ROS in Distrobox

This project is developed inside a ROS 2 Distrobox that uses **host networking**,
so a rosbridge server inside the container is reachable from the host at
`ws://localhost:9090`. No port forwarding is required. Verify from the host:

```bash
curl -i -N -H "Connection: Upgrade" \
  -H "Upgrade: websocket" -H "Sec-WebSocket-Version: 13" \
  -H "Sec-WebSocket-Key: test" http://localhost:9090
```

## Bindings

A *binding* maps a logical action (Joy, arm, land, ...) to a real ROS name and
message type. Two presets ship with the app:

- **UasDraw** — the `/UasDraw/*` safety wrapper. Preferred.
- **MAVROS (direct)** — talks to MAVROS directly. Uses `/mavros/cmd/arming`
  (`mavros_msgs/srv/CommandBool`), `/mavros/cmd/land`
  (`mavros_msgs/srv/CommandTOL`) and `/mavros/cmd/command`
  (`mavros_msgs/srv/CommandLong`). There is no `/mavros/set_mode` or
  `/mavros/cmd/rtl`; mode changes go through `MAV_CMD_DO_SET_MODE` (176).

> The direct-MAVROS preset encodes PX4 custom mode numbers. Validate those
> against your firmware before real use. Prefer the UasDraw wrapper.

Every binding can be edited per profile from the Connect screen (long-press or
the overflow menu on a profile card).

## Quick Start (Linux)

```bash
# Install script (provided)
UasDrawController start        # run in debug
UasDrawController run-release  # build + run release
UasDrawController test         # run tests
UasDrawController analyze      # static analysis
```

## Building from Source

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
cd UasDrawControllerApp
flutter pub get
flutter run -d linux
```

## Android

Enable USB debugging and run via Android Studio (`File → Open → UasDrawControllerApp`) or `flutter run -d <device>`.

## Known Gaps

- The ROS workspace has unresolved interface inconsistencies: `UasDrawDataBlock`
  declares a nested `position`, while the interpreter node still writes
  `message.x/y/z`, and the `LoadFile` service definition is missing.
- No `/UasDraw/load_gcode_content` service node has been confirmed.
- Flight-command buttons send immediately; there is **no** hold-to-confirm
  interlock yet. Do not rely on the app for arming until that is in place.
- No end-to-end test against a live rosbridge server or real PX4 has been run.

## Development Status

This project is under active development. APIs, bindings and UI are subject to change without notice.

## Tests

```bash
flutter analyze
flutter test
```

## License

MIT License — see [LICENSE](LICENSE) for details.
