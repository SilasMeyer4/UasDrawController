
/// Abstract transport for communicating with rosbridge.
/// Implementations: [WebSocketTransport] and [MockTransport].
abstract class RosTransport {
  Future<void> connect(String url, {Duration? timeout});
  Future<void> disconnect();
  Stream<dynamic> stream();
  Future<void> send(dynamic payload);
  bool get isConnected;
}
