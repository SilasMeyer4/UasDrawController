import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/bindings.dart';
import '../../core/rosbridge/ros_client.dart';
import '../../core/services/connection_manager.dart';

/// Manual control: a `sensor_msgs/Joy` stream at a fixed rate, plus arm /
/// offboard / land / RTL service calls resolved through the active bindings.
class FlightScreen extends StatefulWidget {
  const FlightScreen({super.key});

  /// rosbridge publishing rate while a control axis is engaged.
  static const Duration joyPeriod = Duration(milliseconds: 50);

  @override
  State<FlightScreen> createState() => _FlightScreenState();
}

class _FlightScreenState extends State<FlightScreen> {
  double _x = 0;
  double _y = 0;
  double _z = 0;
  double _yaw = 0;
  bool _engaged = false;
  Timer? _timer;
  String? _lastError;
  int _published = 0;

  /// Cached because `dispose` runs after the element is deactivated, and
  /// `context.read` is not allowed to walk the tree from there.
  ConnectionManager? _cm;

  /// Set while `dispose` runs, where `mounted` is still true.
  bool _disposing = false;

  @override
  void initState() {
    super.initState();
    _cm?.addListener(_onConnectionChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = context.read<ConnectionManager>();
    if (identical(next, _cm)) return;
    _cm?.removeListener(_onConnectionChanged);
    _cm = next..addListener(_onConnectionChanged);
  }

  @override
  void dispose() {
    _cm?.removeListener(_onConnectionChanged);
    _cm = null;
    // `mounted` is still true inside dispose, so guard the setState calls
    // explicitly: Flutter forbids rebuilding an element being unmounted.
    _disposing = true;
    _stop();
    super.dispose();
  }

  void _onConnectionChanged() {
    if (_cm?.isConnected != true) {
      _stop();
      if (mounted) {
        setState(() {
          _engaged = false;
          _x = _y = _z = _yaw = 0;
        });
      }
    }
  }

  /// Starts publishing Joy at a fixed rate. rosbridge needs the topic to be
  /// advertised first; [RosClient.publish] does that on the first message.
  void _start() {
    if (!mounted || _disposing) return;
    _timer ??= Timer.periodic(
      FlightScreen.joyPeriod,
      (_) => unawaited(_publishJoy()),
    );
    if (!_engaged) setState(() => _engaged = true);
    unawaited(_publishJoy());
  }

  /// Resets the axes and publishes one all-zero sample so the ROS side sees
  /// the controls neutral instead of holding the last value forever.
  ///
  /// Deliberately usable from [dispose]: it only touches [_cm] and state, and
  /// never reads the element tree.
  void _stop() {
    _timer?.cancel();
    _timer = null;
    _x = _y = _z = _yaw = 0;
    if (mounted && !_disposing) {
      setState(() => _engaged = false);
    }
    unawaited(_publishJoy());
  }

  Future<void> _publishJoy() async {
    final cm = _cm;
    final client = cm?.client;
    final binding = cm?.profile?.bindings.get(LogicalAction.joy);
    if (client == null || binding == null || !client.isConnected) return;
    try {
      await client.publish(
        binding.name,
        <String, dynamic>{
          'axes': <double>[_x, -_y, _z, _yaw],
          'buttons': <int>[],
        },
        type: binding.type,
      );
      _published++;
      // Rebuild roughly twice a second instead of on every 20 Hz sample.
      if (mounted && !_disposing && _published % 20 == 0) setState(() {});
    } on Object catch (err) {
      if (mounted && !_disposing) setState(() => _lastError = err.toString());
    }
  }

  void _setAxis(int index, double value) {
    setState(() {
      switch (index) {
        case 0:
          _x = value;
        case 1:
          _y = value;
        case 2:
          _z = value;
        case 3:
          _yaw = value;
      }
      _lastError = null;
    });
    _start();
  }

  Future<void> _invoke(
    LogicalAction action, {
    Map<String, dynamic> extra = const <String, dynamic>{},
  }) async {
    final cm = context.read<ConnectionManager>();
    final client = cm.client;
    final binding = cm.profile?.bindings.get(action);
    if (client == null || binding == null) return;
    if (!binding.isService) {
      setState(() => _lastError = '${binding.name} is a topic, not a service');
      return;
    }
    setState(() => _lastError = null);
    try {
      final response = await client.callService(
        binding.name,
        binding.type,
        binding.argsWith(extra),
      );
      if (!mounted) return;
      final values = response['values'];
      final result = values is Map<String, dynamic>
          ? values['operation_result']
          : null;
      final ok = result is Map<String, dynamic>
          ? result['was_successful'] == true
          : values is Map<String, dynamic> && values['success'] != false;
      final message = result is Map<String, dynamic>
          ? result['message']
          : (values is Map<String, dynamic> ? values['message'] : null);
      if (!ok) {
        setState(() => _lastError = message is String && message.isNotEmpty
            ? message
            : '${binding.name} reported failure');
      }
    } on RosServiceCallException catch (err) {
      if (mounted) setState(() => _lastError = err.reason);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cm = context.watch<ConnectionManager>();
    if (!cm.isConnected) {
      return Scaffold(
        appBar: AppBar(title: const Text('Flight')),
        body: const Center(child: Text('Flight - not connected')),
      );
    }

    final joy = cm.profile?.bindings.get(LogicalAction.joy);
    final rate = (1000 / FlightScreen.joyPeriod.inMilliseconds).round();

    return Scaffold(
      appBar: AppBar(title: const Text('Flight')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    joy == null
                        ? 'No joystick binding'
                        : '${joy.name}\n'
                            'sensor_msgs/msg/Joy @ $rate Hz '
                            '(${_engaged ? 'streaming' : 'idle'}), '
                            '$_published samples sent',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  _axis(0, 'X', _x),
                  _axis(1, 'Y', _y),
                  _axis(2, 'Z', _z),
                  _axis(3, 'Yaw', _yaw),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton.tonal(
                        onPressed: () => setState(() {
                          _x = _y = _z = _yaw = 0;
                        }),
                        child: const Text('Centre'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _engaged ? _stop : _start,
                        child: Text(_engaged ? 'Stop streaming' : 'Start streaming'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Vehicle commands', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _commandButton('Arm', LogicalAction.arm,
                  enabled: cm.isAvailable(LogicalAction.arm)),
              _commandButton('Offboard', LogicalAction.offboard,
                  enabled: cm.isAvailable(LogicalAction.offboard)),
              _commandButton('Land', LogicalAction.land,
                  enabled: cm.isAvailable(LogicalAction.land)),
              _commandButton('RTL', LogicalAction.rtl,
                  enabled: cm.isAvailable(LogicalAction.rtl)),
            ],
          ),
          if (_lastError != null) ...[
            const SizedBox(height: 12),
            Text(_lastError!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
    );
  }

  Widget _axis(int index, String label, double value) => Row(
        children: [
          SizedBox(width: 44, child: Text(label)),
          Expanded(
            child: Slider(
              value: value,
              min: -1,
              max: 1,
              onChanged: (v) => _setAxis(index, v),
              onChangeEnd: (_) => _stop(),
            ),
          ),
          SizedBox(width: 48, child: Text(value.toStringAsFixed(2))),
        ],
      );

  Widget _commandButton(
    String label,
    LogicalAction action, {
    required bool enabled,
    Map<String, dynamic> extra = const <String, dynamic>{},
  }) {
    final cm = context.read<ConnectionManager>();
    final binding = cm.profile?.bindings.get(action);
    final missing = binding == null || !binding.isService;
    return ElevatedButton(
      onPressed: enabled && !missing ? () => _invoke(action, extra: extra) : null,
      child: Text(label),
    );
  }
}