/// ROS topic/service/node graph metadata as returned by rosapi.
class RosGraph {
  final List<String> topics;
  final List<String> types;
  final List<String> services;
  final List<String> serviceTypes;
  final List<String> nodes;

  RosGraph({
    this.topics = const [],
    this.types = const [],
    this.services = const [],
    this.serviceTypes = const [],
    this.nodes = const [],
  });

  RosGraph copyWith({
    List<String>? topics,
    List<String>? types,
    List<String>? services,
    List<String>? serviceTypes,
    List<String>? nodes,
  }) {
    return RosGraph(
      topics: topics ?? this.topics,
      types: types ?? this.types,
      services: services ?? this.services,
      serviceTypes: serviceTypes ?? this.serviceTypes,
      nodes: nodes ?? this.nodes,
    );
  }
}
