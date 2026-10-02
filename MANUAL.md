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

**Purpose:** Upload and manage G-code files for drawing, and monitor the current drawing data block.

**Current State (v0.0.1):**
- Basic scaffold screen is present
- Full functionality (file picker, G-code content upload via service call, remote file list, live `UasDrawDataBlock` readout) is planned per `PLAN.md` and will be added in upcoming releases

**Planned Workflow (when implemented):**
1. Select a `.gcode` file from your device (Linux/Android file picker)
2. Upload the file content as text via the service call `/UasDraw/load_gcode_content` (type `uas_draw_interfaces/srv/LoadGCodeContent`, request field `content: string`)
3. Monitor live messages on `/UasDraw/uas_draw/data` (`uas_draw_interfaces/msg/UasDrawDataBlock`)
4. View drawing progress/state (`is_drawing`, position `x,y,z`, type constants)

**Note:** The ROS side must implement `/UasDraw/load_gcode_content` for the upload to work (see Section 4).

### 2.4 Flight

**Purpose:** Manual teleoperation and vehicle control.

**Current State (v0.0.1):**
- Basic scaffold screen is present
- Full implementation (virtual dual-thumb joystick, Joy publishing at 20 Hz, arm/offboard/land/RTL with hold-to-confirm, telemetry) is planned

**Planned Controls (when implemented):**
- **Virtual Joystick** — Dual-thumb control, publishes `sensor_msgs/msg/Joy` to the configured Joy topic (default `/UasDraw/joy`) while touched, axes zeroed on release
- **Max Rate Sliders** — Adjust linear/angular rate limits
- **Vehicle Commands** — Arm, Offboard, Land, RTL with **hold-to-confirm** (safety)
- **Telemetry** — Battery, mode, armed status from `/mavros/battery` and `/mavros/state` (if MAVROS present)

**Safety Notes:**
- A server-side joystick timeout fail-safe is strongly recommended on the ROS side (the app zeroes axes on release, but cannot guarantee network connectivity)
- Never rely solely on the mobile app for critical failsafes — implement them on the drone/Pi

---

## 3. Configuration

### 3.1 Connection Profiles

Profiles are stored persistently in the app's support directory. Defaults:
- **Mock (Simulation)**: `ws://mock://local` (internal mock transport)
- **SITL / Workstation**: `ws://localhost:9090`
- **Drone (LAN)**: `ws://192.168.1.10:9090`

To change the drone IP, edit the profile in the Connect screen (future versions will add an edit UI; for now, profiles are managed via the defaults store in code if you need custom defaults).

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
| Setpoint (Local) | `geometry_msgs/msg/PoseStamped` | `/mavros/setpoint_position/local` |
| Battery | `mavros_msgs/msg/BatteryState` | `/mavros/battery` |
| State | `mavros_msgs/msg/State` | `/mavros/state` |

**Capability Discovery:** On connect, the app queries `/rosbridge/topics` and `/rosbridge/services` via `rosapi`. If a binding's service/topic is not present, the corresponding UI controls are disabled (grayed out with "service not found") instead of crashing.

---

## 4. ROS Side Requirements

For full functionality, the UasDraw ROS system must provide:

| Requirement | Notes |
|---|---|
| `rosbridge_suite` installed | `sudo apt install ros-jazzy-rosbridge-suite` on the Pi/container. `rosapi` must run alongside `rosbridge_websocket`. |
| `/rosbridge/*` services available | `/rosbridge/topics`, `/rosbridge/services`, `/rosbridge/nodes`, `/rosbridge/msg_definition` (provided by `rosapi`). |
| `/UasDraw/load_gcode_content` service | Type `uas_draw_interfaces/srv/LoadGCodeContent` with `string content` request and `bool success` response. This is the upload mechanism used by the Drawing screen. |
| (Optional) Teleop node | Subscribe to `sensor_msgs/msg/Joy`, publish position setpoints to MAVROS, expose `arm/offboard/land/rtl` as `std_srvs/srv/Trigger`. Implement a joystick timeout fail-safe server-side. |
| (Optional) MAVROS | For real drone control: `/mavros/battery`, `/mavros/state`, `/mavros/setpoint_position/local` must be available. |

See `PLAN.md` (in this repository) for the detailed ROS-side checklist and known gaps in the current workspace.

---

## 5. Troubleshooting

| Issue | Solution |
|---|---|
| Cannot connect to `ws://192.168.1.10:9090` on Android | Ensure phone and Pi are on the same Wi-Fi network. Cleartext is allowed, but some networks/firewalls block port 9090. Check `ufw`/iptables on the Pi. |
| App connects but services are missing | Verify `rosbridge_websocket` and `rosapi` are both running. Check `ros2 service list` on the Pi. The UasDraw nodes may not be started yet. |
| Mock mode works but real connection fails | Test with `websocat ws://<pi>:9090` from another device to rule out network/firewall issues. |
| Joystick feels laggy | Reduce Wi-Fi congestion, prefer 5 GHz if available. The app publishes Joy at 20 Hz while touched; network latency is expected. |
| Android APK won't install (sideload) | Enable "Install unknown apps" for your file manager/app installer. |

---

## 6. Development Notes

- **Versioning:** `pubspec.yaml` (semantic versioning). Tags `vX.Y.Z` trigger automated releases via GitHub Actions.
- **CI/CD:** On push/PR → `flutter analyze` + `flutter test`. On tag → build Linux (`.tar.gz`) + Android (split APKs + AAB) and attach to GitHub Release.
- **Architecture:** Transport abstraction (`RosTransport`) with `WebSocketTransport` and `MockTransport`, rosbridge v2 protocol codec, minimal ROSDRV introspection parser, capability discovery via `rosapi`.
- **Generated by AI:** This application was created with AI assistance as part of an exploratory/bachelor thesis workflow. It is in active development and not production-ready.

---

## 7. Support & Links

- **UasDraw ROS Repository:** [https://github.com/SilasMeyer4/uas-draw](https://github.com/SilasMeyer4/uas-draw) (private at the time of writing)
- **Controller Repository:** [https://github.com/SilasMeyer4/UasDrawController](https://github.com/SilasMeyer4/UasDrawController)
- **Releases:** [https://github.com/SilasMeyer4/UasDrawController/releases](https://github.com/SilasMeyer4/UasDrawController/releases)
- **ROS 2 rosbridge_suite:** [https://github.com/RobotWebTools/rosbridge_suite](https://github.com/RobotWebTools/rosbridge_suite)
