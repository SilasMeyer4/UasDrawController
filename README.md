# UasDrawController

> **Disclaimer:** This application was **AI-generated** and is currently **in development**. It is **not intended for general use** at this time. Use at your own risk.

A Flutter-based mobile/desktop controller for the [UasDraw](https://github.com/SilasMeyer4/UasDraw) ROS 2 system. It provides remote control, G-code upload, telemetry and diagnostics over rosbridge WebSocket.

## Features

- Cross-platform: Linux desktop + Android
- Connect to ROS 2 via `rosbridge_suite` (WebSocket)
- Diagnostics: nodes, topics, services, live topic viewer
- Drawing: G-code upload via service call (`/UasDraw/load_gcode_content`)
- Flight: virtual joystick publishing `sensor_msgs/Joy`, vehicle commands (arm/offboard/land/RTL) with hold-to-confirm
- Offline simulation (`MockTransport`) for development without ROS

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

## ROS 2 Requirements

The controller expects a running `rosbridge_websocket` on the drone/Pi (default `ws://<host>:9090`). For full functionality, the UasDraw ROS workspace must expose the expected topics/services (see `PLAN.md` for the ROS-side checklist).

## Development Status

This project is under active development. APIs, bindings and UI are subject to change without notice.

## License

MIT License — see [LICENSE](LICENSE) for details.
