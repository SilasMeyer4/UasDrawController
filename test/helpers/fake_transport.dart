import 'dart:async';

import 'package:uasdraw/core/rosbridge/ros_client.dart';
import 'package:uasdraw/core/rosbridge/ros_transport.dart';

/// A RosTransport test double that records outgoing frames and lets the test
/// inject incoming frames.
class FakeTransport implements RosTransport {
  final List<Map<String, dynamic>> sent = <Map<String, dynamic>>[];
  final StreamController<dynamic> _incoming =
      StreamController<dynamic>.broadcast();
  final StreamController<String> _errors =
      StreamController<String>.broadcast();
  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  Stream<dynamic> stream() => _incoming.stream;

  @override
  Stream<String> get errorStream => _errors.stream;

  @override
  Future<void> connect(String url, {Duration? timeout}) async {
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
  }

  /// Auto-replies to every `call_service` with [onServiceCall], letting a test
  /// drive a whole multi-call sequence such as `fetchGraph()`.
  Map<String, dynamic> Function(String service, Map<String, dynamic> args)?
      onServiceCall;

  @override
  Future<void> send(dynamic payload) async {
    if (payload is! Map<String, dynamic>) return;
    sent.add(payload);
    final responder = onServiceCall;
    if (responder == null || payload['op'] != 'call_service') return;
    final service = payload['service'] as String;
    final args = (payload['args'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    // Reply asynchronously, like a real node would.
    Future<void>.microtask(() {
      emit(serviceResponse(
        payload['id'] as String,
        service,
        responder(service, args),
      ));
    });
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    unawaited(_incoming.close());
    unawaited(_errors.close());
  }

  void emit(Map<String, dynamic> frame) => _incoming.add(frame);

  void emitError(String message) => _errors.add(message);

  Map<String, dynamic> lastOp(String op) =>
      sent.lastWhere((frame) => frame['op'] == op);

  List<Map<String, dynamic>> opsOfType(String op) =>
      sent.where((frame) => frame['op'] == op).toList();
}

/// Convenience: a `service_response` frame for [id].
Map<String, dynamic> serviceResponse(
  String id,
  String service,
  Map<String, dynamic> values, {
  bool result = true,
}) =>
    <String, dynamic>{
      'op': 'service_response',
      'id': id,
      'service': service,
      'values': values,
      'result': result,
    };

/// Runs [body] with a connected FakeTransport + RosClient.
Future<T> withClient<T>(
  Future<T> Function(RosClient client, FakeTransport transport) body,
) async {
  final transport = FakeTransport();
  final client = RosClient(transport);
  await client.connect('ws://test');
  try {
    return await body(client, transport);
  } finally {
    await client.dispose();
  }
}