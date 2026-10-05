import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/bindings.dart';
import '../models/log_entry.dart';
import '../rosbridge/ros_client.dart';
import 'connection_manager.dart';

/// Bounded, batched store of `/rosout` records.
///
/// Two things keep this cheap when the ROS graph is noisy:
///
///  * **Batching.** Arriving records land in [_incoming] and are merged at most
///    once per [flushInterval]. A graph spewing 500 lines/s costs five rebuilds
///    per second, not five hundred.
///  * **Capping.** Only [maxEntries] are retained; the oldest are dropped. The
///    widget then virtualises on top of that, so only the visible rows are ever
///    built no matter how long the app has been open.
///
/// Records arrive in arrival order because [List] preserves it, so no sorting
/// pass is needed per batch.
class LogStore extends ChangeNotifier {
  LogStore();

  /// Retained records. Older entries fall off the front once this is hit.
  static const int maxEntries = 5000;

  /// Upper bound on records waiting for the next flush, so pausing the UI or a
  /// backgrounded app cannot grow the queue without limit.
  static const int maxPending = 2000;

  /// Rebuild budget: at most this many UI updates per second.
  static const Duration flushInterval = Duration(milliseconds: 200);

  final List<LogEntry> _entries = <LogEntry>[];
  final List<LogEntry> _incoming = <LogEntry>[];

  /// Indices into [_entries] that pass the current severity filter, oldest
  /// first. Rebuilt on flush and on filter change only, never per record.
  final List<int> _visible = <int>[];

  LogSeverity? _minSeverity;
  Timer? _flushTimer;
  bool _dirty = false;
  bool _disposed = false;

  StreamSubscription<Map<String, dynamic>>? _sub;
  RosClient? _subClient;
  String? _topic;
  ConnectionManager? _cm;

  /// Records retained and visible under the current filter.
  int get visibleCount => _visible.length;

  /// Records retained, including those hidden by the filter.
  int get retainedCount => _entries.length;

  /// Records received since the last flush and not yet shown.
  int get pendingCount => _incoming.length;

  /// Records dropped because [maxEntries] was reached.
  int get droppedCount => _dropped;
  int _dropped = 0;

  /// Minimum severity currently shown, or `null` for everything.
  LogSeverity? get minSeverity => _minSeverity;

  /// All retained records, oldest first.
  UnmodifiableListView<LogEntry> get entries =>
      UnmodifiableListView<LogEntry>(_entries);

  /// The [index]th visible record counted from the newest, which is how the
  /// reversed list in the log view indexes them.
  LogEntry visibleAt(int index) => _entries[_visible[_visible.length - 1 - index]];

  /// Records in arrival order, newest last.
  void add(LogEntry entry) {
    if (_disposed) return;
    _incoming.add(entry);
    // Drop the oldest rather than growing without bound when the flush timer
    // is starved (app backgrounded, or the tab is not mounted).
    if (_incoming.length > maxPending) {
      _incoming.removeRange(0, _incoming.length - maxPending);
      _dropped++;
    }
    _dirty = true;
    // Arm the batch window on demand and let _flush disarm it again, so an
    // idle store holds no timer. Batching must not depend on a subscription
    // being active: records queued just before a disconnect still have to be
    // shown.
    _flushTimer ??= Timer(flushInterval, _flush);
  }

  /// Drops every retained and pending record.
  void clear() {
    if (_disposed) return;
    _entries.clear();
    _incoming.clear();
    _visible.clear();
    _dropped = 0;
    _flushTimer?.cancel();
    _flushTimer = null;
    _dirty = false;
    notifyListeners();
  }

  /// Hides records below [severity], or shows everything when `null`.
  void setMinSeverity(LogSeverity? severity) {
    if (_disposed || severity == _minSeverity) return;
    _minSeverity = severity;
    _rebuildVisible();
    notifyListeners();
  }

  /// Starts mirroring `/rosout` into this store, following [cm]'s connection.
  ///
  /// Safe to call repeatedly; the previous subscription is dropped first.
  void attach(ConnectionManager cm) {
    if (identical(cm, _cm)) return;
    _cm?.removeListener(_onConnectionChanged);
    _cm = cm..addListener(_onConnectionChanged);
    _onConnectionChanged();
  }

  void _onConnectionChanged() {
    if (_disposed) return;
    final binding = _cm?.profile?.bindings.get(LogicalAction.rosout);
    final topic = binding?.name;
    final client = _cm?.client;

    if (_cm?.isConnected != true ||
        client == null ||
        binding == null ||
        topic == null ||
        topic.isEmpty) {
      _stopListening();
      return;
    }
    if (_sub != null && _topic == topic && identical(_subClient, client)) {
      return;
    }

    _stopListening();
    _topic = topic;
    _subClient = client;
    _sub = client.messages.listen(_onFrame);
    unawaited(client.subscribe(topic, binding.type, throttleRate: 100));
  }

  void _onFrame(Map<String, dynamic> frame) {
    if (frame['op'] != 'publish') return;
    if (frame['topic'] != _topic) return;
    final msg = frame['msg'];
    if (msg is! Map<String, dynamic>) return;
    final entry = LogEntry.fromRosout(msg);
    if (entry != null) add(entry);
  }

  void _flush() {
    _flushTimer = null;
    if (_disposed || !_dirty || _incoming.isEmpty) return;
    _dirty = false;

    _entries.addAll(_incoming);
    _incoming.clear();
    if (_entries.length > maxEntries) {
      _dropped += _entries.length - maxEntries;
      _entries.removeRange(0, _entries.length - maxEntries);
    }
    _rebuildVisible();
    notifyListeners();
  }

  void _rebuildVisible() {
    final min = _minSeverity;
    if (min == null) {
      _visible
        ..clear()
        ..addAll(List<int>.generate(_entries.length, (i) => i));
      return;
    }
    _visible.clear();
    for (var i = 0; i < _entries.length; i++) {
      if (_entries[i].severity >= min) _visible.add(i);
    }
  }

  void _stopListening() {
    unawaited(_sub?.cancel());
    _sub = null;
    _subClient = null;
    _topic = null;
    // Deliberately leaves _incoming alone: records already received are still
    // shown once the batch window closes.
  }

  @override
  void dispose() {
    _disposed = true;
    _cm?.removeListener(_onConnectionChanged);
    _cm = null;
    _stopListening();
    _entries.clear();
    _incoming.clear();
    _visible.clear();
    super.dispose();
  }
}