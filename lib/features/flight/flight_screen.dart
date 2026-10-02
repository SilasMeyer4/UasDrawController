import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/connection_manager.dart';
import '../../core/models/bindings.dart';

class FlightScreen extends StatefulWidget {
  const FlightScreen({super.key});

  @override
  State<FlightScreen> createState() => _FlightScreenState();
}

class _FlightScreenState extends State<FlightScreen> {
  double _x = 0;
  double _y = 0;
  double _z = 0;
  double _yaw = 0;
  bool _armed = false;
  bool _offboard = false;


  @override
  void dispose() {
    super.dispose();
  }

  void _publishJoy() {
    final cm = context.read<ConnectionManager>();
    final client = cm.client;
    if (client == null || !cm.isConnected) return;
    final b = Bindings.defaults();
    final joy = b.get(LogicalAction.joy);
    // sensor_msgs/Joy: axes [x,y,z,yaw,...], buttons empty
    client.publish(joy.topic, <String, dynamic>{
      'axes': [_x, -_y, _z, _yaw],
      'buttons': [],
    });
  }

  void _callService(LogicalAction action) {
    final cm = context.read<ConnectionManager>();
    final client = cm.client;
    if (client == null || !cm.isConnected) return;
    final b = Bindings.defaults();
    final binding = b.get(action);
    if (binding.service == null || binding.service!.isEmpty) return;
    unawaited(client.callService(binding.service!, binding.type, <String, dynamic>{}));
  }

  @override
  Widget build(BuildContext context) {
    final cm = context.watch<ConnectionManager>();
    final connected = cm.isConnected;
    return Scaffold(
      appBar: AppBar(title: const Text('Flight')),
      body: connected
          ? Column(
              children: [
                Card(
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Virtual Joystick (Mock Preview)', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: Text('X: ${_x.toStringAsFixed(2)}')),
                            Expanded(child: Text('Y: ${_y.toStringAsFixed(2)}')),
                            Expanded(child: Text('Z: ${_z.toStringAsFixed(2)}')),
                            Expanded(child: Text('Yaw: ${_yaw.toStringAsFixed(2)}')),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Slider(value: _x, min: -1, max: 1, onChanged: (v) { setState(() => _x = v); _publishJoy(); }),
                        Slider(value: _y, min: -1, max: 1, onChanged: (v) { setState(() => _y = v); _publishJoy(); }),
                        Slider(value: _z, min: -1, max: 1, onChanged: (v) { setState(() => _z = v); _publishJoy(); }),
                        Slider(value: _yaw, min: -1, max: 1, onChanged: (v) { setState(() => _yaw = v); _publishJoy(); }),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () {
                              setState(() { _x=_y=_z=_yaw=0; });
                              _publishJoy();
                            },
                            child: const Text('Center'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton(
                      onPressed: () { setState(() => _armed = !_armed); _callService(LogicalAction.arm); },
                      child: Text(_armed ? 'Disarm' : 'Arm'),
                    ),
                    ElevatedButton(
                      onPressed: () { setState(() => _offboard = !_offboard); _callService(LogicalAction.offboard); },
                      child: Text(_offboard ? 'Exit Offboard' : 'Offboard'),
                    ),
                    FilledButton(
                      onPressed: () => _callService(LogicalAction.land),
                      child: const Text('Land'),
                    ),
                    OutlinedButton(
                      onPressed: () => _callService(LogicalAction.rtl),
                      child: const Text('RTL'),
                    ),
                  ],
                ),
              ],
            )
          : const Center(child: Text('Flight — not connected')),
    );
  }
}

void unawaited(Future<void> future) {}
