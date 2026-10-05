import 'package:flutter_test/flutter_test.dart';
import 'package:uasdraw/core/rosbridge/websocket_transport.dart';
import 'package:uasdraw/core/rosbridge/ros_transport.dart';

void main() {
  group('connect', () {
    test('fails when nothing is listening on the port', () async {
      final transport = WebSocketTransport();
      await expectLater(
        transport.connect('ws://127.0.0.1:1',
            timeout: const Duration(milliseconds: 300)),
        throwsA(isA<RosTransportException>().having(
          (e) => e.message,
          'message',
          contains('Could not reach rosbridge'),
        )),
      );
      expect(transport.isConnected, isFalse);
      await transport.dispose();
    });

    test('rejects a non-websocket URL scheme', () async {
      final transport = WebSocketTransport();
      await expectLater(
        transport.connect('http://localhost:9090'),
        throwsA(isA<RosTransportException>().having(
          (e) => e.message,
          'message',
          contains('ws://'),
        )),
      );
      expect(transport.isConnected, isFalse);
      await transport.dispose();
    });

    test('honours the connect timeout', () async {
      // 192.0.2.0/24 is TEST-NET-1 and is guaranteed not to answer.
      final transport = WebSocketTransport();
      final stopwatch = Stopwatch()..start();
      await expectLater(
        transport.connect('ws://192.0.2.1:9090',
            timeout: const Duration(milliseconds: 400)),
        throwsA(isA<RosTransportException>()),
      );
      stopwatch.stop();
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
      await transport.dispose();
    });
  });

  group('state', () {
    test('starts disconnected and ends disconnected', () async {
      final transport = WebSocketTransport();
      expect(transport.isConnected, isFalse);
      await transport.disconnect(); // no-op, must not throw
      await transport.dispose();
    });

    test('send is a no-op while disconnected', () async {
      final transport = WebSocketTransport();
      await transport.send(<String, dynamic>{'op': 'status'});
      await transport.dispose();
    });
  });
}