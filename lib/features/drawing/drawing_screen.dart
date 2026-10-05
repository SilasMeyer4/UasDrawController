import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/bindings.dart';
import '../../core/rosbridge/ros_client.dart';
import '../../core/services/connection_manager.dart';
import '../../core/services/drawing_commands.dart';

/// Live view of `/uas_draw/data`, G-code upload, and the buttons that drive the
/// `uas_draw_interfaces` services and the `DrawPicture` action.
class DrawingScreen extends StatefulWidget {
  const DrawingScreen({super.key});

  @override
  State<DrawingScreen> createState() => _DrawingScreenState();
}

class _DrawingScreenState extends State<DrawingScreen> {
  StreamSubscription<Map<String, dynamic>>? _sub;
  RosClient? _subClient;
  String? _dataTopic;
  String? _bufferTopic;
  double _x = 0;
  double _y = 0;
  double _z = 0;
  double _speed = 0;
  bool _isDrawing = false;
  int _updateCount = 0;
  DateTime? _lastUpdate;
  String _status = 'Waiting for data';
  String? _lastError;

  /// Free slots reported by `BufferStatus`, `null` until the first message.
  int? _freeCapacity;

  /// Outgoing command state.
  DrawingPen _pen = const DrawingPen();
  DrawingCanvas _canvas = const DrawingCanvas();
  bool _scalePicture = true;
  GeometryPoint? _home;
  GeometryPoint? _origin;
  String? _commandStatus;

  /// `DrawPicture` goal in flight, plus its latest feedback.
  RosActionGoal? _goal;
  StreamSubscription<Map<String, dynamic>>? _goalSub;
  DrawPictureFeedback? _feedback;

  /// Cached because `dispose` runs after the element is deactivated, and
  /// `context.read` is not allowed to walk the tree from there.
  ConnectionManager? _cm;

  @override
  void initState() {
    super.initState();
    // The client only exists once a connection is up, so hook the manager
    // rather than reaching for `context.read<...>().client` right here.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncSubscription());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = context.read<ConnectionManager>();
    if (identical(next, _cm)) return;
    _cm?.removeListener(_syncSubscription);
    _cm = next..addListener(_syncSubscription);
  }

  @override
  void dispose() {
    _cm?.removeListener(_syncSubscription);
    _cm = null;
    unawaited(_goalSub?.cancel());
    _goalSub = null;
    final client = _subClient;
    if (client != null) {
      // Only this screen's topics: the client is shared, and unsubscribing
      // everything would take `/rosout` and the joystick stream down with it.
      for (final topic in <String?>{_dataTopic, _bufferTopic}) {
        if (topic != null && topic.isNotEmpty) {
          unawaited(client.unsubscribe(topic));
        }
      }
    }
    unawaited(_sub?.cancel());
    _sub = null;
    _subClient = null;
    super.dispose();
  }

  void _syncSubscription() {
    final cm = _cm;
    if (cm == null || !mounted) return;
    final dataBinding = _dataBinding(cm);
    final topic = dataBinding?.name;

    if (!cm.isConnected || topic == null || topic.isEmpty) {
      _stopListening();
      return;
    }
    if (_sub != null && _dataTopic == topic) return;

    _stopListening();
    final client = cm.client;
    if (client == null) return;
    _dataTopic = topic;
    _subClient = client;
    _sub = client.messages.listen(_onMessage);
    unawaited(
      client.subscribe(topic, dataBinding!.type, throttleRate: 1000),
    );

    // Optional: the buffer gauge is a nice-to-have, not a reason to skip the
    // data subscription when the node does not publish it.
    final buffer = cm.profile?.bindings.get(LogicalAction.bufferStatus);
    if (buffer != null && buffer.name.isNotEmpty) {
      _bufferTopic = buffer.name;
      unawaited(client.subscribe(buffer.name, buffer.type, throttleRate: 1000));
    }
  }

  Binding? _dataBinding(ConnectionManager cm) =>
      cm.profile?.bindings.get(LogicalAction.drawData);

  void _stopListening() {
    final sub = _sub;
    _sub = null;
    _subClient = null;
    _dataTopic = null;
    _bufferTopic = null;
    unawaited(sub?.cancel());
  }

  void _onMessage(Map<String, dynamic> frame) {
    if (frame['op'] != 'publish') return;
    final topic = frame['topic'];
    if (topic != _dataTopic && topic != _bufferTopic) return;
    final msg = frame['msg'];
    if (msg is! Map<String, dynamic> || !mounted) return;

    if (topic == _bufferTopic) {
      final free = msg['free_capacity'];
      if (free is num) setState(() => _freeCapacity = free.toInt());
      return;
    }

    setState(() {
      final position = _point(msg['position']) ??
          _point(msg) ??
          const <String, dynamic>{};
      _x = _double(position['x']);
      _y = _double(position['y']);
      _z = _double(position['z']);
      _speed = _double(msg['speed_in_ms']);
      _isDrawing = msg['is_drawing'] == true;
      _updateCount++;
      _lastUpdate = DateTime.now();
      _status = _isDrawing ? 'Drawing' : 'Travelling';
    });
  }

  static Map<String, dynamic>? _point(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    if (!raw.containsKey('x') && !raw.containsKey('y') && !raw.containsKey('z')) {
      return null;
    }
    return raw;
  }

  static double _double(Object? value) =>
      value is num ? value.toDouble() : 0;

  DrawingCommands? _commandsFor(ConnectionManager cm) {
    final client = cm.client;
    final bindings = cm.profile?.bindings;
    if (client == null || bindings == null) return null;
    return DrawingCommands(client: client, bindings: bindings);
  }

  /// Runs [body], funnelling both the outcome and any failure into the command
  /// status line so every button reports the same way.
  Future<void> _run(String label, Future<String> Function() body) async {
    setState(() {
      _commandStatus = '$label...';
      _lastError = null;
    });
    try {
      final message = await body();
      if (!mounted) return;
      setState(() => _commandStatus = '$label: $message');
    } on Object catch (err) {
      if (!mounted) return;
      setState(() {
        _commandStatus = '$label failed';
        _lastError = _reasonOf(err);
      });
    }
  }

  /// Unwraps the typed exceptions so the user sees the ROS reason rather than
  /// `Instance of 'RosServiceCallException'`.
  static String _reasonOf(Object err) => switch (err) {
        RosServiceCallException(:final reason) => reason,
        RosActionException(:final reason) => reason,
        DrawingCommandException(:final reason) => reason,
        _ => err.toString(),
      };

  Future<void> _pickFile() async {
    final cm = context.read<ConnectionManager>();
    final commands = _commandsFor(cm);
    final binding = cm.profile?.bindings.get(LogicalAction.loadGcodeContent);
    if (commands == null || binding == null) return;

    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Select a .gcode file',
      allowedExtensions: const ['gcode', 'nc', 'ngc', 'tap'],
      type: FileType.any,
    );
    if (picked.isEmpty) return;
    final file = picked.first;
    try {
      final content = utf8.decode(await file.readAsBytes());
      await _uploadGcode(commands, binding, content);
    } on Object catch (err) {
      if (!mounted) return;
      setState(() {
        _status = 'Upload failed';
        _lastError = 'Could not read ${file.name}: $err';
      });
    }
  }

  Future<void> _loadDemo() async {
    final cm = context.read<ConnectionManager>();
    final commands = _commandsFor(cm);
    final binding = cm.profile?.bindings.get(LogicalAction.loadGcodeContent);
    if (commands == null || binding == null) return;
    await _uploadGcode(commands, binding, _demoGcode);
  }

  Future<void> _uploadGcode(
    DrawingCommands commands,
    Binding binding,
    String content,
  ) async {
    setState(() {
      _status = 'Uploading g-code...';
      _lastError = null;
    });
    try {
      final response = await commands.client.callService(
        binding.name,
        binding.type,
        binding.argsWith(<String, dynamic>{'content': content}),
      );
      final result = readUasResult(response);
      setState(() {
        _status =
            result.isSuccess ? 'G-code accepted' : 'G-code rejected by the ROS node';
        if (!result.isSuccess) _lastError = result.message;
      });
    } on RosServiceCallException catch (err) {
      setState(() {
        _status = 'Upload failed';
        _lastError = err.reason;
      });
    }
  }

  Future<void> _setPen() async {
    final cm = context.read<ConnectionManager>();
    final commands = _commandsFor(cm);
    if (commands == null) return;
    await _run('Set pen', () async =>
        (await commands.setPen(_pen)).summary);
  }

  Future<void> _applyContext() async {
    final cm = context.read<ConnectionManager>();
    final commands = _commandsFor(cm);
    if (commands == null) return;
    final context_ = DrawingContext(
      canvas: _canvas,
      scalePicture: _scalePicture,
      pen: _pen,
    );
    await _run('Apply context', () async =>
        (await commands.setDrawingContext(context_)).summary);
  }

  Future<void> _setHome() async {
    final cm = context.read<ConnectionManager>();
    final commands = _commandsFor(cm);
    if (commands == null) return;
    await _run('Set home', () async {
      final point = await commands.setHome();
      if (!mounted) return point?.toString() ?? 'no position returned';
      setState(() => _home = point);
      return point?.toString() ?? 'no position returned';
    });
  }

  Future<void> _setOrigin() async {
    final cm = context.read<ConnectionManager>();
    final commands = _commandsFor(cm);
    if (commands == null) return;
    await _run('Set origin', () async {
      final point = await commands.setOrigin();
      if (!mounted) return point?.toString() ?? 'no position returned';
      setState(() => _origin = point);
      return point?.toString() ?? 'no position returned';
    });
  }

  Future<void> _drawPicture() async {
    final cm = context.read<ConnectionManager>();
    final commands = _commandsFor(cm);
    if (commands == null) return;

    setState(() {
      _commandStatus = 'Draw picture...';
      _lastError = null;
      _feedback = null;
    });

    final RosActionGoal goal;
    try {
      goal = await commands.drawPicture();
    } on Object catch (err) {
      if (!mounted) return;
      setState(() {
        _commandStatus = 'Draw picture failed';
        _lastError = _reasonOf(err);
      });
      return;
    }
    if (!mounted) {
      await goal.cancel();
      return;
    }

    setState(() => _goal = goal);
    // Subscribe before awaiting the result: feedback frames that arrive while
    // we are waiting would otherwise be dropped.
    unawaited(_goalSub?.cancel());
    _goalSub = goal.feedback.listen((values) {
      if (!mounted) return;
      setState(() => _feedback = DrawPictureFeedback.fromJson(values));
    });

    try {
      final values = await goal.result;
      if (!mounted) return;
      final result = readUasResult(<String, dynamic>{'values': values});
      setState(() {
        _commandStatus = result.isSuccess ? 'Picture drawn' : 'Picture failed';
        if (!result.isSuccess) _lastError = result.message;
      });
    } on Object catch (err) {
      if (!mounted) return;
      setState(() {
        _commandStatus = 'Picture failed';
        _lastError = _reasonOf(err);
      });
    } finally {
      unawaited(_goalSub?.cancel());
      _goalSub = null;
      if (mounted) setState(() => _goal = null);
    }
  }

  Future<void> _cancelGoal() async {
    final goal = _goal;
    if (goal == null) return;
    setState(() => _commandStatus = 'Cancelling...');
    try {
      await goal.cancel();
    } on Object catch (err) {
      if (!mounted) return;
      setState(() => _lastError = _reasonOf(err));
    }
  }

  static const String _demoGcode = '''
G21
G90
F500
G00 X0 Y0 Z0
G01 X10 Y0 Z-1
G01 X10 Y10 Z-1
G01 X0 Y10 Z-1
G01 X0 Y0 Z-1
G00 X0 Y0 Z0
''';

  @override
  Widget build(BuildContext context) {
    final cm = context.watch<ConnectionManager>();
    if (!cm.isConnected) {
      return Scaffold(
        appBar: AppBar(title: const Text('Drawing')),
        body: const Center(child: Text('Drawing - not connected')),
      );
    }

    final binding = cm.profile?.bindings.get(LogicalAction.loadGcodeContent);
    final canUpload = binding != null && cm.isAvailable(LogicalAction.loadGcodeContent);
    final topic = _dataBinding(cm)?.name ?? '(unbound)';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Drawing'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 16, right: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(topic, style: Theme.of(context).textTheme.bodySmall),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _statusCard(),
          const SizedBox(height: 16),
          if (!cm.isAvailable(LogicalAction.loadGcodeContent))
            const Text(
              'The load_gcode_content service was not found in the ROS graph.',
              style: TextStyle(color: Colors.orange),
            ),
          _uploadButtons(canUpload),
          const SizedBox(height: 24),
          _penSection(cm),
          const SizedBox(height: 16),
          _contextSection(cm),
          const SizedBox(height: 16),
          _positionSection(cm),
          const SizedBox(height: 16),
          _runControlSection(cm),
          const SizedBox(height: 16),
          _drawSection(cm),
          if (_commandStatus != null) ...[
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(_commandStatus!),
              ),
            ),
          ],
          if (_lastError != null) ...[
            const SizedBox(height: 12),
            Text(_lastError!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
    );
  }

  Widget _statusCard() => Card(
        child: ListTile(
          title: Text('Status: $_status'),
          subtitle: Text(
            'X=${_x.toStringAsFixed(2)} '
            'Y=${_y.toStringAsFixed(2)} '
            'Z=${_z.toStringAsFixed(2)}  '
            'speed=${_speed.toStringAsFixed(2)} m/s  '
            'drawing=$_isDrawing\n'
            'buffer free=${_freeCapacity ?? '--'}\n'
            '$_updateCount updates'
            '${_lastUpdate == null ? '' : ' - last ${_lastUpdate!.toIso8601String()}'}',
          ),
          isThreeLine: true,
        ),
      );

  Widget _uploadButtons(bool canUpload) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ElevatedButton(
            onPressed: canUpload ? _pickFile : null,
            child: const Text('Upload .gcode'),
          ),
          OutlinedButton(
            onPressed: canUpload ? _loadDemo : null,
            child: const Text('Load demo g-code'),
          ),
        ],
      );

  /// Pen selection: `type` and `length_in_cm` sent by one `SetPen` call.
  Widget _penSection(ConnectionManager cm) => _section(
        'Pen',
        cm,
        LogicalAction.setPen,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(width: 60, child: Text('Type')),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _pen.type,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final type in knownPenTypes)
                        DropdownMenuItem<int>(
                          value: type,
                          child: Text('${penLabel(type)} ($type)'),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _pen = _pen.copyWith(type: value));
                    },
                  ),
                ),
              ],
            ),
            _slider(
              'Length',
              _pen.lengthInCm,
              min: 0.1,
              max: 20,
              unit: 'cm',
              onChanged: (v) => setState(() => _pen = _pen.copyWith(lengthInCm: v)),
            ),
          ],
        ),
        button: ('Set pen', _setPen),
      );

  /// Canvas size plus the scale flag, sent as one `SetDrawingContext`.
  Widget _contextSection(ConnectionManager cm) => _section(
        'Drawing context',
        cm,
        LogicalAction.setDrawingContext,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _slider(
              'Width',
              _canvas.widthInCm,
              min: 1,
              max: 500,
              unit: 'cm',
              onChanged: (v) =>
                  setState(() => _canvas = _canvas.copyWith(widthInCm: v)),
            ),
            _slider(
              'Height',
              _canvas.heightInCm,
              min: 1,
              max: 500,
              unit: 'cm',
              onChanged: (v) =>
                  setState(() => _canvas = _canvas.copyWith(heightInCm: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Scale picture to canvas'),
              subtitle: const Text('scale_picture'),
              value: _scalePicture,
              onChanged: (v) => setState(() => _scalePicture = v),
            ),
          ],
        ),
        button: ('Apply context', _applyContext),
      );

  /// Home and origin both answer with a `geometry_msgs/Point`.
  Widget _positionSection(ConnectionManager cm) => _section(
        'Positions',
        cm,
        LogicalAction.setHome,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _pointRow('Home', _home, LogicalAction.setHome, _setHome),
            const SizedBox(height: 8),
            _pointRow('Origin', _origin, LogicalAction.setOrigin, _setOrigin),
          ],
        ),
      );

  Widget _pointRow(
    String label,
    GeometryPoint? point,
    LogicalAction action,
    VoidCallback onPressed,
  ) {
    final cm = context.read<ConnectionManager>();
    final binding = cm.profile?.bindings.get(action);
    final ready = binding != null && cm.isAvailable(action);
    return Row(
      children: [
        Expanded(
          child: Text(
            '$label: ${point ?? 'not set'}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        OutlinedButton(
          onPressed: ready ? onPressed : null,
          child: Text('Set ${label.toLowerCase()}'),
        ),
      ],
    );
  }

  /// Pause / resume / cancel. Cancel is a plain `Trigger` so it still works
  /// when the interpreter is wedged and cannot answer a typed request.
  Widget _runControlSection(ConnectionManager cm) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Run control', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _serviceButton(cm, 'Pause', LogicalAction.pause),
                  _serviceButton(cm, 'Resume', LogicalAction.resume),
                  _serviceButton(
                    cm,
                    'Cancel drawing',
                    LogicalAction.cancelDrawing,
                    destructive: true,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Cancel aborts the running job from the node side.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );

  Widget _serviceButton(
    ConnectionManager cm,
    String label,
    LogicalAction action, {
    bool destructive = false,
  }) {
    final binding = cm.profile?.bindings.get(action);
    final ready = binding != null && cm.isAvailable(action);
    return destructive
        ? FilledButton.tonal(
            onPressed: ready ? () => _serviceCall(action, label) : null,
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(label),
          )
        : OutlinedButton(
            onPressed: ready ? () => _serviceCall(action, label) : null,
            child: Text(label),
          );
  }

  Future<void> _serviceCall(LogicalAction action, String label) async {
    final cm = context.read<ConnectionManager>();
    final commands = _commandsFor(cm);
    if (commands == null) return;
    await _run(label, () async => switch (action) {
          LogicalAction.pause => (await commands.pause()).summary,
          LogicalAction.resume => (await commands.resume()).summary,
          LogicalAction.cancelDrawing =>
            (await commands.cancelDrawing()).summary,
          _ => 'not a run-control command',
        });
  }

  /// The `DrawPicture` action: progress from feedback, abort via `action_cancel`.
  Widget _drawSection(ConnectionManager cm) {
    final binding = cm.profile?.bindings.get(LogicalAction.drawPicture);
    final ready = binding != null && cm.isAvailable(LogicalAction.drawPicture);
    final feedback = _feedback;
    final running = _goal != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Draw picture', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              binding == null
                  ? 'DrawPicture is not bound in this profile.'
                  : '${binding.name}\n${binding.type}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (running)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(value: feedback?.progress ?? 0),
                  const SizedBox(height: 8),
                  Text(
                    feedback == null
                        ? 'goal accepted, waiting for feedback'
                        : 'line ${feedback.currentLine}  '
                            '${(feedback.progress * 100).toStringAsFixed(0)}%  '
                            '${feedback.activePen ?? _pen}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: ready && !running ? _drawPicture : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Draw picture'),
                ),
                if (running)
                  OutlinedButton(
                    onPressed: _cancelGoal,
                    child: const Text('Cancel goal'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// One titled card whose single button calls a bound service, disabled with
  /// an explanation when the ROS graph does not offer it.
  Widget _section(
    String title,
    ConnectionManager cm,
    LogicalAction action,
    Widget child, {
    (String, Future<void> Function())? button,
  }) {
    final binding = cm.profile?.bindings.get(action);
    final available = cm.isAvailable(action);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                if (!available)
                  Text(
                    'unavailable',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
            if (binding != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  binding.name,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 12),
            child,
            if (button != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: ElevatedButton(
                  onPressed: available && binding != null ? button.$2 : null,
                  child: Text(button.$1),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _slider(
    String label,
    double value, {
    required double min,
    required double max,
    required String unit,
    required ValueChanged<double> onChanged,
  }) =>
      Row(
        children: [
          SizedBox(width: 60, child: Text(label)),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: ((max - min) * 10).round(),
              label: '${value.toStringAsFixed(1)} $unit',
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 68,
            child: Text(
              '${value.toStringAsFixed(1)} $unit',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      );
}