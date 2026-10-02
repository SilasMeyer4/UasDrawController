import 'dart:async';
import 'ros_transport.dart';
import 'ros_graph.dart';

/// Thin client that speaks rosbridge v2 and caches the ROS graph via rosapi.
class RosClient {
  RosClient(this._transport);

  final RosTransport _transport;
  final StreamController<Map<String, dynamic>> _incoming =
      StreamController<Map<String, dynamic>>.broadcast();
  final Map<String, Completer<Map<String, dynamic>>> _pending =
      <String, Completer<Map<String, dynamic>>>{};

  Stream<Map<String, dynamic>> get messages => _incoming.stream;
  bool get isConnected => _transport.isConnected;

  Future<void> connect(String url, {Duration? timeout}) async {
    await _transport.connect(url, timeout: timeout);
    _transport.stream().listen(_onMessage);
  }

  Future<void> disconnect() async {
    await _transport.disconnect();
  }

  void _onMessage(dynamic event) {
    if (event is Map<String, dynamic>) {
      _incoming.add(event);
      final id = event['id'] as String?;
      if (id != null && _pending.containsKey(id)) {
        _pending.remove(id)!.complete(event);
      }
    }
  }

  Future<Map<String, dynamic>> callService(
    String service,
    String type,
    Map<String, dynamic> args, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final id = _nextId();
    final op = <String, dynamic>{
      'op': 'call_service',
      'id': id,
      'service': service,
      'type': type,
      'args': args,
    };
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    await _transport.send(op);
    return completer.future.timeout(timeout);
  }

  void subscribe(String topic, String type, {int? rate, int? throttleRate, int? queueLength}) {
    final op = <String, dynamic>{
      'op': 'subscribe',
      'id': _nextId(),
      'topic': topic,
      'type': type,
      'rate': ?rate,
      'throttle_rate': ?throttleRate,
      'queue_length': ?queueLength,
    };
    unawaited(_transport.send(op));
  }

  void unsubscribe(String topic, String type) {
    final op = <String, dynamic>{
      'op': 'unsubscribe',
      'id': _nextId(),
      'topic': topic,
      'type': type,
    };
    unawaited(_transport.send(op));
  }

  void advertise(String topic, String type) {
    final op = <String, dynamic>{
      'op': 'advertise',
      'id': _nextId(),
      'topic': topic,
      'type': type,
    };
    unawaited(_transport.send(op));
  }

  void unadvertise(String topic, String type) {
    final op = <String, dynamic>{
      'op': 'unadvertise',
      'id': _nextId(),
      'topic': topic,
      'type': type,
    };
    unawaited(_transport.send(op));
  }

  void publish(String topic, Map<String, dynamic> msg) {
    final op = <String, dynamic>{
      'op': 'publish',
      'topic': topic,
      'msg': msg,
    };
    unawaited(_transport.send(op));
  }

  Future<RosGraph> fetchGraph() async {
    final topics = await callService('/rosbridge/topics', 'rosapi_msgs/srv/Topics', {});
    final services = await callService('/rosbridge/services', 'rosapi_msgs/srv/Services', {});
    final nodes = await callService('/rosbridge/nodes', 'rosapi_msgs/srv/Nodes', {});

    List<String> tlist = const [];
    List<String> ttypes = const [];
    List<String> slist = const [];
    List<String> stypes = const [];
    List<String> nlist = const [];

    final tvals = (topics['values'] as Map<String, dynamic>?);
    tlist = (tvals?['topics'] as List?)?.cast<String>() ?? const [];
    ttypes = (tvals?['types'] as List?)?.cast<String>() ?? const [];
    final svals = (services['values'] as Map<String, dynamic>?);
    slist = (svals?['services'] as List?)?.cast<String>() ?? const [];
    stypes = (svals?['types'] as List?)?.cast<String>() ?? const [];
    final nvals = (nodes['values'] as Map<String, dynamic>?);
    nlist = (nvals?['nodes'] as List?)?.cast<String>() ?? const [];

    return RosGraph(
      topics: tlist,
      types: ttypes,
      services: slist,
      serviceTypes: stypes,
      nodes: nlist,
    );
  }

  int _seq = 0;
  String _nextId() {
    _seq++;
    return 'id-$_seq';
  }
}

/// Helper to fire-and-forget.
void unawaited(Future<void> future) {}
