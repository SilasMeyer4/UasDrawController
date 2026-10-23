import 'package:flutter/material.dart';

import '../../core/models/bindings.dart';
import '../../core/models/pen_contact.dart';
import '../../core/services/pen_trace_store.dart';

/// Live 2D view of the wall, drawn from the Gazebo pen contact stream.
///
/// This replaces the custom Gazebo drawing plugin: the simulation stays clean
/// and the app renders the trace locally.
class LiveCanvasCard extends StatefulWidget {
  const LiveCanvasCard({
    super.key,
    required this.store,
    required this.binding,
    required this.topicAvailable,
  });

  final PenTraceStore store;

  /// Contact topic from the active connection profile, if one is bound.
  final Binding? binding;

  /// Whether the topic exists in the discovered ROS graph.
  final bool topicAvailable;

  @override
  State<LiveCanvasCard> createState() => _LiveCanvasCardState();
}

class _LiveCanvasCardState extends State<LiveCanvasCard> {
  double _canvasWidth = 720;

  static const _minWidth = 200.0;
  static const _maxWidth = 1200.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unavailable = widget.binding != null && !widget.topicAvailable;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Live canvas', style: theme.textTheme.titleSmall),
                ),
                OutlinedButton.icon(
                  onPressed: widget.store.clear,
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 2),
            if (widget.binding == null)
              Text(
                'No pen contact topic is bound in this profile.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              )
            else
              Text(
                '${widget.binding!.name}\n${widget.binding!.type}',
                style: theme.textTheme.bodySmall,
              ),
            if (unavailable)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'The contact topic is not in the ROS graph. '
                  'Is the ros_gz bridge running?',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.orange,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            _canvas(theme),
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(width: 90, child: Text('Canvas width')),
                Expanded(
                  child: Slider(
                    key: const Key('live-canvas-width'),
                    value: _canvasWidth.clamp(_minWidth, _maxWidth),
                    min: _minWidth,
                    max: _maxWidth,
                    divisions: ((_maxWidth - _minWidth) / 10).round(),
                    label: '${_canvasWidth.toStringAsFixed(0)} px',
                    onChanged: (v) => setState(() => _canvasWidth = v),
                  ),
                ),
                SizedBox(
                  width: 68,
                  child: Text(
                    '${_canvasWidth.toStringAsFixed(0)} px',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Front view: Y horizontal, Z vertical',
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 8),
            ListenableBuilder(
              listenable: widget.store,
              builder: (context, _) => Row(
                children: [
                  _statusDot(theme),
                  const SizedBox(width: 6),
                  Text(
                    _statusLabel(unavailable),
                    style: theme.textTheme.bodySmall,
                  ),
                  const Spacer(),
                  Text(
                    '${widget.store.pointCount} points · ${widget.store.strokeCount} strokes',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(bool unavailable) {
    if (widget.binding == null) return 'not bound';
    if (unavailable) return 'no topic';
    return widget.store.isContacting ? 'contact' : 'waiting';
  }

  Widget _statusDot(ThemeData theme) {
    final color = widget.binding == null || !widget.topicAvailable
        ? Colors.orange
        : widget.store.isContacting
            ? Colors.green
            : Colors.blueGrey;
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _canvas(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            key: const Key('live-canvas'),
            constraints: BoxConstraints(maxWidth: _canvasWidth),
            child: AspectRatio(
              aspectRatio: widget.store.wallBounds.width /
                  widget.store.wallBounds.height,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black26),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      RepaintBoundary(
                        child: CustomPaint(
                          painter: PenTracePainter(
                            store: widget.store,
                            wallBounds: widget.store.wallBounds,
                          ),
                        ),
                      ),
                      ListenableBuilder(
                        listenable: widget.store,
                        builder: (context, _) {
                          if (!widget.store.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return IgnorePointer(
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  'No contact yet — touch the wall with the pen.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.black54,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Paints the normalized strokes, grid and wall background.
class PenTracePainter extends CustomPainter {
  PenTracePainter({required this.store, required this.wallBounds})
      : super(repaint: store);

  final PenTraceStore store;
  final WallBounds wallBounds;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    final minor = Paint()
      ..color = const Color(0xFFE1E1E1)
      ..strokeWidth = 1;
    // The wall is 4 x 3 m, so 8 x 6 half-metre cells.
    for (var i = 1; i < 8; i++) {
      final x = rect.left + rect.width * i / 8;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), minor);
    }
    for (var j = 1; j < 6; j++) {
      final y = rect.top + rect.height * j / 6;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), minor);
    }

    final axis = Paint()
      ..color = const Color(0xFFC7C7C7)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(rect.left + rect.width / 2, rect.top),
      Offset(rect.left + rect.width / 2, rect.bottom),
      axis,
    );
    canvas.drawLine(
      Offset(rect.left, rect.top + rect.height / 2),
      Offset(rect.right, rect.top + rect.height / 2),
      axis,
    );

    final ink = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final dot = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.fill;

    for (final stroke in store.strokes) {
      if (stroke.isEmpty) continue;
      if (stroke.points.length == 1) {
        canvas.drawCircle(_toPixels(stroke.points.first, rect), 2.2, dot);
        continue;
      }
      final path = Path()
        ..moveTo(
          _toPixels(stroke.points.first, rect).dx,
          _toPixels(stroke.points.first, rect).dy,
        );
      for (final point in stroke.points.skip(1)) {
        final pixel = _toPixels(point, rect);
        path.lineTo(pixel.dx, pixel.dy);
      }
      canvas.drawPath(path, ink);
    }
  }

  Offset _toPixels(Offset normalized, Rect rect) => Offset(
        rect.left + normalized.dx * rect.width,
        rect.top + normalized.dy * rect.height,
      );

  @override
  bool shouldRepaint(covariant PenTracePainter oldDelegate) =>
      oldDelegate.store != store || oldDelegate.wallBounds != wallBounds;
}
