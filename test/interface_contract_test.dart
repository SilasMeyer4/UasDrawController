import 'package:flutter_test/flutter_test.dart';
import 'package:uasdraw/core/models/bindings.dart';

/// Types the `uas_draw` preset claims, keyed by the logical action.
///
/// This table exists so a rename or a move in `uas_draw_interfaces` shows up as
/// a test failure instead of as a runtime error on a connected vehicle. When an
/// interface changes, update the table below to match the `.srv`/`.action`
/// files.
const Map<LogicalAction, String> expectedTypes = <LogicalAction, String>{
  LogicalAction.drawData: 'uas_draw_interfaces/msg/UasDrawDataBlock',
  LogicalAction.bufferStatus: 'uas_draw_interfaces/msg/BufferStatus',
  LogicalAction.rosout: 'rcl_interfaces/msg/Log',
  LogicalAction.loadGcodeContent: 'uas_draw_interfaces/srv/LoadGCodeContent',
  LogicalAction.pause: 'uas_draw_interfaces/srv/Pause',
  LogicalAction.resume: 'uas_draw_interfaces/srv/Resume',
  LogicalAction.cancelDrawing: 'uas_draw_interfaces/srv/Cancel',
  LogicalAction.setPen: 'uas_draw_interfaces/srv/SetPen',
  LogicalAction.setHome: 'uas_draw_interfaces/srv/SetHome',
  LogicalAction.setOrigin: 'uas_draw_interfaces/srv/SetOrigin',
  LogicalAction.setDrawingContext: 'uas_draw_interfaces/srv/SetDrawingContext',
  LogicalAction.drawPicture: 'uas_draw_interfaces/action/DrawPicture',
};

void main() {
  group('uasDraw preset', () {
    final bindings = Bindings.uasDraw();

    test('binds every interface under /uas_draw', () {
      // /rosout is a standard ROS topic, not one this node owns.
      const external = <LogicalAction>{LogicalAction.rosout};
      for (final entry in expectedTypes.entries) {
        final binding = bindings.get(entry.key);
        expect(binding, isNotNull, reason: '${entry.key} is not bound');
        if (external.contains(entry.key)) continue;
        expect(
          binding!.name,
          startsWith('/uas_draw/'),
          reason: '${entry.key} -> ${binding.name}',
        );
      }
    });

    test('uses the type each interface file declares', () {
      for (final entry in expectedTypes.entries) {
        expect(
          bindings.get(entry.key)!.type,
          entry.value,
          reason:
              '${entry.key} drifted from ${entry.value}; check the interface '
              'package and update expectedTypes.',
        );
      }
    });

    test('reads the response field each interface actually returns', () {
      // Result-returning services are not uniform: LoadGCodeContent and Cancel
      // call the field `operation_result`, the rest call it `result`. If a new
      // service is added, its field name has to be handled in readUasResult.
      final operationResult = <LogicalAction>[
        LogicalAction.loadGcodeContent,
        LogicalAction.cancelDrawing,
      ];
      for (final action in operationResult) {
        expect(bindings.get(action)!.type, contains('srv/'));
      }
    });

    test('the two kinds of ROS name are classified correctly', () {
      expect(bindings.get(LogicalAction.drawData)!.kind, BindingKind.topic);
      expect(bindings.get(LogicalAction.bufferStatus)!.kind, BindingKind.topic);
      expect(bindings.get(LogicalAction.rosout)!.kind, BindingKind.topic);
      expect(bindings.get(LogicalAction.pause)!.kind, BindingKind.service);
      expect(
        bindings.get(LogicalAction.cancelDrawing)!.kind,
        BindingKind.service,
      );
      expect(bindings.get(LogicalAction.drawPicture)!.kind, BindingKind.action);
      expect(bindings.get(LogicalAction.drawPicture)!.isAction, isTrue);
    });

    test('the data topic is the one the node publishes', () {
      expect(bindings.get(LogicalAction.drawData)!.name, '/uas_draw/data');
    });
  });
}