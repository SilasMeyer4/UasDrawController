import 'package:flutter_test/flutter_test.dart';
import 'package:uasdraw/core/rosbridge/ros_client.dart';

import 'helpers/fake_transport.dart';

void main() {
  group('rosapi introspection', () {
    test('uses the real /rosapi/* service names, not /rosbridge/*', () async {
      await withClient((client, transport) async {
        transport.onServiceCall = (service, _) => _valuesFor(service);
        await client.fetchGraph();

        final seen = transport.sent
            .where((f) => f['op'] == 'call_service')
            .map((f) => f['service'] as String)
            .toList();
        expect(seen, <String>[
          '/rosapi/topics',
          '/rosapi/services',
          '/rosapi/nodes',
        ]);
        expect(seen, isNot(contains(startsWith('/rosbridge/'))));
      });
    });

    test('fetchGraph zips names with types', () async {
      await withClient((client, transport) async {
        transport.onServiceCall = (service, _) => _valuesFor(service);
        final graph = await client.fetchGraph();
        expect(graph.topics, <String, String>{
          '/uas_draw/data': 'uas_draw_interfaces/msg/UasDrawDataBlock',
          '/UasDraw/joy': 'sensor_msgs/msg/Joy',
        });
        expect(graph.services, <String, String>{
          '/UasDraw/arm': 'std_srvs/srv/Trigger',
        });
        expect(graph.nodes, contains('/rosapi'));
        expect(graph.hasTopic('/UasDraw/joy'), isTrue);
        expect(graph.hasService('/UasDraw/arm'), isTrue);
        expect(graph.topicType('/UasDraw/joy'), 'sensor_msgs/msg/Joy');
      });
    });

    test('tolerates mismatched name/type array lengths', () async {
      await withClient((client, transport) async {
        transport.onServiceCall = (service, _) => switch (service) {
              '/rosapi/topics' => <String, dynamic>{
                  'topics': ['/a', '/b'],
                  'types': ['pkg/msg/A'],
                },
              '/rosapi/services' =>
                <String, dynamic>{'services': <String>[], 'types': <String>[]},
              _ => <String, dynamic>{'nodes': <String>[]},
            };
        final graph = await client.fetchGraph();
        expect(graph.topics, <String, String>{'/a': 'pkg/msg/A', '/b': ''});
      });
    });
  });

  group('service calls', () {
    test('returns the service_response values', () async {
      await withClient((client, transport) async {
        transport.onServiceCall = (_, _) =>
            <String, dynamic>{'success': true, 'message': 'armed'};
        final response = await client.callService(
            '/UasDraw/arm', 'std_srvs/srv/Trigger', <String, dynamic>{});
        expect(response['values'], <String, dynamic>{
          'success': true,
          'message': 'armed',
        });
      });
    });

    test('throws when rosbridge reports result=false', () async {
      await withClient((client, transport) async {
        final future = client.callService(
            '/nope', 'std_srvs/srv/Trigger', <String, dynamic>{});
        await Future<void>.delayed(Duration.zero);
        final request = transport.lastOp('call_service');
        transport.emit(serviceResponse(
          request['id'] as String,
          '/nope',
          <String, dynamic>{},
          result: false,
        ));
        await expectLater(
          future,
          throwsA(isA<RosServiceCallException>()
              .having((e) => e.service, 'service', '/nope')),
        );
      });
    });

    test('times out with an actionable message and drops the pending entry',
        () async {
      await withClient((client, transport) async {
        await expectLater(
          client.callService(
            '/silent',
            'std_srvs/srv/Trigger',
            <String, dynamic>{},
            timeout: const Duration(milliseconds: 50),
          ),
          throwsA(isA<RosServiceCallException>().having(
            (e) => e.reason,
            'reason',
            contains('no response within'),
          )),
        );
        // A late response for the timed-out id must not be dispatched twice.
        final late = serviceResponse('call_service:1', '/silent',
            <String, dynamic>{'success': true});
        expect(() => transport.emit(late), returnsNormally);
      });
    });

    test('refuses to call while disconnected', () async {
      final transport = FakeTransport();
      final client = RosClient(transport);
      await expectLater(
        client.callService('/x', 'std_srvs/srv/Trigger', <String, dynamic>{}),
        throwsA(isA<RosServiceCallException>()),
      );
    });
  });

  group('publish / advertise', () {
    test('advertises before the first publish', () async {
      await withClient((client, transport) async {
        await client.publish('/UasDraw/joy', <String, dynamic>{'axes': <double>[]},
            type: 'sensor_msgs/msg/Joy');
        expect(transport.sent.map((f) => f['op']).toList(),
            <String>['advertise', 'publish']);
        expect(transport.sent.first['type'], 'sensor_msgs/msg/Joy');
      });
    });

    test('advertises only once for a repeated publish', () async {
      await withClient((client, transport) async {
        for (var i = 0; i < 5; i++) {
          await client.publish('/UasDraw/joy', <String, dynamic>{},
              type: 'sensor_msgs/msg/Joy');
        }
        expect(transport.opsOfType('advertise'), hasLength(1));
        expect(transport.opsOfType('publish'), hasLength(5));
      });
    });

    test('publish without a type skips advertising', () async {
      await withClient((client, transport) async {
        await client.publish('/raw', <String, dynamic>{});
        expect(transport.opsOfType('advertise'), isEmpty);
      });
    });

    test('unadvertise carries the advertised type', () async {
      await withClient((client, transport) async {
        await client.advertise('/t', 'pkg/msg/T');
        await client.unadvertise('/t');
        expect(transport.lastOp('unadvertise')['type'], 'pkg/msg/T');
        expect(client.advertised, isEmpty);
      });
    });

    test('does nothing when disconnected', () async {
      final transport = FakeTransport();
      final client = RosClient(transport);
      await client.publish('/t', <String, dynamic>{}, type: 'pkg/msg/T');
      await client.subscribe('/t', 'pkg/msg/T');
      expect(transport.sent, isEmpty);
    });
  });

  group('subscribe', () {
    test('deduplicates and sends throttle_rate', () async {
      await withClient((client, transport) async {
        await client.subscribe('/a', 'pkg/msg/A', throttleRate: 1000);
        await client.subscribe('/a', 'pkg/msg/A', throttleRate: 1000);
        expect(transport.opsOfType('subscribe'), hasLength(1));
        expect(transport.lastOp('subscribe')['throttle_rate'], 1000);
        expect(client.subscribed, <String, String>{'/a': 'pkg/msg/A'});
      });
    });

    test('unsubscribeAll clears every subscription', () async {
      await withClient((client, transport) async {
        await client.subscribe('/a', 'pkg/msg/A');
        await client.subscribe('/b', 'pkg/msg/B');
        await client.unsubscribeAll();
        expect(client.subscribed, isEmpty);
        expect(transport.opsOfType('unsubscribe'), hasLength(2));
      });
    });

    test('messages stream yields only publish frames', () async {
      await withClient((client, transport) async {
        final received = <Map<String, dynamic>>[];
        final sub = client.messages.listen(received.add);
        await Future<void>.delayed(Duration.zero);
        transport.emit(<String, dynamic>{
          'op': 'status',
          'level': 'warning',
          'message': 'topic not advertised',
        });
        transport.emit(<String, dynamic>{
          'op': 'publish',
          'topic': '/x',
          'msg': <String, dynamic>{'a': 1},
        });
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();
        expect(received, hasLength(1));
        expect(received.single['topic'], '/x');
      });
    });
  });

  group('reconnect', () {
    test('does not stack listeners on the transport stream', () async {
      final transport = FakeTransport();
      final client = RosClient(transport);
      await client.connect('ws://test');
      await client.connect('ws://test');
      final received = <Map<String, dynamic>>[];
      final sub = client.messages.listen(received.add);
      await Future<void>.delayed(Duration.zero);
      transport.emit(<String, dynamic>{
        'op': 'publish',
        'topic': '/x',
        'msg': <String, dynamic>{},
      });
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      await client.dispose();
      expect(received, hasLength(1));
    });

    test('disconnect fails pending calls and clears state', () async {
      final transport = FakeTransport();
      final client = RosClient(transport);
      await client.connect('ws://test');
      await client.subscribe('/a', 'pkg/msg/A');
      final future = client.callService(
          '/pending', 'std_srvs/srv/Trigger', <String, dynamic>{});
      // Attach the expectation before disconnecting: the rejection is
      // synchronous with respect to the disconnect call.
      final expectation =
          expectLater(future, throwsA(isA<RosServiceCallException>()));
      await client.disconnect();
      await expectation;
      expect(client.subscribed, isEmpty);
      expect(client.advertised, isEmpty);
    });
  });

  group('errors', () {
    test('status frames are surfaced as errors, not messages', () async {
      await withClient((client, transport) async {
        final errors = <String>[];
        final sub = client.errors.listen(errors.add);
        transport.emit(<String, dynamic>{
          'op': 'status',
          'level': 'error',
          'message': 'publish: topic not advertised',
        });
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();
        expect(errors.single, contains('topic not advertised'));
      });
    });

    test('transport failures are forwarded', () async {
      await withClient((client, transport) async {
        final errors = <String>[];
        final sub = client.errors.listen(errors.add);
        transport.emitError('socket closed');
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();
        expect(errors, <String>['socket closed']);
      });
    });
  });
}

Map<String, dynamic> _valuesFor(String service) => switch (service) {
      '/rosapi/topics' => <String, dynamic>{
          'topics': ['/uas_draw/data', '/UasDraw/joy'],
          'types': [
            'uas_draw_interfaces/msg/UasDrawDataBlock',
            'sensor_msgs/msg/Joy',
          ],
        },
      '/rosapi/services' => <String, dynamic>{
          'services': ['/UasDraw/arm'],
          'types': ['std_srvs/srv/Trigger'],
        },
      '/rosapi/nodes' => <String, dynamic>{
          'nodes': ['/rosapi', '/UasDraw/gcode_interpreter'],
        },
      _ => <String, dynamic>{},
    };