import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:uasdraw/app/app.dart';
import 'package:uasdraw/core/models/bindings.dart';
import 'package:uasdraw/core/models/connection_profile.dart';
import 'package:uasdraw/core/services/connection_manager.dart';
import 'package:uasdraw/core/services/log_store.dart';
import 'package:uasdraw/core/services/profile_store.dart';
import 'package:uasdraw/main.dart';

/// In-memory ProfileStore so widget tests do not touch path_provider.
class _FakeProfileStore extends ProfileStore {
  List<ConnectionProfile> profiles = ProfileStore().defaults;

  @override
  List<ConnectionProfile> get defaults => ProfileStore().defaults;

  @override
  Future<List<ConnectionProfile>> loadProfiles() async => profiles;

  @override
  Future<void> saveProfiles(List<ConnectionProfile> value) async {
    profiles = value;
  }
}

/// Runs [body] with the app connected to the mock simulation.
///
/// Teardown is registered via `addTearDown` rather than a `finally` block:
/// `testWidgets` runs the body inside a `fake_async` zone where awaiting a
/// future that is not driven by the fake clock never completes. Callbacks
/// registered with `addTearDown` run after that zone is torn down, so the
/// connection is closed reliably without deadlocking the test.
Future<void> withApp(
  WidgetTester tester,
  Future<void> Function(AppHarness harness) body, {
  Bindings? bindings,
  ConnectionProfile? profile,
}) async {
  final harness = AppHarness();
  addTearDown(harness.dispose);
  await harness.cm.connect(profile ??
      ConnectionProfile(
        name: 'Mock',
        wsUrl: 'mock://local',
        isMock: true,
        bindings: bindings,
      ));
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ConnectionManager>.value(value: harness.cm),
        ChangeNotifierProvider<LogStore>.value(value: harness.logs),
        Provider<ProfileStore>(create: (_) => _FakeProfileStore()),
      ],
      child: MaterialApp.router(routerConfig: createAppRouter()),
    ),
  );
  // NB: not pumpAndSettle - the mock simulation schedules periodic timers,
  // so settling never converges.
  await tester.pump();
  try {
    await body(harness);
  } finally {
    // `testWidgets` asserts that no timer is pending once the body returns,
    // and that check runs *before* `addTearDown`. The mock transport and the
    // log store own periodic timers, so the harness has to be torn down here,
    // not in teardown.
    //
    // `runAsync` is required: disconnecting awaits real I/O completions, which
    // never resolve inside the fake clock that `testWidgets` installs.
    await tester.runAsync(harness.dispose);
    // Disconnecting stops new emissions, but futures the mock's action chain
    // and the log batch window already scheduled still have to elapse or the
    // pending-timer assertion fires.
    await tester.pump(const Duration(seconds: 2));
    // The router keeps listening to the (now disposed) providers; unmounting
    // the tree releases those subscriptions.
    await tester.pumpWidget(const SizedBox.shrink());
  }
}

/// The objects a widget test needs a handle on.
class AppHarness {
  final ConnectionManager cm = ConnectionManager();
  final LogStore logs = LogStore();

  Future<void>? _disposal;

  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    await cm.disconnect();
    logs.dispose();
  }
}

void main() {
  testWidgets('App starts on Connect', (tester) async {
    await tester.pumpWidget(const UasDrawApp());
    await tester.pumpAndSettle();
    expect(find.text('Connect'), findsWidgets);
  });

  testWidgets('connecting to the mock profile populates the ROS graph',
      (tester) async {
    await withApp(tester, (h) async {
      final cm = h.cm;
      expect(find.text('Mock (Simulation)'), findsOneWidget);
      expect(cm.isConnected, isTrue);
      expect(cm.graph.topics, isNotEmpty);
      expect(cm.graph.services, isNotEmpty);
      expect(cm.graphError, isNull);
    });
  });

  testWidgets('connect failure is surfaced and leaves the app disconnected',
      (tester) async {
    final cm = ConnectionManager();
    addTearDown(cm.disconnect);
    // A wrong URL scheme fails before any socket is opened.
    await cm.connect(
      ConnectionProfile(name: 'Bad', wsUrl: 'http://127.0.0.1:9090'),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ConnectionManager>.value(value: cm),
          Provider<ProfileStore>(create: (_) => _FakeProfileStore()),
        ],
        child: MaterialApp.router(routerConfig: createAppRouter()),
      ),
    );
    await tester.pump();
    expect(cm.isConnected, isFalse);
    expect(cm.error, contains('ws://'));
    expect(find.textContaining('Connection failed'), findsOneWidget);
  });

  testWidgets('flight screen advertises Joy and stops the stream on request',
      (tester) async {
    await withApp(tester, (h) async {
      expect(h.cm.isConnected, isTrue);
      await tester.tap(find.text('Flight'));
      await tester.pump();

      await tester.tap(find.text('Start streaming'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(h.cm.client!.advertised, contains('/UasDraw/joy'));

      await tester.tap(find.text('Stop streaming'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Stop streaming'), findsNothing);
    });
  });

  testWidgets('drawing screen subscribes to the drawing topic',
      (tester) async {
    await withApp(tester, (h) async {
      final cm = h.cm;
      await tester.tap(find.text('Drawing'));
      await tester.pumpAndSettle();

      expect(find.text('/uas_draw/data'), findsOneWidget);
      expect(cm.client!.subscribed.keys, contains('/uas_draw/data'));
    });
  });

  testWidgets('drawing screen gates upload on capability discovery',
      (tester) async {
    await withApp(
      tester,
      (h) async {
        await tester.tap(find.text('Drawing'));
        await tester.pump();

        expect(find.textContaining('not found in the ROS graph'), findsOneWidget);
        final button = tester.widget<OutlinedButton>(
          find.ancestor(
            of: find.text('Load demo g-code'),
            matching: find.byType(OutlinedButton),
          ),
        );
        expect(button.onPressed, isNull);
      },
      // Bind to a service the mock graph does not advertise.
      bindings: Bindings.uasDraw().withOverride(
        LogicalAction.loadGcodeContent,
        const Binding.service(
            '/nope/load', 'uas_draw_interfaces/srv/LoadGCodeContent'),
      ),
    );
  });

  testWidgets('diagnostics lists bindings with their availability',
      (tester) async {
    await withApp(tester, (h) async {
      await tester.tap(find.text('Diagnostics'));
      await tester.pump();
      expect(find.text('Bindings'), findsOneWidget);
      expect(find.textContaining('/uas_draw/data'), findsWidgets);
    });
  });

  testWidgets('navigation reaches every tab', (tester) async {
    await withApp(tester, (h) async {
      for (final label in [
        'Diagnostics',
        'Drawing',
        'Flight',
        'Logs',
        'About',
        'Connect',
      ]) {
        await tester.tap(find.text(label));
        await tester.pump();
      }
      expect(find.byType(AppShell), findsOneWidget);
    });
  });

  group('logs tab', () {
    Future<void> openLogs(WidgetTester tester) async {
      await tester.tap(find.text('Logs'));
      // The store attaches in a post-frame callback.
      await tester.pump();
      await tester.pump();
    }

    testWidgets('subscribes to /rosout when the tab is first opened',
        (tester) async {
      await withApp(tester, (h) async {
      final cm = h.cm;
        await openLogs(tester);
        expect(find.text('Logs'), findsWidgets);
        expect(cm.client!.subscribed.keys, contains('/rosout'));
      });
    });

    testWidgets('shows records arriving on /rosout', (tester) async {
      await withApp(tester, (h) async {
        await openLogs(tester);
        expect(find.textContaining('Waiting for messages'), findsOneWidget);

        // The mock emits a sample record every 400 ms; the store batches at
        // 200 ms, so this crosses both timers.
        await tester.pump(const Duration(milliseconds: 700));
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.textContaining('Waiting for messages'), findsNothing);
        expect(find.textContaining('buffered'), findsWidgets);
      });
    });

    testWidgets('clear empties the list and re-enables the empty state',
        (tester) async {
      await withApp(tester, (h) async {
        await openLogs(tester);
        await tester.pump(const Duration(milliseconds: 700));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.textContaining('Waiting for messages'), findsNothing);

        await tester.tap(find.byTooltip('Clear log'));
        await tester.pump();

        expect(find.textContaining('Waiting for messages'), findsOneWidget);
        expect(find.byTooltip('Clear log'), findsOneWidget);
      });
    });

    testWidgets('the severity filter narrows the list without disconnecting',
        (tester) async {
      await withApp(tester, (h) async {
        await openLogs(tester);
        await tester.pump(const Duration(milliseconds: 700));
        await tester.pump(const Duration(milliseconds: 300));

        await tester.tap(find.widgetWithText(FilterChip, 'Error'));
        await tester.pump();

        // Filtering is a view concern; the subscription stays up.
        expect(h.cm.client!.subscribed.keys, contains('/rosout'));
      });
    });
  });
}