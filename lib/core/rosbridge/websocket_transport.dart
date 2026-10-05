import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'ros_transport.dart';

/// Real rosbridge WebSocket transport (rosbridge_suite v2 protocol).
///
/// Connects to `ws://<host>:9090` (the default port of
/// `ros2 launch rosbridge_server rosbridge_websocket_launch.xml`).
class WebSocketTransport implements RosTransport {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  final StreamController<dynamic> _incoming =
      StreamController<dynamic>.broadcast();
  final StreamController<String> _errors =
      StreamController<String>.broadcast();
  bool _connected = false;
  String? _url;

  @override
  bool get isConnected => _connected;

  /// URL of the currently open link, or the last attempted one.
  String? get url => _url;

  @override
  Stream<dynamic> stream() => _incoming.stream;

  @override
  Stream<String> get errorStream => _errors.stream;

  @override
  Future<void> connect(
    String url, {
    Duration? timeout = const Duration(seconds: 5),
  }) async {
    if (_connected) return;
    await disconnect();
    _url = url;

    final uri = Uri.parse(url);
    if (!uri.hasScheme || (uri.scheme != 'ws' && uri.scheme != 'wss')) {
      throw RosTransportException(
        'Invalid rosbridge URL "$url": expected ws://host:9090 or wss://...',
      );
    }

    final channel = WebSocketChannel.connect(uri);
    try {
      // `ready` is the only reliable "the socket is actually usable" signal:
      // `WebSocketChannel.connect` itself completes immediately, so a wrong IP
      // would otherwise look like a successful connection.
      final ready = channel.ready;
      if (timeout != null) {
        await ready.timeout(timeout);
      } else {
        await ready;
      }
    } on Object catch (err) {
      // Do not await the close: when the handshake never completed, closing the
      // sink blocks until the OS gives up on the TCP connection, which would
      // make a failed connect hang long past its own timeout.
      unawaited(channel.sink.close().catchError((Object _) {}));
      throw RosTransportException(
        'Could not reach rosbridge at $url. Check that rosbridge is running, '
        'that the port (9090) is reachable, and that any firewall allows it.',
        err,
      );
    }

    _channel = channel;
    _sub = channel.stream.listen(
      _onFrame,
      onDone: () => _onClosed('rosbridge closed the connection'),
      onError: (Object err) => _onClosed('rosbridge connection error: $err'),
      cancelOnError: false,
    );
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    final sub = _sub;
    final channel = _channel;
    _sub = null;
    _channel = null;
    await sub?.cancel();
    try {
      await channel?.sink.close();
    } catch (_) {
      // Already gone.
    }
  }

  @override
  Future<void> send(dynamic payload) async {
    if (!_connected || _channel == null) return;
    try {
      if (payload is String) {
        _channel!.sink.add(payload);
      } else {
        _channel!.sink.add(jsonEncode(payload));
      }
    } on Object catch (err) {
      _emitError('failed to send frame: $err');
    }
  }

  void _onFrame(dynamic event) {
    if (_incoming.isClosed) return;
    if (event is String) {
      try {
        _incoming.add(jsonDecode(event));
        return;
      } on FormatException catch (err) {
        _emitError('received a non-JSON frame: $err');
        return;
      }
    }
    _incoming.add(event);
  }

  void _onClosed(String reason) {
    if (!_connected) return;
    _connected = false;
    _emitError(reason);
  }

  void _emitError(String message) {
    if (_errors.isClosed) return;
    _errors.add(message);
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    // Do not await: a broadcast controller's close future only completes once
    // the done event is delivered, which never happens under fake async.
    unawaited(_incoming.close());
    unawaited(_errors.close());
  }
}