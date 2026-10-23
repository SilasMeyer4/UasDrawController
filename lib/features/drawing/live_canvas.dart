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
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unavailable = widget.binding != null && !widget.topicAvailable;
    final bounds = widget.store.wallBounds;

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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'Wall ${_metres(bounds.width)} × ${_metres(bounds.height)} m\n'
                    'Y ${_metres(bounds.minY)}..${_metres(bounds.maxY)} m · '
                    'Z ${_metres(bounds.minZ)}..${_metres(bounds.maxZ)} m',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  key: const Key('edit-wall-size'),
                  onPressed: _editWallDimensions,
                  icon: const Icon(Icons.straighten, size: 18),
                  label: const Text('Dimensions'),
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

  Future<void> _editWallDimensions() async {
    final bounds = await showDialog<WallBounds>(
      context: context,
      builder: (_) => _WallDimensionsDialog(initial: widget.store.wallBounds),
    );
    if (bounds == null || !mounted) return;
    widget.store.updateWallBounds(bounds);
    setState(() {});
  }

  static String _metres(double value) => value.toStringAsFixed(2);

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
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        key: const Key('live-canvas'),
        constraints: const BoxConstraints(maxWidth: 720),
        child: AspectRatio(
          aspectRatio:
              widget.store.wallBounds.width / widget.store.wallBounds.height,
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
                      painter: PenTracePainter(store: widget.store),
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
  }
}

/// Paints the normalized strokes, grid and wall background.
class PenTracePainter extends CustomPainter {
  PenTracePainter({required this.store}) : super(repaint: store);

  final PenTraceStore store;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final bounds = store.wallBounds;
    final grid = _gridStep(bounds);
    final columns = (bounds.width / grid).round();
    final rows = (bounds.height / grid).round();

    final minor = Paint()
      ..color = const Color(0xFFE1E1E1)
      ..strokeWidth = 1;
    for (var i = 1; i < columns; i++) {
      final x = rect.left + rect.width * i / columns;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), minor);
    }
    for (var j = 1; j < rows; j++) {
      final y = rect.top + rect.height * j / rows;
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

  static double _gridStep(WallBounds bounds) {
    final largest = bounds.width > bounds.height ? bounds.width : bounds.height;
    if (largest <= 5) return 0.5;
    if (largest <= 10) return 1;
    if (largest <= 20) return 2;
    return 5;
  }

  @override
  bool shouldRepaint(covariant PenTracePainter oldDelegate) =>
      oldDelegate.store != store ||
      oldDelegate.store.wallBounds != store.wallBounds;
}

/// Dialog for matching the canvas to the physical drawing wall in Gazebo.
class _WallDimensionsDialog extends StatefulWidget {
  const _WallDimensionsDialog({required this.initial});

  final WallBounds initial;

  @override
  State<_WallDimensionsDialog> createState() => _WallDimensionsDialogState();
}

class _WallDimensionsDialogState extends State<_WallDimensionsDialog> {
  late final TextEditingController _width;
  late final TextEditingController _height;
  late final TextEditingController _centerY;
  late final TextEditingController _bottomZ;
  String? _error;

  @override
  void initState() {
    super.initState();
    final bounds = widget.initial;
    _width = TextEditingController(text: _format(bounds.width));
    _height = TextEditingController(text: _format(bounds.height));
    _centerY = TextEditingController(text: _format(bounds.centerY));
    _bottomZ = TextEditingController(text: _format(bounds.minZ));
  }

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    _centerY.dispose();
    _bottomZ.dispose();
    super.dispose();
  }

  static String _format(double value) => value.toStringAsFixed(2);

  static double? _parse(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.'));

  void _reset() {
    _width.text = '4.00';
    _height.text = '3.00';
    _centerY.text = '0.00';
    _bottomZ.text = '0.00';
    setState(() => _error = null);
  }

  void _apply() {
    final width = _parse(_width.text);
    final height = _parse(_height.text);
    final centerY = _parse(_centerY.text);
    final bottomZ = _parse(_bottomZ.text);

    if (width == null ||
        height == null ||
        !width.isFinite ||
        !height.isFinite ||
        width < 0.01 ||
        height < 0.01 ||
        width > 100 ||
        height > 100) {
      setState(
        () => _error = 'Width and height must be between 0.01 and 100 m.',
      );
      return;
    }
    if (centerY == null ||
        bottomZ == null ||
        !centerY.isFinite ||
        !bottomZ.isFinite) {
      setState(() => _error = 'Enter valid numbers for the wall origin.');
      return;
    }

    Navigator.of(context).pop(
      WallBounds.fromExtent(
        width: width,
        height: height,
        centerY: centerY,
        bottomZ: bottomZ,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Wall dimensions'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Match these values to the drawing wall in Gazebo. '
                'Existing strokes are remapped to the new extents.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              _numberField('wall-width-input', 'Width (Y, m)', _width),
              _numberField('wall-height-input', 'Height (Z, m)', _height),
              _numberField('wall-center-y-input', 'Center Y (m)', _centerY),
              _numberField('wall-bottom-z-input', 'Bottom Z (m)', _bottomZ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _reset, child: const Text('Reset')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('wall-size-apply'),
          onPressed: _apply,
          child: const Text('Apply'),
        ),
      ],
    );
  }

  Widget _numberField(
    String key,
    String label,
    TextEditingController controller,
  ) =>
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: TextField(
          key: Key(key),
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      );
}
