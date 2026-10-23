import 'dart:ui' show Offset;

/// The vertical drawing wall from `uas_draw.sdf`, expressed in world metres.
///
/// The wall is a static box at `(3.0, 0.0, 1.5)` with size
/// `0.10 x 4.0 x 3.0 m`, so the pen can reach `y` in `[-2, 2]` and `z` in
/// `[0, 3]`. Keeping the bounds in one object makes it easy to adapt the canvas
/// if the world changes later.
class WallBounds {
  const WallBounds({
    this.minY = -2.0,
    this.maxY = 2.0,
    this.minZ = 0.0,
    this.maxZ = 3.0,
  });

  final double minY;
  final double maxY;
  final double minZ;
  final double maxZ;

  double get width => maxY - minY;
  double get height => maxZ - minZ;

  /// Maps a world-space contact point onto the wall as a normalized offset.
  ///
  /// `0,0` is the top-left corner and `1,1` the bottom-right corner when the
  /// wall is viewed from the drone side. In that view `+Y` points left and
  /// `+Z` points up, hence the inverted axes.
  Offset normalize({required double y, required double z}) {
    final u = ((maxY - y) / width).clamp(0.0, 1.0);
    final v = ((maxZ - z) / height).clamp(0.0, 1.0);
    return Offset(u, v);
  }
}

/// One averaged pen-tip position from a contact message.
class PenContactSample {
  const PenContactSample({required this.y, required this.z});

  final double y;
  final double z;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PenContactSample && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(y, z);

  @override
  String toString() => 'PenContactSample(y: $y, z: $z)';
}

/// Collision name fragments from `x500_uas_draw/model.sdf`.
///
/// Gazebo may prefix these with the model/link scope, so callers match by
/// substring rather than by exact name.
const String penTipCollisionName = 'pen_tip_collision';
const String wallCollisionName = 'wall_collision';

/// Extracts the pen/wall contact point from a `ros_gz_interfaces/msg/Contacts`
/// message decoded by rosbridge.
///
/// A contact message can contain several penetration points for the sphere and
/// can report the two collisions in either order. The positions are averaged
/// so one message produces one stable pen-tip sample. Returns an empty list
/// when the message has no pen/wall contact.
List<PenContactSample> parsePenContact(Map<String, dynamic> msg) {
  final rawContacts = msg['contacts'];
  if (rawContacts is! List) return const <PenContactSample>[];

  var sumY = 0.0;
  var sumZ = 0.0;
  var count = 0;

  for (final raw in rawContacts) {
    if (raw is! Map) continue;
    final contact =
        raw is Map<String, dynamic> ? raw : raw.cast<String, dynamic>();

    final first = _entityName(contact['collision1']);
    final second = _entityName(contact['collision2']);
    final penFirst = first.contains(penTipCollisionName) &&
        second.contains(wallCollisionName);
    final wallFirst = second.contains(penTipCollisionName) &&
        first.contains(wallCollisionName);
    if (!penFirst && !wallFirst) continue;

    final positions = contact['positions'];
    if (positions is! List) continue;
    for (final position in positions) {
      if (position is! Map) continue;
      final y = position['y'];
      final z = position['z'];
      if (y is! num || z is! num) continue;
      sumY += y.toDouble();
      sumZ += z.toDouble();
      count++;
    }
  }

  if (count == 0) return const <PenContactSample>[];
  return <PenContactSample>[PenContactSample(y: sumY / count, z: sumZ / count)];
}

String _entityName(Object? raw) {
  if (raw is! Map) return '';
  final name = raw['name'];
  return name is String ? name : '';
}
