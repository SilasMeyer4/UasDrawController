import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/connection_manager.dart';
import '../../core/models/bindings.dart';

class DrawingScreen extends StatefulWidget {
  const DrawingScreen({super.key});

  @override
  State<DrawingScreen> createState() => _DrawingScreenState();
}

class _DrawingScreenState extends State<DrawingScreen> {
  String _status = 'Idle';
  double _x = 0, _y = 0, _z = 0;
  bool _drawing = false;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    final cm = context.read<ConnectionManager>();
    cm.client?.messages.listen((msg) {
      if (msg['op'] != 'publish') return;
      if (msg['topic'] != '/UasDraw/uas_draw/data') return;
      final m = msg['msg'] as Map<String, dynamic>?;
      if (m == null || !mounted) return;
      setState(() {
        _x = (m['x'] as num?)?.toDouble() ?? 0;
        _y = (m['y'] as num?)?.toDouble() ?? 0;
        _z = (m['z'] as num?)?.toDouble() ?? 0;
        _drawing = (m['is_drawing'] as bool?) ?? false;
        _status = _drawing ? 'Drawing' : 'Travel';
      });
    });
  }

  Future<void> _loadDemo() async {
    final cm = context.read<ConnectionManager>();
    final client = cm.client;
    if (client == null) return;
    final b = Bindings.defaults();
    final binding = b.get(LogicalAction.loadGcodeContent);
    if (binding.service == null) return;
    await client.callService(binding.service!, binding.type, <String, dynamic>{
      'content': 'G21\nG90\nF500\nG00 X0 Y0 Z0\nG01 X10 Y0 Z-1\nG01 X10 Y10 Z-1\nG01 X0 Y10 Z-1\nG01 X0 Y0 Z-1\nG00 X0 Y0 Z0\n',
    });
    if (mounted) setState(() => _status = 'Demo G-code loaded');
  }

  @override
  Widget build(BuildContext context) {
    final cm = context.watch<ConnectionManager>();
    return Scaffold(
      appBar: AppBar(title: const Text('Drawing')),
      body: cm.isConnected
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: ListTile(
                      title: Text('Status: $_status'),
                      subtitle: Text('X=${_x.toStringAsFixed(2)} Y=${_y.toStringAsFixed(2)} Z=${_z.toStringAsFixed(2)} • Drawing=$_drawing'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadDemo,
                    child: const Text('Load Demo G-Code (Mock)'),
                  ),
                  const SizedBox(height: 8),
                  const Text('Mock publishes /UasDraw/uas_draw/data every 500ms; values above update live.'),
                ],
              ),
            )
          : const Center(child: Text('Drawing — not connected')),
    );
  }
}
