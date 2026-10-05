import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/log_entry.dart';
import '../../core/services/connection_manager.dart';
import '../../core/services/log_store.dart';

/// Tail of the `/rosout` topic.
///
/// The list is reversed and virtualised: index 0 is the newest record, so new
/// lines stay at the bottom without the viewport jumping while the user reads
/// older ones, and only the handful of rows on screen are built.
class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  @override
  void initState() {
    super.initState();
    // The store has to start listening as soon as the tab exists, otherwise a
    // connection made before the first visit would not be picked up.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<LogStore>().attach(context.read<ConnectionManager>());
    });
  }

  @override
  Widget build(BuildContext context) {
    final cm = context.watch<ConnectionManager>();
    final store = context.watch<LogStore>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs'),
        actions: [
          IconButton(
            tooltip: 'Clear log',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: store.retainedCount == 0 ? null : store.clear,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 16, right: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _summary(store),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          _severityFilter(store),
          const Divider(height: 1),
          Expanded(
            child: store.visibleCount == 0
                ? _empty(cm)
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: store.visibleCount,
                    itemBuilder: (context, index) =>
                        _LogRow(entry: store.visibleAt(index)),
                  ),
          ),
        ],
      ),
    );
  }

  static String _summary(LogStore store) {
    final buffer = <String>[
      '${store.visibleCount} shown',
      '${store.retainedCount} buffered',
    ];
    if (store.pendingCount > 0) buffer.add('${store.pendingCount} queued');
    if (store.droppedCount > 0) buffer.add('${store.droppedCount} dropped');
    return buffer.join('  -  ');
  }

  Widget _severityFilter(LogStore store) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            _chip(store, null, 'All'),
            _chip(store, LogSeverity.debug, 'Debug'),
            _chip(store, LogSeverity.info, 'Info'),
            _chip(store, LogSeverity.warn, 'Warn'),
            _chip(store, LogSeverity.error, 'Error'),
          ],
        ),
      );

  Widget _chip(LogStore store, LogSeverity? severity, String label) =>
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(
          label: Text(label),
          selected: store.minSeverity == severity,
          onSelected: (_) => store.setMinSeverity(severity),
        ),
      );

  Widget _empty(ConnectionManager cm) {
    if (!cm.isConnected) {
      return const Center(child: Text('Logs - not connected'));
    }
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Waiting for messages on /rosout.\n'
          'Log output only appears once a ROS node logs something.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// One record. Kept as its own stateless widget so the list can rebuild only the
/// rows whose data changed.
class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(entry.severity);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 74,
            child: Text(
              entry.timeLabel,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: color.withValues(alpha: 0.8),
              ),
            ),
          ),
          SizedBox(
            width: 46,
            child: Text(
              entry.severity.label,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (entry.node.isNotEmpty)
                  Text(
                    entry.node,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: Colors.blueGrey,
                    ),
                  ),
                SelectableText(
                  entry.message,
                  style: const TextStyle(fontSize: 12, height: 1.25),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Color _severityColor(LogSeverity severity) => switch (severity) {
        LogSeverity.debug => Colors.blueGrey,
        LogSeverity.info => Colors.black87,
        LogSeverity.warn => Colors.orange.shade900,
        LogSeverity.error => Colors.red.shade700,
        LogSeverity.fatal => Colors.purple.shade700,
        LogSeverity.unknown => Colors.blueGrey,
      };
}