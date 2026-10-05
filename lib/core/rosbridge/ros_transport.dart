import 'dart:async';

/// Abstract byte/JSON transport for talking to a rosbridge server
/// (`rosbridge_suite`, rosbridge v2 protocol over WebSocket).
///
/// Implementations: [WebSocketTransport] for real links and [MockTransport]
/// for the offline simulation backend.
abstract class RosTransport {
  /// Opens the link.
  ///
  /// Must complete only once the socket is actually usable and must throw
  /// [RosTransportException] when the endpoint is unreachable, so callers can
  /// distinguish "connected" from "we tried".
  Future<void> connect(String url, {Duration? timeout});

  /// Closes the link. Safe to call when already closed.
  Future<void> disconnect();

  /// Server -> client frames. Decoded JSON objects when possible, otherwise the
  /// raw frame.
  Stream<dynamic> stream();

  /// Client -> server frames. Objects are JSON encoded, strings are sent as-is.
  Future<void> send(dynamic payload);

  /// Non-fatal transport problems (socket dropped, undecodable frame, ...).
  /// These do not close the stream: rosbridge reports recoverable problems
  /// (e.g. "publish: topic not advertised") this way.
  Stream<String> get errorStream;

  bool get isConnected;

  /// Releases the underlying resources. Call when the transport is discarded.
  Future<void> dispose();
}

/// Raised when the link cannot be established at all.
class RosTransportException implements Exception {
  RosTransportException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() =>
      cause == null ? 'RosTransportException: $message' : 'RosTransportException: $message ($cause)';
}