import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/bindings.dart';
import '../../core/services/connection_manager.dart';

/// ROS graph snapshot plus per-binding capability discovery, so it is obvious
/// which app actions the connected ROS system can actually serve.
class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cm = context.watch<ConnectionManager>();
    final graph = cm.graph;
    final bindings = cm.profile?.bindings;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: [
          IconButton(
            tooltip: 'Refresh graph',
            icon: const Icon(Icons.refresh),
            onPressed: cm.isConnected ? cm.refreshGraph : null,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _kv(context, 'Connected', cm.isConnected.toString()),
          if (cm.profile != null) ...[
            _kv(context, 'Profile', cm.profile!.name),
            _kv(context, 'Endpoint',
                cm.profile!.isMock ? 'simulation' : cm.profile!.wsUrl),
            _kv(context, 'Binding preset',
                Bindings.presetName(cm.profile!.bindings)),
          ],
          if (cm.graphError != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: const Text('Introspection failed'),
                subtitle: Text(
                  '${cm.graphError}\n\n'
                  'rosbridge answers /rosapi/topics, /rosapi/services and '
                  '/rosapi/nodes. That means the rosapi node is not running: '
                  'start it with '
                  'ros2 launch rosbridge_server rosbridge_websocket_launch.xml.',
                ),
              ),
            ),
          const SizedBox(height: 8),
          _kv(context, 'Nodes', graph.nodes.length.toString()),
          _kv(context, 'Topics', graph.topics.length.toString()),
          _kv(context, 'Services', graph.services.length.toString()),
          if (bindings != null) ...[
            const SizedBox(height: 16),
            Text('Bindings', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            for (final action in LogicalAction.values)
              _bindingTile(context, cm, action),
          ],
          const SizedBox(height: 16),
          _section(context, 'Nodes', graph.describeNodes),
          _section(context, 'Topics', graph.describeTopics()),
          _section(context, 'Services', graph.describeServices()),
        ],
      ),
    );
  }

  Widget _bindingTile(
    BuildContext context,
    ConnectionManager cm,
    LogicalAction action,
  ) {
    final binding = cm.profile?.bindings.get(action);
    if (binding == null) return const SizedBox.shrink();
    final available = cm.isAvailable(action);
    return ListTile(
      dense: true,
      leading: Icon(
        available ? Icons.check_circle_outline : Icons.remove_circle_outline,
        size: 18,
        color: available ? Colors.green : Colors.orange,
      ),
      title: Text(action.name, style: const TextStyle(fontSize: 13)),
      subtitle: Text(
        '${_kindLabel(binding)}  ${binding.name}\n'
        '${binding.type}',
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
      ),
    );
  }

  /// Actions cannot be verified through rosapi, so say so instead of implying
  /// the graph check covered them.
  static String _kindLabel(Binding binding) => switch (binding.kind) {
        BindingKind.topic => 'topic',
        BindingKind.service => 'service',
        BindingKind.action => 'action',
      };

  Widget _kv(BuildContext context, String key, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Text('$key: '),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      );

  Widget _section(BuildContext context, String title, List<String> lines) {
    if (lines.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        for (final line in lines)
          Text(line, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
      ],
    );
  }
}