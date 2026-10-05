import 'package:flutter_test/flutter_test.dart';
import 'package:uasdraw/core/models/bindings.dart';
import 'package:uasdraw/core/services/drawing_commands.dart';

import 'helpers/fake_transport.dart';

void main() {
  group('readUasResult', () {
    test('reads the operation_result field used by LoadGCodeContent', () {
      final result = readUasResult(<String, dynamic>{
        'values': <String, dynamic>{
          'operation_result': <String, dynamic>{
            'was_successful': true,
            'message': '',
          },
        },
      });
      expect(result.isSuccess, isTrue);
      expect(result.summary, 'ok');
    });

    test('reads the result field used by Pause/Resume/SetPen', () {
      final result = readUasResult(<String, dynamic>{
        'values': <String, dynamic>{
          'result': <String, dynamic>{
            'was_successful': false,
            'message': 'no g-code loaded',
          },
        },
      });
      expect(result.isSuccess, isFalse);
      expect(result.summary, 'no g-code loaded');
    });

    test('falls back to the Trigger success/message shape', () {
      final result = readUasResult(<String, dynamic>{
        'values': <String, dynamic>{'success': true, 'message': 'cancelled'},
      });
      expect(result.isSuccess, isTrue);
      expect(result.summary, 'cancelled');
    });

    test('treats a was_successful:false Trigger reply as a failure', () {
      final result = readUasResult(<String, dynamic>{
        'values': <String, dynamic>{'success': true, 'was_successful': false},
      });
      expect(result.isSuccess, isFalse);
    });

    test('a rosbridge result:false frame is a failure', () {
      final result = readUasResult(<String, dynamic>{
        'result': false,
        'values': <String, dynamic>{},
      });
      expect(result.isSuccess, isFalse);
    });
  });

  group('readGeometryPoint', () {
    test('reads a SetHome/SetOrigin position', () {
      final point = readGeometryPoint(<String, dynamic>{
        'values': <String, dynamic>{
          'position': <String, dynamic>{'x': 1.5, 'y': -2.0, 'z': 0.25},
        },
      });
      expect(point, const GeometryPoint(1.5, -2.0, 0.25));
    });

    test('defaults a missing z to zero', () {
      final point = readGeometryPoint(<String, dynamic>{
        'values': <String, dynamic>{
          'position': <String, dynamic>{'x': 3.0, 'y': 4.0},
        },
      });
      expect(point, const GeometryPoint(3.0, 4.0, 0));
    });

    test('returns null when the reply carries no position', () {
      expect(readGeometryPoint(const <String, dynamic>{}), isNull);
      expect(
        readGeometryPoint(<String, dynamic>{'values': <String, dynamic>{}}),
        isNull,
      );
    });
  });

  group('message builders', () {
    test('DrawingPen matches the Pen layout', () {
      expect(
        const DrawingPen(type: 0, lengthInCm: 2.5).toJson(),
        <String, dynamic>{'type': 0, 'length_in_cm': 2.5},
      );
    });

    test('DrawingCanvas nests dimensions_in_cm as x/y', () {
      expect(
        const DrawingCanvas(widthInCm: 120, heightInCm: 80).toJson(),
        <String, dynamic>{
          'dimensions_in_cm': <String, dynamic>{'x': 120.0, 'y': 80.0},
        },
      );
    });

    test('DrawingContext flattens canvas, scale flag and pen', () {
      expect(
        const DrawingContext(
          canvas: DrawingCanvas(widthInCm: 10, heightInCm: 20),
          scalePicture: false,
          pen: DrawingPen(type: 1, lengthInCm: 5),
        ).toJson(),
        <String, dynamic>{
          'canvas': <String, dynamic>{
            'dimensions_in_cm': <String, dynamic>{'x': 10.0, 'y': 20.0},
          },
          'scale_picture': false,
          'pen': <String, dynamic>{'type': 1, 'length_in_cm': 5.0},
        },
      );
    });

    test('DrawingPen defaults to the one constant the interface defines', () {
      expect(const DrawingPen().type, DrawingPen.pencil);
    });
  });

  group('DrawPictureFeedback', () {
    test('decodes line, progress and the active pen', () {
      final feedback = DrawPictureFeedback.fromJson(<String, dynamic>{
        'current_line': 42,
        'progress': 0.5,
        'active_pen': <String, dynamic>{'type': 1, 'length_in_cm': 3.0},
      });
      expect(feedback.currentLine, 42);
      expect(feedback.progress, 0.5);
      expect(feedback.activePen, const DrawingPen(type: 1, lengthInCm: 3));
    });

    test('clamps a nonsense progress instead of breaking the bar', () {
      expect(
        DrawPictureFeedback.fromJson(
          <String, dynamic>{'progress': 4.2},
        ).progress,
        1.0,
      );
      expect(
        DrawPictureFeedback.fromJson(
          <String, dynamic>{'progress': -1.0},
        ).progress,
        0.0,
      );
    });

    test('tolerates missing fields', () {
      final feedback = DrawPictureFeedback.fromJson(const <String, dynamic>{});
      expect(feedback.currentLine, 0);
      expect(feedback.progress, 0);
      expect(feedback.activePen, isNull);
    });
  });

  group('DrawingCommands', () {
    test('sends SetPen with a nested pen', () async {
      await withClient((client, transport) async {
        final commands =
            DrawingCommands(client: client, bindings: Bindings.uasDraw());
        transport.onServiceCall = (_, _) => const <String, dynamic>{
              'result': <String, dynamic>{'was_successful': true, 'message': ''},
            };

        final result =
            await commands.setPen(const DrawingPen(type: 1, lengthInCm: 4));
        expect(result.isSuccess, isTrue);

        final call = transport.lastOp('call_service');
        expect(call['service'], '/uas_draw/set_pen');
        expect(call['type'], 'uas_draw_interfaces/srv/SetPen');
        expect(
          ((call['args'] as Map)['pen'] as Map),
          <String, dynamic>{'type': 1, 'length_in_cm': 4.0},
        );
      });
    });

    test('sends SetDrawingContext with a nested context', () async {
      await withClient((client, transport) async {
        final commands =
            DrawingCommands(client: client, bindings: Bindings.uasDraw());
        transport.onServiceCall = (_, _) => const <String, dynamic>{};

        await commands.setDrawingContext(
          const DrawingContext(canvas: DrawingCanvas(widthInCm: 5, heightInCm: 6)),
        );

        final call = transport.lastOp('call_service');
        expect(call['service'], '/uas_draw/set_drawing_context');
        final args = (call['args'] as Map)['context'] as Map;
        expect(args['scale_picture'], isTrue);
        expect(
          ((args['canvas'] as Map)['dimensions_in_cm'] as Map)['x'],
          5.0,
        );
      });
    });

    test('the request-free services send no args', () async {
      await withClient((client, transport) async {
        final commands =
            DrawingCommands(client: client, bindings: Bindings.uasDraw());
        transport.onServiceCall = (_, _) => const <String, dynamic>{};

        await commands.pause();
        expect(transport.lastOp('call_service')['args'], isEmpty);
        expect(transport.lastOp('call_service')['service'], '/uas_draw/pause');

        await commands.resume();
        expect(transport.lastOp('call_service')['service'], '/uas_draw/resume');

        await commands.cancelDrawing();
        final cancel = transport.lastOp('call_service');
        expect(cancel['service'], '/uas_draw/cancel_drawing');
        expect(cancel['type'], 'uas_draw_interfaces/srv/Cancel');
        expect(cancel['args'], isEmpty);
      });
    });

    test('SetHome and SetOrigin return the reported point', () async {
      await withClient((client, transport) async {
        final commands =
            DrawingCommands(client: client, bindings: Bindings.uasDraw());
        transport.onServiceCall = (service, _) => <String, dynamic>{
              'position': service == '/uas_draw/set_home'
                  ? <String, dynamic>{'x': 0.0, 'y': 0.0, 'z': 0.0}
                  : <String, dynamic>{'x': 50.0, 'y': 25.0, 'z': -1.0},
            };

        expect(await commands.setHome(), const GeometryPoint(0, 0, 0));
        expect(await commands.setOrigin(), const GeometryPoint(50, 25, -1));
      });
    });

    test('drawPicture sends an action goal, not a service call', () async {
      await withClient((client, transport) async {
        final commands =
            DrawingCommands(client: client, bindings: Bindings.uasDraw());
        await commands.drawPicture();

        final goal = transport.lastOp('action_goal');
        expect(goal['action'], '/uas_draw/draw_picture');
        expect(goal['action_type'], 'uas_draw_interfaces/action/DrawPicture');
        expect(transport.opsOfType('call_service'), isEmpty);
      });
    });

    test('every command reports an unbound action instead of crashing',
        () async {
      await withClient((client, transport) async {
        // A profile that only binds the joystick.
        final commands = DrawingCommands(
          client: client,
          bindings: Bindings(<LogicalAction, Binding>{
            LogicalAction.joy: const Binding.topic('/joy', 'sensor_msgs/msg/Joy'),
          }),
        );

        await expectLater(
          commands.pause(),
          throwsA(isA<DrawingCommandException>()),
        );
        await expectLater(
          commands.setPen(const DrawingPen()),
          throwsA(isA<DrawingCommandException>()),
        );
        await expectLater(
          commands.drawPicture(),
          throwsA(isA<DrawingCommandException>()),
        );
        expect(transport.sent, isEmpty);
      });
    });

    test('a service binding on drawPicture is not mistaken for an action',
        () async {
      await withClient((client, transport) async {
        final commands = DrawingCommands(
          client: client,
          bindings: Bindings.uasDraw().withOverride(
            LogicalAction.drawPicture,
            const Binding.service(
              '/uas_draw/draw_picture',
              'std_srvs/srv/Trigger',
            ),
          ),
        );
        await expectLater(
          commands.drawPicture(),
          throwsA(isA<DrawingCommandException>()),
        );
      });
    });
  });
}