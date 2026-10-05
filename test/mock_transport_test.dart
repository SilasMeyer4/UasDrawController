import 'package:flutter_test/flutter_test.dart';
import 'package:uasdraw/core/rosbridge/mock_transport.dart';
import 'package:uasdraw/core/rosbridge/ros_client.dart';

void main() {
  late MockTransport transport;
  late RosClient client;

  setUp(() async {
    transport = MockTransport();
    client = RosClient(transport);
    await client.connect('mock://local');
  });

  tearDown(() async {
    await client.dispose();
  });

  group('fidelity with real rosbridge', () {
    test('introspection uses /rosapi/* names', () async {
      final graph = await client.fetchGraph();
      expect(graph.topics.keys, contains('/uas_draw/data'));
      expect(graph.topics['/uas_draw/data'],
          'uas_draw_interfaces/msg/UasDrawDataBlock');
      expect(graph.services.keys, contains('/UasDraw/arm'));
      expect(graph.services['/UasDraw/arm'], 'std_srvs/srv/Trigger');
      expect(graph.nodes, contains('/rosapi'));
    });

    test('publishing a topic that was never advertised is dropped', () async {
      final received = <Map<String, dynamic>>[];
      final sub = client.messages.listen(received.add);
      await Future<void>.delayed(Duration.zero);

      // No advertise: the mock must refuse, exactly like rosbridge does.
      await client.publish('/UasDraw/joy', <String, dynamic>{'axes': <double>[]});
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(received, isEmpty);
      final errors = <String>[];
      final errorSub = client.errors.listen(errors.add);
      await client.publish('/UasDraw/joy', <String, dynamic>{'axes': <double>[]});
      await Future<void>.delayed(Duration.zero);
      await errorSub.cancel();
      await sub.cancel();
      expect(errors.join(), contains('not advertised'));
    });

    test('advertise makes the publish accepted', () async {
      await client.publish('/UasDraw/joy', <String, dynamic>{'axes': <double>[]},
          type: 'sensor_msgs/msg/Joy');
      expect(transport.sentOps.map((f) => f['op']),
          containsAllInOrder(<String>['advertise', 'publish']));
    });

    test('unsubscribed topics are not forwarded', () async {
      await client.subscribe('/mavros/battery', 'mavros_msgs/msg/BatteryState');
      final received = <Map<String, dynamic>>[];
      final sub = client.messages.listen(received.add);
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      await sub.cancel();
      expect(received, isNotEmpty);
      expect(received.every((f) => f['topic'] == '/mavros/battery'), isTrue);
    });

    test('a subscribed drawing topic delivers UasDrawDataBlock frames', () async {
      await client.subscribe('/uas_draw/data',
          'uas_draw_interfaces/msg/UasDrawDataBlock');
      final received = <Map<String, dynamic>>[];
      final sub = client.messages.listen(received.add);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      await sub.cancel();
      expect(received, isNotEmpty);
      final msg = received.first['msg'] as Map<String, dynamic>;
      // UasDrawDataBlock nests a geometry_msgs/Point; the app must see that.
      expect(msg['position'], isA<Map<String, dynamic>>());
      expect((msg['position'] as Map<String, dynamic>)['x'], isA<num>());
      expect(msg['is_drawing'], isA<bool>());
    });

    test('unknown service reports failure instead of fake success', () async {
      await expectLater(
        client.callService('/does/not/exist', 'std_srvs/srv/Trigger',
            <String, dynamic>{}),
        throwsA(isA<RosServiceCallException>()),
      );
    });

    test('LoadGCodeContent returns a uas_draw_interfaces/Result', () async {
      final response = await client.callService(
        '/uas_draw/load_gcode_content',
        'uas_draw_interfaces/srv/LoadGCodeContent',
        <String, dynamic>{'content': 'G21\nG90\n'},
      );
      final values = response['values'] as Map<String, dynamic>;
      final result = values['operation_result'] as Map<String, dynamic>;
      expect(result['was_successful'], isTrue);
    });

    test('empty g-code is rejected by the node', () async {
      final response = await client.callService(
        '/uas_draw/load_gcode_content',
        'uas_draw_interfaces/srv/LoadGCodeContent',
        <String, dynamic>{'content': '   '},
      );
      final result = (response['values'] as Map<String, dynamic>)['operation_result']
          as Map<String, dynamic>;
      expect(result['was_successful'], isFalse);
      expect(result['message'], contains('empty'));
    });

    test('Trigger services return success', () async {
      final response = await client.callService(
        '/UasDraw/arm',
        'std_srvs/srv/Trigger',
        <String, dynamic>{},
      );
      expect((response['values'] as Map<String, dynamic>)['success'], isTrue);
    });

    test('the mock never echoes outbound frames back as traffic', () async {
      final received = <Map<String, dynamic>>[];
      final sub = client.messages.listen(received.add);
      await client.subscribe('/UasDraw/joy', 'sensor_msgs/msg/Joy');
      await client.publish('/UasDraw/joy', <String, dynamic>{'axes': <double>[0.1]},
          type: 'sensor_msgs/msg/Joy');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await sub.cancel();
      expect(received.where((f) => f['op'] == 'call_service'), isEmpty);
    });
  });

  group('rosdrvFor', () {
    test('knows the interfaces the app uses', () {
      expect(rosdrvFor('std_srvs/srv/Trigger'), contains('---'));
      expect(rosdrvFor('geometry_msgs/msg/Point'), contains('float64 x'));
      expect(rosdrvFor('nope/msg/Nope'), isEmpty);
    });
  });
}