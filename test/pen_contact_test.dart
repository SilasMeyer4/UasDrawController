import 'package:flutter_test/flutter_test.dart';
import 'package:uasdraw/core/models/pen_contact.dart';
import 'package:uasdraw/core/services/pen_trace_store.dart';

Map<String, dynamic> contactMessage({
  String first = 'x500_uas_draw::pen_link::pen_tip_collision',
  String second = 'drawing_wall::wall_link::wall_collision',
  List<Map<String, dynamic>> positions = const <Map<String, dynamic>>[
    <String, dynamic>{'x': 2.95, 'y': 0.5, 'z': 1.5},
  ],
}) =>
    <String, dynamic>{
      'contacts': <Map<String, dynamic>>[
        <String, dynamic>{
          'collision1': <String, dynamic>{'id': 1, 'name': first, 'type': 5},
          'collision2': <String, dynamic>{'id': 2, 'name': second, 'type': 5},
          'positions': positions,
        },
      ],
    };

void main() {
  group('WallBounds', () {
    const bounds = WallBounds();

    test('maps wall corners to the canvas', () {
      expect(bounds.normalize(y: 2, z: 3), const Offset(0, 0));
      expect(bounds.normalize(y: -2, z: 0), const Offset(1, 1));
      expect(bounds.normalize(y: 0, z: 1.5), const Offset(0.5, 0.5));
    });

    test('clamps contacts outside the wall to the canvas edge', () {
      expect(bounds.normalize(y: 10, z: 10), const Offset(0, 0));
      expect(bounds.normalize(y: -10, z: -10), const Offset(1, 1));
    });
  });

  group('parsePenContact', () {
    test('extracts the pen position from scoped Gazebo names', () {
      final samples = parsePenContact(contactMessage());
      expect(samples, hasLength(1));
      expect(samples.single.y, 0.5);
      expect(samples.single.z, 1.5);
    });

    test('accepts the wall as collision1 and pen as collision2', () {
      final samples = parsePenContact(
        contactMessage(
          first: 'drawing_wall::wall_link::wall_collision',
          second: 'x500_uas_draw::pen_link::pen_tip_collision',
        ),
      );
      expect(samples, hasLength(1));
    });

    test('averages every penetration point in a manifold', () {
      final samples = parsePenContact(
        contactMessage(
          positions: const <Map<String, dynamic>>[
            <String, dynamic>{'x': 2.95, 'y': 0.0, 'z': 1.0},
            <String, dynamic>{'x': 2.95, 'y': 1.0, 'z': 2.0},
          ],
        ),
      );
      expect(samples.single.y, 0.5);
      expect(samples.single.z, 1.5);
    });

    test('ignores contacts that do not involve the pen and wall', () {
      final samples = parsePenContact(
        contactMessage(first: 'drone::body', second: 'ground::plane'),
      );
      expect(samples, isEmpty);
    });

    test('returns nothing for an empty or malformed message', () {
      expect(
        parsePenContact(<String, dynamic>{'contacts': <Object>[]}),
        isEmpty,
      );
      expect(parsePenContact(<String, dynamic>{}), isEmpty);
      expect(parsePenContact(<String, dynamic>{'contacts': 'nope'}), isEmpty);
      expect(
        parsePenContact(
          contactMessage(positions: const <Map<String, dynamic>>[]),
        ),
        isEmpty,
      );
    });
  });

  group('PenTraceStore', () {
    late PenTraceStore store;

    setUp(() {
      store = PenTraceStore(minPointSpacing: 0);
    });

    tearDown(() => store.dispose());

    test('records a contact as a point on the canvas', () {
      store.ingest(contactMessage(), now: DateTime(2026, 1, 1));

      expect(store.pointCount, 1);
      expect(store.strokeCount, 1);
      expect(store.isContacting, isTrue);
      expect(store.strokes.single.points.single, const Offset(0.375, 0.5));
    });

    test('extends the same stroke while contact continues', () {
      final start = DateTime(2026, 1, 1);
      store.ingest(contactMessage(), now: start);
      store.ingest(
        contactMessage(
          positions: const <Map<String, dynamic>>[
            <String, dynamic>{'x': 2.95, 'y': 1.0, 'z': 1.5},
          ],
        ),
        now: start.add(const Duration(milliseconds: 100)),
      );

      expect(store.pointCount, 2);
      expect(store.strokeCount, 1);
    });

    test('a contact message without contacts ends the stroke', () {
      store.ingest(contactMessage(), now: DateTime(2026, 1, 1));
      store.ingest(<String, dynamic>{'contacts': <Object>[]});

      expect(store.isContacting, isFalse);
      expect(store.activeStroke, isNull);
      expect(store.pointCount, 1);

      store.ingest(contactMessage(), now: DateTime(2026, 1, 1));
      expect(store.strokeCount, 2);
    });

    test('a long pause starts a new stroke even without a lift message', () {
      final start = DateTime(2026, 1, 1);
      store.ingest(contactMessage(), now: start);
      store.ingest(
        contactMessage(),
        now: start.add(const Duration(milliseconds: 600)),
      );

      expect(store.strokeCount, 2);
      expect(store.pointCount, 2);
    });

    test('near-identical samples do not flood the canvas', () {
      store.dispose();
      store = PenTraceStore(minPointSpacing: 0.01);
      final start = DateTime(2026, 1, 1);
      store.ingest(contactMessage(), now: start);
      store.ingest(
        contactMessage(),
        now: start.add(const Duration(milliseconds: 50)),
      );

      expect(store.pointCount, 1);
    });

    test('clear removes every stroke and resets the indicator', () {
      store.ingest(contactMessage(), now: DateTime(2026, 1, 1));
      store.clear();

      expect(store.pointCount, 0);
      expect(store.strokeCount, 0);
      expect(store.strokes, isEmpty);
      expect(store.isContacting, isFalse);
    });
  });
}
