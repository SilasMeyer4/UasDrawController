// Typed views over the `uas_draw_interfaces` messages, plus the calls that
// send them.
//
// The ROS side spells a few of these fields differently between services, so
// every request is built here rather than in the widgets: a screen only has to
// say "set this pen" and never hand-assembles nested JSON.

import '../models/bindings.dart';
import '../rosbridge/ros_client.dart';

/// Raised when a command cannot even be attempted, e.g. because the active
/// profile has nothing bound to the matching [LogicalAction].
class DrawingCommandException implements Exception {
  DrawingCommandException(this.action, this.reason);

  final LogicalAction action;
  final String reason;

  @override
  String toString() => reason;
}

/// A point in the drawing plane, mirroring `geometry_msgs/msg/Point`.
class GeometryPoint {
  const GeometryPoint(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeometryPoint && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() =>
      '(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)}, ${z.toStringAsFixed(2)})';
}

/// Mirrors `uas_draw_interfaces/msg/Pen`.
class DrawingPen {
  const DrawingPen({this.type = pencil, this.lengthInCm = 2});

  /// The only constant the interface currently defines.
  static const int pencil = 0;

  final int type;
  final double lengthInCm;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': type,
        'length_in_cm': lengthInCm,
      };

  DrawingPen copyWith({int? type, double? lengthInCm}) => DrawingPen(
        type: type ?? this.type,
        lengthInCm: lengthInCm ?? this.lengthInCm,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DrawingPen &&
          other.type == type &&
          other.lengthInCm == lengthInCm;

  @override
  int get hashCode => Object.hash(type, lengthInCm);

  @override
  String toString() => '${penLabel(type)} ($lengthInCm cm)';
}

/// Mirrors `uas_draw_interfaces/msg/Canvas`.
///
/// [widthInCm]/[heightInCm] are carried in ROS as the `x`/`y` components of
/// `dimensions_in_cm`.
class DrawingCanvas {
  const DrawingCanvas({this.widthInCm = 100, this.heightInCm = 100});

  final double widthInCm;
  final double heightInCm;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'dimensions_in_cm': <String, dynamic>{
          'x': widthInCm,
          'y': heightInCm,
        },
      };

  DrawingCanvas copyWith({double? widthInCm, double? heightInCm}) =>
      DrawingCanvas(
        widthInCm: widthInCm ?? this.widthInCm,
        heightInCm: heightInCm ?? this.heightInCm,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DrawingCanvas &&
          other.widthInCm == widthInCm &&
          other.heightInCm == heightInCm;

  @override
  int get hashCode => Object.hash(widthInCm, heightInCm);

  @override
  String toString() => '${widthInCm}x$heightInCm cm';
}

/// Mirrors `uas_draw_interfaces/msg/UasDrawContext`.
class DrawingContext {
  const DrawingContext({
    this.canvas = const DrawingCanvas(),
    this.scalePicture = true,
    this.pen = const DrawingPen(),
  });

  final DrawingCanvas canvas;
  final bool scalePicture;
  final DrawingPen pen;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'canvas': canvas.toJson(),
        'scale_picture': scalePicture,
        'pen': pen.toJson(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DrawingContext &&
          other.canvas == canvas &&
          other.scalePicture == scalePicture &&
          other.pen == pen;

  @override
  int get hashCode => Object.hash(canvas, scalePicture, pen);

  @override
  String toString() => 'UasDrawContext($canvas, scale=$scalePicture, $pen)';
}

/// Mirrors `uas_draw_interfaces/msg/Result`, the reply of every drawing service.
class UasResult {
  const UasResult(this.wasSuccessful, [this.message = '']);

  final bool wasSuccessful;
  final String message;

  bool get isSuccess => wasSuccessful;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UasResult &&
          other.wasSuccessful == wasSuccessful &&
          other.message == message;

  @override
  int get hashCode => Object.hash(wasSuccessful, message);

  /// Short label for a status line: the message when the node sent one,
  /// otherwise a plain ok.
  String get summary {
    if (!wasSuccessful) return message.isEmpty ? 'rejected' : message;
    return message.isEmpty ? 'ok' : message;
  }

  @override
  String toString() => 'UasResult($wasSuccessful, $message)';
}

/// Decodes a `Result` out of a rosbridge service response.
///
/// The drawing services are not uniform: `LoadGCodeContent` names its field
/// `operation_result`, `Pause`/`Resume`/`SetPen`/`SetDrawingContext` name theirs
/// `result`, and plain `Trigger` replies use `success`. All three are accepted so
/// callers do not have to care which node answered.
UasResult readUasResult(Map<String, dynamic> response) {
  // rosbridge itself could not route the call. `callService` normally throws
  // before this point, but a raw frame can still be handed in directly.
  if (response['result'] == false) {
    return const UasResult(false, 'rosbridge reported failure');
  }
  final values = response['values'];
  if (values is! Map<String, dynamic>) return const UasResult(true);
  for (final key in const <String>['operation_result', 'result']) {
    final nested = values[key];
    if (nested is Map<String, dynamic>) {
      return UasResult(
        nested['was_successful'] == true,
        nested['message'] as String? ?? '',
      );
    }
  }
  return UasResult(
    values['was_successful'] != false && values['success'] != false,
    values['message'] as String? ?? '',
  );
}

/// Decodes the `geometry_msgs/Point` returned by `SetHome`/`SetOrigin`, or
/// `null` when the reply carried no position.
GeometryPoint? readGeometryPoint(Map<String, dynamic> response) {
  final values = response['values'];
  if (values is! Map<String, dynamic>) return null;
  final raw = values['position'];
  if (raw is! Map<String, dynamic>) return null;
  final x = raw['x'];
  final y = raw['y'];
  if (x is! num || y is! num) return null;
  return GeometryPoint(
    x.toDouble(),
    y.toDouble(),
    (raw['z'] as num?)?.toDouble() ?? 0,
  );
}

/// Mirrors the `DrawPicture` action feedback block.
class DrawPictureFeedback {
  const DrawPictureFeedback({
    required this.currentLine,
    required this.progress,
    this.activePen,
  });

  /// G-code line the interpreter is currently on.
  final int currentLine;

  /// Completion in the range 0..1, already clamped.
  final double progress;

  /// Pen the interpreter is holding, when it reported one.
  final DrawingPen? activePen;

  static DrawPictureFeedback fromJson(Map<String, dynamic> values) {
    final raw = values['active_pen'];
    return DrawPictureFeedback(
      currentLine: (values['current_line'] as num?)?.toInt() ?? 0,
      progress: ((values['progress'] as num?)?.toDouble() ?? 0)
          .clamp(0.0, 1.0),
      activePen: raw is Map<String, dynamic>
          ? DrawingPen(
              type: (raw['type'] as num?)?.toInt() ?? DrawingPen.pencil,
              lengthInCm: (raw['length_in_cm'] as num?)?.toDouble() ?? 0,
            )
          : null,
    );
  }

  @override
  String toString() =>
      'line $currentLine, ${(progress * 100).toStringAsFixed(0)}%';
}

/// Sends the `uas_draw_interfaces` services and the `DrawPicture` action.
///
/// Resolved through [Bindings] rather than hardcoded names, so the same code
/// works against both stock presets and any profile the user edited by hand.
class DrawingCommands {
  DrawingCommands({required this.client, required this.bindings});

  final RosClient client;
  final Bindings bindings;

  /// Binding for [action] when it points at a service, `null` otherwise.
  Binding? serviceFor(LogicalAction action) {
    final binding = bindings.get(action);
    return binding != null && binding.isService ? binding : null;
  }

  /// Binding for [action] when it points at an action server, `null` otherwise.
  Binding? actionFor(LogicalAction action) {
    final binding = bindings.get(action);
    return binding != null && binding.isAction ? binding : null;
  }

  Future<UasResult> _simple(LogicalAction action) async {
    final binding = serviceFor(action);
    if (binding == null) throw _unbound(action);
    final response =
        await client.callService(binding.name, binding.type, binding.args);
    return readUasResult(response);
  }

  Future<UasResult> _withField(LogicalAction action, String field, Object value) async {
    final binding = serviceFor(action);
    if (binding == null) throw _unbound(action);
    final response = await client.callService(
      binding.name,
      binding.type,
      binding.argsWith(<String, dynamic>{field: value}),
    );
    return readUasResult(response);
  }

  Future<GeometryPoint?> _queryPoint(LogicalAction action) async {
    final binding = serviceFor(action);
    if (binding == null) throw _unbound(action);
    final response =
        await client.callService(binding.name, binding.type, binding.args);
    return readGeometryPoint(response);
  }

  /// `Pause`: hold the interpreter where it is.
  Future<UasResult> pause() => _simple(LogicalAction.pause);

  /// `Resume`: continue after a [pause].
  Future<UasResult> resume() => _simple(LogicalAction.resume);

  /// Stops the running job. Uses a plain `Trigger`, so it stays usable even
  /// when the drawing node is wedged.
  Future<UasResult> cancelDrawing() => _simple(LogicalAction.cancelDrawing);

  /// `SetPen`: selects the tool and its reach.
  Future<UasResult> setPen(DrawingPen pen) =>
      _withField(LogicalAction.setPen, 'pen', pen.toJson());

  /// `SetDrawingContext`: canvas size, scaling and the active pen in one call.
  Future<UasResult> setDrawingContext(DrawingContext context) => _withField(
        LogicalAction.setDrawingContext,
        'context',
        context.toJson(),
      );

  /// `SetHome`: asks the node to report/take the home position.
  Future<GeometryPoint?> setHome() => _queryPoint(LogicalAction.setHome);

  /// `SetOrigin`: asks the node to report/take the drawing origin.
  Future<GeometryPoint?> setOrigin() => _queryPoint(LogicalAction.setOrigin);

  /// Starts `DrawPicture` and returns the running goal so the caller can read
  /// feedback and cancel it.
  ///
  /// The goal has an empty request, so only the binding defaults are sent.
  Future<RosActionGoal> drawPicture() async {
    final binding = actionFor(LogicalAction.drawPicture);
    if (binding == null) throw _unbound(LogicalAction.drawPicture);
    return client.sendActionGoal(binding.name, binding.type, binding.args);
  }

  DrawingCommandException _unbound(LogicalAction action) =>
      DrawingCommandException(
        action,
        'No ${action.name} target is bound in this connection profile.',
      );
}

/// Human label for a `Pen.type` value.
String penLabel(int type) => switch (type) {
      DrawingPen.pencil => 'Pencil',
      _ => 'Tool $type',
    };

/// Pen types offered in the UI.
///
/// `Pen.msg` only declares `PENCIL = 0`, so the rest are speculative: pick one
/// to send an arbitrary `type` and let the node decide what it means.
const List<int> knownPenTypes = <int>[0, 1, 2, 3];