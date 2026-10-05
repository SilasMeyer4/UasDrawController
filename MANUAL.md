# UasDrawController User Manual

> **Disclaimer:** This application was **AI-generated** and is currently **in development**. It is **not intended for general use** at this time. Use at your own risk.

This manual describes how to run, configure and use the UasDrawController application to control the [UasDraw](https://github.com/SilasMeyer4/uas-draw) ROS 2 system via rosbridge.

---

## 1. Getting Started

### 1.1 Running on Linux

Use the provided helper script (added globally to `~/bin`):

```bash
UasDrawController start        # Debug mode with hot reload
UasDrawController run-release  # Build release and run
UasDrawController build        # Build release only
./build/linux/x64/release/bundle/uasdraw  # Run release directly
```

### 1.2 Running on Android

1. Enable USB debugging on your Android device
2. Connect via USB
3. Open Android Studio → `File → Open` → `/home/silas/ros2_workspace/UasDraw/UasDrawControllerApp/`
4. Select your device and press ▶ Run
5. Or via CLI: `flutter devices && flutter run -d <device-id>`

### 1.3 Mock Mode (No ROS Required)

The app includes a built-in simulation backend (`MockTransport`). Use the **"Mock (Simulation)"** profile in the Connect screen to test the UI without a running ROS system. This is ideal for development and familiarization.

---

## 2. Main Screens

The app uses a bottom navigation bar with four screens: **Connect**, **Diagnostics**, **Drawing**, **Flight**.

### 2.1 Connect

**Purpose:** Manage connection profiles and connect to your ROS 2 system.

- **Mock (Simulation)** — Offline demo with synthetic telemetry and mock rosbridge responses
- **SITL / Workstation** — Defaults to `ws://localhost:9090` (for running rosbridge on your PC/container)
- **Drone (LAN)** — Defaults to `ws://192.168.1.10:9090` (adjust to your Raspberry Pi's IP address)

**How to connect:**
1. Select the desired profile by tapping it
2. The app will attempt to connect to rosbridge on port `9090`
3. Connection status is indicated by a green link icon next to the active profile
4. If connection fails, an error message is shown below the list

**Notes:**
- The app expects `rosbridge_websocket` to be running on the target host (port 9090)
- Cleartext WebSocket (`ws://`) is permitted on Android for LAN addresses (configured via `network_security_config.xml`)
- All ROS names are configurable via bindings (not hardcoded)

### 2.2 Diagnostics

**Purpose:** Inspect the live ROS graph and view available nodes/topics/services.

**What you see:**
- **Connected/Profile** — Current connection state and active profile
- **Counters** — Number of nodes, topics, and services discovered via `rosapi`
- **Nodes** — List of all running ROS 2 nodes
- **Topics** — List of published topics with their names
- **Services** — List of available services

**Usage:**
- Refreshes automatically after connecting
- Use this screen to verify that `rosapi`, `rosbridge_websocket`, your UasDraw nodes, and (if present) MAVROS are all discoverable
- If expected services like `/UasDraw/arm` or `/UasDraw/load_gcode_content` are missing, they will also be missing from the other screens (capability discovery disables unavailable features)

### 2.3 Drawing

**Purpose:** Upload G-code files for drawing, and monitor live drawing data.

**Workflow:**
1. Press **Load G-Code** and pick a `.gcode` file (Linux/Android file picker)
2. The app calls the service bound to *Load G-Code Content*
   (default `uas_draw_interfaces/srv/LoadGCodeContent`, request field `content: string`)
3. The response is `uas_draw_interfaces/Result` with an `operation_result` field;
   failures (for example empty G-code) are surfaced in the status line
4. The screen subscribes to *Draw Data*
   (default `uas_draw_interfaces/msg/UasDrawDataBlock` on `/UasDraw/uas_draw/data`)
   and shows live `is_drawing` state, position, update count and timestamp

The **Load G-Code** button is disabled when capability discovery does not find
the service in the live graph, so you get "service not found" instead of a
timeout.

**Note:** the ROS side must actually register `/UasDraw/load_gcode_content` for
upload to work. No such node has been confirmed in the current workspace
(see Section 4).

### 2.4 Flight

**Purpose:** Manual teleoperation and vehicle control.

**Controls (implemented):**
- **Virtual Joystick** — Two-axis pad publishing `sensor_msgs/msg/Joy` to the bound
  Joy topic (default `/UasDraw/joy`) at **20 Hz** while a control is engaged.
  Axes are zeroed and one all-zero sample is published when you release, or when
  the connection drops.
- **Vehicle Commands** — Arm, Offboard, Land, RTL buttons, each mapped to a service
  call. Buttons are disabled when capability discovery cannot find the service.

> **Safety:** these buttons send immediately. There is **no hold-to-confirm
> interlock** in the current version. Do not use the app for arming until that
> interlock exists, and always keep a physical kill switch in reach.

**Telemetry:** not yet implemented.

**Safety Notes:**
- A server-side joystick timeout fail-safe is strongly recommended on the ROS
  side (the app zeroes axes on release, but cannot guarantee connectivity)
- Never rely solely on the mobile app for critical failsafes — implement them on
  the drone/Pi

---

## 3. Configuration

### 3.1 Connection Profiles

Profiles are stored persistently in the app's support directory. Defaults:
- **Mock (Simulation)**: `mock://local` (internal mock transport)
- **SITL / Workstation**: `ws://localhost:9090`
- **Drone (LAN)**: `ws://192.168.1.10:9090`

**Editing:** tap the overflow menu (⋮) on a profile card and choose **Edit** to
change the name, rosbridge URL, mock flag and bindings; **Remove** deletes it
(kept when it is the last profile). Long-pressing a card opens the editor too.
The `+` button in the app bar adds a new profile. Profiles and their binding
overrides survive restarts.

Only `ws://` and `wss://` URLs are accepted; anything else fails fast with a
clear error instead of opening a socket.

### 3.2 ROS Bindings

All logical actions map to configurable ROS names/types (see `lib/core/models/bindings.dart`). Defaults are aligned with the UasDraw namespace `/UasDraw/...`:

| Action | Type | Default Name |
|---|---|---|
| Joystick | `sensor_msgs/msg/Joy` | `/UasDraw/joy` |
| Arm | `std_srvs/srv/Trigger` | `/UasDraw/arm` |
| Offboard | `std_srvs/srv/Trigger` | `/UasDraw/offboard` |
| Land | `std_srvs/srv/Trigger` | `/UasDraw/land` |
| RTL | `std_srvs/srv/Trigger` | `/UasDraw/rtl` |
| Load G-Code Content | `uas_draw_interfaces/srv/LoadGCodeContent` | `/UasDraw/load_gcode_content` |
| Draw Data | `uas_draw_interfaces/msg/UasDrawDataBlock` | `/UasDraw/uas_draw/data` |
| Setpoint (Local) | `geometry_msgs/msg/PoseStamped` | `/mavros/setpoint_position/local` |
| Battery | `mavros_msgs/msg/BatteryState` | `/mavros/battery` |
| State | `mavros_msgs/msg/State` | `/mavros/state` |

**Presets:** switch a profile between **UasDraw** and **MAVROS (direct)** in the
profile editor. The direct preset uses the real MAVROS 2.x interfaces:

| Action | Service | Type | Notes |
|---|---|---|---|
| Arm | `/mavros/cmd/arming` | `mavros_msgs/srv/CommandBool` | `command: bool` |
| Land | `/mavros/cmd/land` | `mavros_msgs/srv/CommandTOL` | altitude in `command` |
| Offboard | `/mavros/cmd/command` | `mavros_msgs/srv/CommandLong` | `MAV_CMD_DO_SET_MODE` (176) |
| RTL | `/mavros/cmd/command` | `mavros_msgs/srv/CommandLong` | `MAV_CMD_DO_SET_MODE` (176) |

There is **no** `/mavros/set_mode` and **no** `/mavros/cmd/rtl`; mode changes go
through `MAV_CMD_DO_SET_MODE`. The preset fills in PX4 custom mode numbers, which
are firmware-specific — verify them for your PX4 build before real use. The
`/UasDraw/*` wrapper is the safer choice.

**Capability Discovery:** on connect the app queries `/rosapi/topics`,
`/rosapi/services` and `/rosapi/nodes`. If a binding's name is absent from the
graph, the matching UI controls are disabled rather than failing at call time.
Diagnostics lists every binding with its availability.

---

## 4. ROS Side Requirements

For full functionality, the UasDraw ROS system must provide:

| Requirement | Notes |
|---|---|
| `rosbridge_suite` installed | `sudo apt install ros-jazzy-rosbridge-suite`. Launch with `ros2 launch rosbridge_server rosbridge_websocket_launch.xml`, which also starts `rosapi`. |
| `/rosapi/*` services available | `/rosapi/topics`, `/rosapi/services`, `/rosapi/nodes`, `/rosapi/message_details`. These are the real names; there is no `/rosbridge/topics`. |
| `/UasDraw/uas_draw/data` topic | `uas_draw_interfaces/msg/UasDrawDataBlock`. Currently declares a nested `position` (`geometry_msgs/Point`), so the app reads `position.x/y/z`. |
| `/UasDraw/load_gcode_content` service | `uas_draw_interfaces/srv/LoadGCodeContent`, request `string content`, response `Result operation_result`. |
| (Optional) Teleop node | Subscribe to `sensor_msgs/msg/Joy`, publish position setpoints to MAVROS, expose `arm/offboard/land/rtl` as `std_srvs/srv/Trigger`. Implement a joystick timeout fail-safe server-side. |
| (Optional) MAVROS | `sudo apt install ros-jazzy-mavros ros-jazzy-mavros-msgs`, launch `mavros_node`. Provides `/mavros/battery`, `/mavros/state`, `/mavros/cmd/*`. |
| (Optional) MAVLink link | rosbridge does not talk MAVLink. You still need a MAVLink path between ROS and PX4. |

### Known workspace inconsistencies

These are unresolved in the ROS workspace and need fixing there:

- `UasDrawDataBlock.msg` defines `geometry_msgs/Point position`, but
  `gcode_interpreter_node.cpp` still assigns `message.x/y/z`.
- `load_file.hpp` is included but there is no `LoadFile.srv`.
- No node registering `/UasDraw/load_gcode_content` was found.

Until these are fixed, Drawing upload cannot work end to end. See `PLAN.md` for
the full checklist.

---

## 5. Troubleshooting

| Issue | Solution |
|---|---|
| Cannot connect to `ws://192.168.1.10:9090` on Android | Ensure phone and Pi are on the same Wi-Fi network. Cleartext is allowed, but some networks/firewalls block port 9090. Check `ufw`/iptables on the Pi. |
| App connects but services are missing | Verify `rosbridge_websocket` and `rosapi` are both running. `ros2 service list \| grep rosapi`. The UasDraw nodes may not be started yet. |
| Mock mode works but real connection fails | Test with `websocat ws://<pi>:9090` from another device to rule out network/firewall issues. |
| "ws://" URL error | Only `ws://` and `wss://` are supported. `http://` is rejected before connecting. |
| Connect hangs | rosbridge accepts the WebSocket but the ROS graph never answers; confirm `rosapi` is running. The connection has a timeout, so it should fail rather than hang. |
| Load G-Code is greyed out | Capability discovery did not find the bound service. Check `ros2 service list` for `/UasDraw/load_gcode_content`. |
| Joystick feels laggy | Reduce Wi-Fi congestion, prefer 5 GHz if available. The app publishes Joy at 20 Hz while touched; network latency is expected. |
| Android APK won't install (sideload) | Enable "Install unknown apps" for your file manager/app installer. |

---

## 6. Development Notes

- **Versioning:** `pubspec.yaml` (semantic versioning). Tags `vX.Y.Z` trigger automated releases via GitHub Actions.
- **CI/CD:** On push/PR → `flutter analyze` + `flutter test`. On tag → build Linux (`.tar.gz`) + Android (split APKs + AAB) and attach to GitHub Release.
- **Architecture:** Transport abstraction (`RosTransport`) with `WebSocketTransport`
  and `MockTransport`, rosbridge v2 protocol handling, minimal ROSDRV introspection
  parser, capability discovery via `/rosapi`.
- **Tests:** `flutter test` covers the client, transports, bindings/profiles and
  screens. Widget-test teardown uses `addTearDown`, because `testWidgets` runs the
  body in a `fake_async` zone where awaiting `disconnect()` would never complete.
- **Generated by AI:** This application was created with AI assistance as part of an exploratory/bachelor thesis workflow. It is in active development and not production-ready.

---

## 7. Support & Links

- **UasDraw ROS Repository:** [https://github.com/SilasMeyer4/uas-draw](https://github.com/SilasMeyer4/uas-draw) (private at the time of writing)
- **Controller Repository:** [https://github.com/SilasMeyer4/UasDrawController](https://github.com/SilasMeyer4/UasDrawController)
- **Releases:** [https://github.com/SilasMeyer4/UasDrawController/releases](https://github.com/SilasMeyer4/UasDrawController/releases)
- **ROS 2 rosbridge_suite:** [https://github.com/RobotWebTools/rosbridge_suite](https://github.com/RobotWebTools/rosbridge_suite)
