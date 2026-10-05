import 'package:flutter_test/flutter_test.dart';
import 'package:uasdraw/core/models/log_entry.dart';
import 'package:uasdraw/core/services/log_store.dart';

void main() {
  group('LogSeverity', () {
    test('maps the rcl level numbers', () {
      expect(LogSeverity.fromLevel(10), LogSeverity.debug);
      expect(LogSeverity.fromLevel(20), LogSeverity.info);
      expect(LogSeverity.fromLevel(30), LogSeverity.warn);
      expect(LogSeverity.fromLevel(40), LogSeverity.error);
      expect(LogSeverity.fromLevel(50), LogSeverity.fatal);
    });

    test('an unknown level still shows up rather than vanishing', () {
      expect(LogSeverity.fromLevel(99), LogSeverity.unknown);
      expect(LogSeverity.fromLevel(null), LogSeverity.unknown);
    });

    test('orders by severity', () {
      expect(LogSeverity.error >= LogSeverity.warn, isTrue);
      expect(LogSeverity.info >= LogSeverity.warn, isFalse);
    });
  });

  group('LogEntry', () {
    test('decodes an rcl_interfaces/msg/Log payload', () {
      final entry = LogEntry.fromRosout(<String, dynamic>{
        'stamp': <String, dynamic>{'sec': 1700000000, 'nanosec': 500000000},
        'level': 40,
        'name': '/uas_draw/gcode_interpreter',
        'msg': 'buffer underrun',
      });
      expect(entry, isNotNull);
      expect(entry!.severity, LogSeverity.error);
      expect(entry.node, '/uas_draw/gcode_interpreter');
      expect(entry.message, 'buffer underrun');
      expect(entry.stamp.millisecond, 500);
    });

    test('falls back to arrival time for an empty stamp', () {
      final before = DateTime.now().subtract(const Duration(seconds: 1));
      final entry = LogEntry.fromRosout(<String, dynamic>{
        'stamp': <String, dynamic>{'sec': 0, 'nanosec': 0},
        'level': 20,
        'msg': 'hello',
      });
      expect(entry!.stamp.isAfter(before), isTrue);
    });

    test('rejects a frame without a message', () {
      expect(LogEntry.fromRosout(<String, dynamic>{'level': 20}), isNull);
    });

    test('tolerates a missing logger name', () {
      final entry = LogEntry.fromRosout(<String, dynamic>{'msg': 'x'});
      expect(entry!.node, isEmpty);
      expect(entry.severity, LogSeverity.unknown);
    });
  });

  group('LogStore', () {
    /// Adds [count] records without waiting for the batch timer.
    void fill(LogStore store, int count,
        {LogSeverity severity = LogSeverity.info}) {
      for (var i = 0; i < count; i++) {
        store.add(
          LogEntry(
            stamp: DateTime(2026, 1, 1, 12, 0, i % 60),
            severity: severity,
            node: '/test',
            message: 'line $i',
          ),
        );
      }
    }

    test('does not notify until the batch window elapses', () {
      final store = LogStore();
      var notifications = 0;
      store.addListener(() => notifications++);

      fill(store, 500);
      expect(notifications, 0, reason: '500 records must not cost 500 rebuilds');
      expect(store.pendingCount, 500);

      // One flush covers the whole batch.
      store.add(LogEntry(
        stamp: DateTime(2026),
        severity: LogSeverity.info,
        node: '/test',
        message: 'wake up',
      ));
      return Future<void>.delayed(LogStore.flushInterval * 3, () {
        expect(notifications, 1);
        expect(store.visibleCount, 501);
      });
    });

    test('keeps arrival order', () {
      final store = LogStore();
      fill(store, 3);
      return Future<void>.delayed(LogStore.flushInterval * 3, () {
        expect(
          store.entries.map((e) => e.message).toList(),
          <String>['line 0', 'line 1', 'line 2'],
        );
      });
    });

    test('caps retained entries and counts what it dropped', () async {
      final store = LogStore();
      // Several distinct batches, each below maxPending, so the cap under test
      // is the one on retained entries rather than on the pending queue.
      for (var batch = 0; batch < 5; batch++) {
        fill(store, 1500);
        await Future<void>.delayed(LogStore.flushInterval * 2);
      }
      expect(store.retainedCount, LogStore.maxEntries);
      expect(store.droppedCount, greaterThan(0));
      expect(store.entries.first.message, isNot('line 0'),
          reason: 'the oldest records fall off the front');
    });

    test('bounds the pending queue so a starved flush cannot grow forever',
        () {
      final store = LogStore();
      fill(store, LogStore.maxPending + 100);
      expect(store.pendingCount, LogStore.maxPending);
    });

    test('clear empties retained, pending and visible records', () {
      final store = LogStore();
      fill(store, 10);
      store.clear();
      expect(store.retainedCount, 0);
      expect(store.pendingCount, 0);
      expect(store.visibleCount, 0);
      expect(store.droppedCount, 0);
    });

    test('clear also cancels a batch that had not flushed yet', () {
      final store = LogStore();
      var notifications = 0;
      store.addListener(() => notifications++);
      fill(store, 10);

      store.clear();
      return Future<void>.delayed(LogStore.flushInterval * 3, () {
        expect(store.retainedCount, 0, reason: 'cleared records must stay gone');
        expect(notifications, 1, reason: 'only the clear itself notified');
      });
    });

    test('the severity filter hides lower levels without dropping them', () {
      final store = LogStore();
      store.add(LogEntry(
        stamp: DateTime(2026),
        severity: LogSeverity.info,
        node: '/a',
        message: 'info',
      ));
      store.add(LogEntry(
        stamp: DateTime(2026),
        severity: LogSeverity.error,
        node: '/b',
        message: 'error',
      ));
      return Future<void>.delayed(LogStore.flushInterval * 2, () {
        store.setMinSeverity(LogSeverity.error);
        expect(store.visibleCount, 1);
        expect(store.retainedCount, 2, reason: 'filtering must not discard');
        expect(store.visibleAt(0).message, 'error');

        store.setMinSeverity(null);
        expect(store.visibleCount, 2);
      });
    });

    test('visibleAt counts from the newest, matching the reversed list', () {
      final store = LogStore();
      fill(store, 4);
      return Future<void>.delayed(LogStore.flushInterval * 2, () {
        expect(store.visibleAt(0).message, 'line 3');
        expect(store.visibleAt(1).message, 'line 2');
        expect(store.visibleAt(3).message, 'line 0');
      });
    });

    test('records after a disconnect are ignored rather than throwing', () {
      final store = LogStore();
      store.add(LogEntry(
        stamp: DateTime(2026),
        severity: LogSeverity.info,
        node: '/a',
        message: 'after dispose',
      ));
      store.dispose();
      expect(() => store.add(LogEntry(
            stamp: DateTime(2026),
            severity: LogSeverity.info,
            node: '/a',
            message: 'ignored',
          )), returnsNormally);
    });
  });
}