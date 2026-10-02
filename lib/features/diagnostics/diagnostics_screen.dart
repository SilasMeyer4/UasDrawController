import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/connection_manager.dart';

class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cm = context.watch<ConnectionManager>();
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostics')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _kv('Connected', cm.isConnected.toString()),
          if (cm.profile != null) _kv('Profile', cm.profile!.name),
          _kv('Nodes', cm.graph.nodes.length.toString()),
          _kv('Topics', cm.graph.topics.length.toString()),
          _kv('Services', cm.graph.services.length.toString()),
          const SizedBox(height: 16),
          const Text('Nodes', style: TextStyle(fontWeight: FontWeight.bold)),
          ...cm.graph.nodes.map((n) => Text(n)),
          const SizedBox(height: 12),
          const Text('Topics', style: TextStyle(fontWeight: FontWeight.bold)),
          ...cm.graph.topics.map((t) => Text(t)),
          const SizedBox(height: 12),
          const Text('Services', style: TextStyle(fontWeight: FontWeight.bold)),
          ...cm.graph.services.map((s) => Text(s)),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [Text('$k: '), Text(v, style: const TextStyle(fontWeight: FontWeight.bold))],
      ),
    );
  }
}
