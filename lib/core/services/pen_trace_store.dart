import 'dart:async';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../models/bindings.dart';
import '../models/pen_contact.dart';
import '../rosbridge/ros_client.dart';
import 'connection_manager.dart';

/// One continuous pen stroke, stored in normalized wall coordinates.
class PenStroke {
  PenStroke();

  /// Normalized points, oldest first. `0,0` is the top-left of the wall.
  final List<Offset> points = <Offset>[];

  bool get isEmpty => points.isEmpty;
}

/// Accumulates the Gazebo pen/wall contact stream into strokes for the canvas.
///
/// The store is owned by the app, not by the Drawing screen, so the trace keeps
/// recording when the user switches tabs and survives navigating back. It
/// follows [ConnectionManager] exactly like `LogStore` follows `/rosout`.
class PenTraceStore extends ChangeNotifier {
  PenTraceStore({
    this.wallBounds = const WallBounds(),
    this.strokeGap = const Duration(milliseconds: 500),
    this.minPointSpacing = 0.002,
  });

  /// World-space extents of the drawing wall.
  final WallBounds wallBounds;

  /// A pause longer than this starts a new stroke even if Gazebo never sent an
  /// explicit "no contact" message.
  final Duration strokeGap;

  /// Minimum normalized distance between two recorded points, so a noisy
  /// contact manifold does not flood the canvas with duplicate samples.
  final double minPointSpacing;

  final List<PenStroke> _strokes = <PenStroke>[];
  PenStroke? _active;

  bool _isContacting = false;
  int _pointCount = 0;
  DateTime? _lastSampleAt;
  Timer? _gapTimer;

  ConnectionManager? _cm;
  StreamSubscription<Map<String, dynamic>>? _sub;
  RosClient? _subClient;
  String? _topic;
  bool _disposed = false;

  /// Completed and in-progress strokes, in drawing order.
  List<PenStroke> get strokes => List<PenStroke>.unmodifiable(_strokes);

  /// Stroke currently being extended, or `null` after a lift.
  PenStroke? get activeStroke => _active;

  /// True while the latest contact message still reports pen/wall contact.
  bool get isContacting => _isContacting;

  /// Total recorded points, including single-point dots.
  int get pointCount => _pointCount;

  /// Number of strokes, including the active one.
  int get strokeCount => _strokes.length;

  bool get isEmpty => _pointCount == 0;

  /// Starts following the active profile's contact topic.
  ///
  /// Safe to call repeatedly; only a changed [ConnectionManager] is re-attached.
  void attach(ConnectionManager cm) {
    if (identical(cm, _cm)) return;
    _cm?.removeListener(_onConnectionChanged);
    _cm = cm..addListener(_onConnectionChanged);
    _onConnectionChanged();
  }

  void _onConnectionChanged() {
    if (_disposed) return;

    final binding = _cm?.profile?.bindings.get(LogicalAction.penContact);
    final topic = binding?.name;
    final client = _cm?.client;
    final connected = _cm?.isConnected == true;

    if (!connected ||
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

    final topicChanged = _topic != null && _topic != topic;
    _stopListening();
    if (topicChanged) clear();

    _topic = topic;
    _subClient = client;
    _sub = client.messages.listen(_onFrame);
    unawaited(client.subscribe(topic, binding.type, throttleRate: 50));
  }

  void _onFrame(Map<String, dynamic> frame) {
    if (frame['op'] != 'publish' || frame['topic'] != _topic) return;
    final raw = frame['msg'];
    if (raw is! Map) return;
    final msg = raw is Map<String, dynamic> ? raw : raw.cast<String, dynamic>();
    ingest(msg);
  }

  /// Feeds one decoded contact message into the trace.
  ///
  /// Public only so unit tests can drive the segmentation logic without a live
  /// rosbridge connection.
  @visibleForTesting
  void ingest(Map<String, dynamic> msg, {DateTime? now}) {
    if (_disposed) return;

    final samples = parsePenContact(msg);
    if (samples.isEmpty) {
      _endContact();
      return;
    }

    final when = now ?? DateTime.now();
    final point = wallBounds.normalize(y: samples.first.y, z: samples.first.z);
    final previous = _lastSampleAt;
    final gap = previous == null || when.difference(previous) > strokeGap;
    _lastSampleAt = when;

    if (gap || _active == null || _active!.points.isEmpty) {
      _startStroke(point);
    } else {
      final last = _active!.points.last;
      if ((point - last).distance >= minPointSpacing) {
        _active!.points.add(point);
        _pointCount++;
      }
    }

    _isContacting = true;
    _scheduleGapTimer();
    notifyListeners();
  }

  void _startStroke(Offset point) {
    final stroke = PenStroke()..points.add(point);
    _strokes.add(stroke);
    _active = stroke;
    _pointCount++;
  }

  void _endContact() {
    if (!_isContacting && _active == null) return;
    _active = null;
    _isContacting = false;
    _lastSampleAt = null;
    _gapTimer?.cancel();
    _gapTimer = null;
    notifyListeners();
  }

  void _scheduleGapTimer() {
    _gapTimer?.cancel();
    _gapTimer = Timer(strokeGap, () {
      if (_disposed || !_isContacting) return;
      final last = _lastSampleAt;
      if (last != null && DateTime.now().difference(last) < strokeGap) {
        _scheduleGapTimer();
        return;
      }
      _endContact();
    });
  }

  /// Removes every stroke and resets the contact indicator.
  void clear() {
    if (_disposed) return;
    _strokes.clear();
    _active = null;
    _isContacting = false;
    _pointCount = 0;
    _lastSampleAt = null;
    _gapTimer?.cancel();
    _gapTimer = null;
    notifyListeners();
  }

  void _stopListening() {
    unawaited(_sub?.cancel());
    _sub = null;
    _subClient = null;
    _topic = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _cm?.removeListener(_onConnectionChanged);
    _cm = null;
    _stopListening();
    _gapTimer?.cancel();
    _gapTimer = null;
    _strokes.clear();
    super.dispose();
  }
}
