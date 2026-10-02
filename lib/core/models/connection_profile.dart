/// Connection profile describing how to reach the drone/ROS system.
class ConnectionProfile {
  final String name;
  final String wsUrl; // e.g. ws://192.168.1.10:9090
  final bool isMock;

  ConnectionProfile({
    required this.name,
    required this.wsUrl,
    this.isMock = false,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'wsUrl': wsUrl,
        'isMock': isMock,
      };

  static ConnectionProfile fromJson(Map<String, dynamic> json) {
    return ConnectionProfile(
      name: json['name'] as String? ?? 'Unnamed',
      wsUrl: json['wsUrl'] as String? ?? 'ws://localhost:9090',
      isMock: json['isMock'] as bool? ?? false,
    );
  }

  ConnectionProfile copyWith({
    String? name,
    String? wsUrl,
    bool? isMock,
  }) {
    return ConnectionProfile(
      name: name ?? this.name,
      wsUrl: wsUrl ?? this.wsUrl,
      isMock: isMock ?? this.isMock,
    );
  }
}
