/// Snapshot of the ROS graph as reported by the `rosapi` node, queried through
/// the `/rosapi/topics`, `/rosapi/services` and `/rosapi/nodes` services.
class RosGraph {
  /// topic name -> fully qualified type
  final Map<String, String> topics;

  /// service name -> fully qualified type
  final Map<String, String> services;

  final List<String> nodes;

  const RosGraph({
    this.topics = const {},
    this.services = const {},
    this.nodes = const [],
  });

  bool get isEmpty => topics.isEmpty && services.isEmpty && nodes.isEmpty;

  bool hasTopic(String name) => topics.containsKey(name);

  bool hasService(String name) => services.containsKey(name);

  String? topicType(String name) => topics[name];

  String? serviceType(String name) => services[name];

  /// `name` and `type` separated by a tab, sorted, ready for a text list.
  List<String> describeTopics() => _describe(topics);

  List<String> describeServices() => _describe(services);

  List<String> get describeNodes => [...nodes]..sort();

  static List<String> _describe(Map<String, String> source) {
    final keys = source.keys.toList()..sort();
    return [for (final k in keys) '$k\t${source[k] ?? ''}'.trimRight()];
  }
}