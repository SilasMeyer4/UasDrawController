import 'bindings.dart';

/// Connection profile describing how to reach the drone/ROS system, plus the
/// ROS names that profile should use.
class ConnectionProfile {
  ConnectionProfile({
    required this.name,
    required this.wsUrl,
    this.isMock = false,
    Bindings? bindings,
  }) : bindings = bindings ?? Bindings.uasDraw();

  final String name;

  /// rosbridge WebSocket endpoint, e.g. `ws://192.168.1.10:9090`.
  final String wsUrl;

  /// When true the in-app [MockTransport] simulation is used and `wsUrl` is
  /// ignored.
  final bool isMock;

  final Bindings bindings;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'wsUrl': wsUrl,
        'isMock': isMock,
        'bindings': bindings.toJson(),
      };

  static ConnectionProfile fromJson(Map<String, dynamic> json) {
    final rawBindings = (json['bindings'] as Map?)?.cast<String, dynamic>();
    return ConnectionProfile(
      name: json['name'] as String? ?? 'Unnamed',
      wsUrl: json['wsUrl'] as String? ?? 'ws://localhost:9090',
      isMock: json['isMock'] as bool? ?? false,
      bindings: rawBindings == null
          ? Bindings.uasDraw()
          : Bindings.fromJson(rawBindings),
    );
  }

  ConnectionProfile copyWith({
    String? name,
    String? wsUrl,
    bool? isMock,
    Bindings? bindings,
  }) =>
      ConnectionProfile(
        name: name ?? this.name,
        wsUrl: wsUrl ?? this.wsUrl,
        isMock: isMock ?? this.isMock,
        bindings: bindings ?? this.bindings,
      );
}