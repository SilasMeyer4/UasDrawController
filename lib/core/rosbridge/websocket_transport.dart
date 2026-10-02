import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'ros_transport.dart';

/// Real rosbridge WebSocket transport (v2 protocol).
/// Connects to `ws://<host>:<port>` (default 9090).
class WebSocketTransport implements RosTransport {
  WebSocketChannel? _channel;
  final StreamController<dynamic> _controller = StreamController<dynamic>.broadcast();
  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect(String url, {Duration? timeout}) async {
    if (_connected) return;
    final uri = Uri.parse(url);
    final channel = WebSocketChannel.connect(uri);
    _channel = channel;

    // Forward messages as decoded JSON objects or strings, depending on what arrives.
    channel.stream.listen(
      (event) {
        try {
          if (event is String) {
            final decoded = jsonDecode(event);
            _controller.add(decoded);
          } else {
            _controller.add(event);
          }
        } catch (_) {
          _controller.add(event);
        }
      },
      onDone: () {
        _connected = false;
      },
      onError: (_) {
        _connected = false;
      },
      cancelOnError: false,
    );

    // Mark connected after subscription is set up. WebSocketChannel.connect
    // completes when the socket is opened in most cases; there is no explicit
    // open event here, so we optimistically mark connected and rely on
    // onDone/onError to flip the flag on close/errors.
    _connected = true;
    if (timeout != null) {
      // Best-effort: if the socket closes within timeout due to an immediate
      // failure, the flag will be false, but callers typically just await this
      // future. For this app, reconnection is handled at a higher level.
      unawaited(Future.delayed(timeout, () {}));
    }
  }

  @override
  Future<void> disconnect() async {
    await _channel?.sink.close();
    _channel = null;
    _connected = false;
  }

  @override
  Stream<dynamic> stream() => _controller.stream;

  @override
  Future<void> send(dynamic payload) async {
    if (!_connected || _channel == null) {
      return;
    }
    if (payload is String) {
      _channel?.sink.add(payload);
    } else {
      _channel?.sink.add(jsonEncode(payload));
    }
  }
}

/// Helper to fire-and-forget a delayed callback without returning a Future
/// that callers must await.
void unawaited(Future<void> future) {}
