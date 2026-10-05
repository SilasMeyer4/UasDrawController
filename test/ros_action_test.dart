
import 'package:flutter_test/flutter_test.dart';
import 'package:uasdraw/core/rosbridge/ros_client.dart';

import 'helpers/fake_transport.dart';

void main() {
  group('rosbridge action protocol', () {
    test('sends an action_goal frame with action and action_type', () async {
      await withClient((client, transport) async {
        await client.sendActionGoal(
          '/uas_draw/draw_picture',
          'uas_draw_interfaces/action/DrawPicture',
          const <String, dynamic>{},
        );

        final goal = transport.lastOp('action_goal');
        expect(goal['action'], '/uas_draw/draw_picture');
        expect(goal['action_type'], 'uas_draw_interfaces/action/DrawPicture');
        expect(goal['goal'], isEmpty);
        expect(goal['id'], isA<String>());
      });
    });

    test('action ids never collide with service call ids', () async {
      await withClient((client, transport) async {
        transport.onServiceCall = (_, _) => const <String, dynamic>{};
        final goal = await client.sendActionGoal(
          '/uas_draw/draw_picture',
          'uas_draw_interfaces/action/DrawPicture',
          const <String, dynamic>{},
        );
        await client.callService(
          '/rosapi/nodes',
          'rosapi_msgs/srv/Nodes',
          const <String, dynamic>{},
        );

        final ids = transport.sent
            .map((frame) => frame['id'] as String?)
            .whereType<String>()
            .toList();
        expect(ids, containsAll(<String>[goal.id]));
        expect(ids.toSet().length, ids.length, reason: 'ids must be unique');
        expect(goal.id, isNot(startsWith('call_service:')));
      });
    });

    test('delivers action_feedback frames to the goal feedback stream', () async {
      await withClient((client, transport) async {
        final goal = await client.sendActionGoal(
          '/uas_draw/draw_picture',
          'uas_draw_interfaces/action/DrawPicture',
          const <String, dynamic>{},
        );
        final seen = <Map<String, dynamic>>[];
        final sub = goal.feedback.listen(seen.add);

        transport.emit(actionFrame('action_feedback', goal.id, <String, dynamic>{
          'current_line': 10,
          'progress': 0.5,
        }));
        transport.emit(actionFrame('action_feedback', goal.id, <String, dynamic>{
          'current_line': 20,
          'progress': 1.0,
        }));
        await pumpEventQueue();

        expect(seen, hasLength(2));
        expect(seen.last['current_line'], 20);
        await sub.cancel();
      });
    });

    test('action frames do not leak into the topic message stream', () async {
      await withClient((client, transport) async {
        final goal = await client.sendActionGoal(
          '/uas_draw/draw_picture',
          'uas_draw_interfaces/action/DrawPicture',
          const <String, dynamic>{},
        );
        final traffic = <Map<String, dynamic>>[];
        client.messages.listen(traffic.add);

        transport.emit(actionFrame('action_feedback', goal.id, const <String, dynamic>{}));
        transport.emit(actionFrame('action_result', goal.id, const <String, dynamic>{}));
        await pumpEventQueue();

        expect(traffic, isEmpty);
      });
    });

    test('resolves the goal result and closes the feedback stream', () async {
      await withClient((client, transport) async {
        final goal = await client.sendActionGoal(
          '/uas_draw/draw_picture',
          'uas_draw_interfaces/action/DrawPicture',
          const <String, dynamic>{},
        );
        var feedbackClosed = false;
        goal.feedback.listen(null, onDone: () => feedbackClosed = true);

        transport.emit(actionFrame('action_result', goal.id,
            <String, dynamic>{'result': <String, dynamic>{'was_successful': true}}));

        final values = await goal.result;
        expect((values['result'] as Map)['was_successful'], isTrue);
        await pumpEventQueue();
        expect(feedbackClosed, isTrue);
        expect(client.activeGoals, isEmpty);
      });
    });

    test('a result frame with result:false rejects the goal', () async {
      await withClient((client, transport) async {
        final goal = await client.sendActionGoal(
          '/uas_draw/draw_picture',
          'uas_draw_interfaces/action/DrawPicture',
          const <String, dynamic>{},
        );
        transport.emit(actionFrame('action_result', goal.id,
            const <String, dynamic>{}, result: false));

        await expectLater(
          goal.result,
          throwsA(isA<RosActionException>()
              .having((e) => e.action, 'action', '/uas_draw/draw_picture')),
        );
      });
    });

    test('cancel sends action_cancel for the goal id', () async {
      await withClient((client, transport) async {
        final goal = await client.sendActionGoal(
          '/uas_draw/draw_picture',
          'uas_draw_interfaces/action/DrawPicture',
          const <String, dynamic>{},
        );
        await goal.cancel();

        final cancel = transport.lastOp('action_cancel');
        expect(cancel['id'], goal.id);
        expect(cancel['action'], '/uas_draw/draw_picture');
      });
    });

    test('cancelling a finished goal sends nothing', () async {
      await withClient((client, transport) async {
        final goal = await client.sendActionGoal(
          '/uas_draw/draw_picture',
          'uas_draw_interfaces/action/DrawPicture',
          const <String, dynamic>{},
        );
        transport.emit(actionFrame('action_result', goal.id,
            const <String, dynamic>{}));
        await goal.result;
        final before = transport.sent.length;

        await goal.cancel();
        expect(transport.sent, hasLength(before));
      });
    });

    test('rejects a goal when not connected', () async {
      final client = RosClient(FakeTransport());
      await expectLater(
        client.sendActionGoal(
          '/uas_draw/draw_picture',
          'uas_draw_interfaces/action/DrawPicture',
          const <String, dynamic>{},
        ),
        throwsA(isA<RosActionException>()),
      );
    });

    test('disconnect fails every in-flight goal', () async {
      final transport = FakeTransport();
      final client = RosClient(transport);
      await client.connect('ws://test');
      final goal = await client.sendActionGoal(
        '/uas_draw/draw_picture',
        'uas_draw_interfaces/action/DrawPicture',
        const <String, dynamic>{},
      );

      await client.disconnect();
      await expectLater(
        goal.result,
        throwsA(isA<RosActionException>()),
      );
      await client.dispose();
    });

    test('a goal nobody awaits does not surface as an unhandled error',
        () async {
      await withClient((client, transport) async {
        // The failure arrives before anyone listens: the UI is allowed to only
        // care about feedback.
        await client.sendActionGoal(
          '/uas_draw/draw_picture',
          'uas_draw_interfaces/action/DrawPicture',
          const <String, dynamic>{},
        );
        transport.emit(actionFrame('action_result', 'action_goal:1',
            const <String, dynamic>{}, result: false));
        await pumpEventQueue();
      });
    });
  });
}

/// Convenience: an `action_result` / `action_feedback` frame for [id].
Map<String, dynamic> actionFrame(
  String op,
  String id,
  Map<String, dynamic> values, {
  bool result = true,
}) =>
    <String, dynamic>{
      'op': op,
      'id': id,
      'action': '/uas_draw/draw_picture',
      'values': values,
      if (op == 'action_result') 'result': result,
    };