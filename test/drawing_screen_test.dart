import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uasdraw/core/models/bindings.dart';

import 'widget_test.dart' show withApp;

/// Scrolls [finder] into view.
///
/// The Drawing screen is one long `ListView` whose children are built lazily,
/// so controls further down do not exist in the tree until scrolled to.
///
/// This jumps the scroll position rather than dragging: the screen is full of
/// sliders and dropdowns, and a finger-based drag that lands on one of those
/// is claimed by its gesture recogniser and never scrolls the list.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  final state = tester.state<ScrollableState>(find.byType(Scrollable));
  for (var step = 0; step < 200; step++) {
    if (finder.evaluate().isNotEmpty) break;
    final position = state.position;
    if (position.pixels >= position.maxScrollExtent) break;
    position.jumpTo(position.pixels + 120);
    // maxScrollExtent grows as the sliver builds more children.
    await tester.pump();
  }
  expect(finder, findsWidgets, reason: 'could not scroll to the target');
  await tester.ensureVisible(finder);
  await tester.pump();
}

/// The button ancestor of [label].
Finder buttonFor(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );

/// The `Draw picture` action button, found by its play icon because the card
/// title carries the same text.
Finder get drawButton => find.ancestor(
      of: find.byIcon(Icons.play_arrow),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );

/// [button]'s callback, or null when the button is disabled.
VoidCallback? callbackOf(WidgetTester tester, Finder button) =>
    tester.widget<ButtonStyleButton>(button).onPressed;

/// A profile that binds nothing but the data topic, so every command button is
/// gated off.
final Bindings unbound = Bindings(<LogicalAction, Binding>{
  LogicalAction.drawData: Binding.topic(
    '/uas_draw/data',
    'uas_draw_interfaces/msg/UasDrawDataBlock',
  ),
});

Future<void> openDrawing(WidgetTester tester) async {
  await tester.tap(find.text('Drawing'));
  await tester.pump();
}

void main() {
  group('run control', () {
    testWidgets('Pause reports success from the node', (tester) async {
      await withApp(tester, (h) async {
        await openDrawing(tester);
        await scrollTo(tester, find.text('Pause'));
        await tester.tap(buttonFor('Pause'));
        await tester.pump();

        await scrollTo(tester, find.text('Pause: ok'));
        expect(find.text('Pause: ok'), findsOneWidget);
      });
    });

    testWidgets('Resume reports success from the node', (tester) async {
      await withApp(tester, (h) async {
        await openDrawing(tester);
        await scrollTo(tester, find.text('Resume'));
        await tester.tap(buttonFor('Resume'));
        await tester.pump();

        await scrollTo(tester, find.text('Resume: ok'));
        expect(find.text('Resume: ok'), findsOneWidget);
      });
    });

    testWidgets('Cancel drawing reports success', (tester) async {
      await withApp(tester, (h) async {
        await openDrawing(tester);
        await scrollTo(tester, find.text('Cancel drawing'));
        await tester.tap(buttonFor('Cancel drawing'));
        await tester.pump();

        // Cancel returns a Result with a message, so it is not just 'ok'.
        await scrollTo(tester, find.text('Cancel drawing: drawing cancelled'));
        expect(find.text('Cancel drawing: drawing cancelled'), findsOneWidget);
      });
    });
  });

  group('pen and context', () {
    testWidgets('Set pen sends the selected values and reports success',
        (tester) async {
      await withApp(tester, (h) async {
        await openDrawing(tester);
        await scrollTo(tester, find.text('Pen'));

        // Change the pen type so the request cannot pass by accident.
        await tester.tap(find.byType(DropdownButtonFormField<int>));
        await tester.pump();
        await tester.tap(find.byType(DropdownMenuItem<int>).last);
        await tester.pump();
        await tester.pumpAndSettle();

        await scrollTo(tester, find.text('Set pen'));
        await tester.tap(buttonFor('Set pen'));
        await tester.pump();

        await scrollTo(tester, find.text('Set pen: ok'));
        expect(find.text('Set pen: ok'), findsOneWidget);
      });
    });

    testWidgets('Apply context reports success', (tester) async {
      await withApp(tester, (h) async {
        await openDrawing(tester);
        await scrollTo(tester, find.text('Apply context'));
        await tester.tap(buttonFor('Apply context'));
        await tester.pump();

        await scrollTo(tester, find.text('Apply context: ok'));
        expect(find.text('Apply context: ok'), findsOneWidget);
      });
    });
  });

  group('positions', () {
    testWidgets('Set home stores the returned point', (tester) async {
      await withApp(tester, (h) async {
        await openDrawing(tester);
        await scrollTo(tester, find.text('Set home'));
        expect(find.text('Home: not set'), findsOneWidget);

        await tester.tap(buttonFor('Set home'));
        await tester.pump();

        expect(find.text('Home: (0.00, 0.00, 0.00)'), findsOneWidget);
      });
    });

    testWidgets('Set origin stores the returned point', (tester) async {
      await withApp(tester, (h) async {
        await openDrawing(tester);
        await scrollTo(tester, find.text('Set origin'));
        await tester.tap(buttonFor('Set origin'));
        await tester.pump();

        expect(find.text('Origin: (50.00, 50.00, -0.50)'), findsOneWidget);
      });
    });
  });

  group('DrawPicture action', () {
    testWidgets('the card names the bound goal and type', (tester) async {
      await withApp(tester, (h) async {
        await openDrawing(tester);
        await scrollTo(tester, drawButton);
        // Name and type are rendered as one two-line Text.
        expect(
          find.text('/uas_draw/draw_picture\n'
              'uas_draw_interfaces/action/DrawPicture'),
          findsOneWidget,
        );
      });
    });

    testWidgets('starting a goal offers cancel and then shows feedback',
        (tester) async {
      await withApp(tester, (h) async {
        await openDrawing(tester);
        await scrollTo(tester, drawButton);
        expect(find.text('Cancel goal'), findsNothing);

        await tester.tap(drawButton);
        await tester.pump();
        expect(find.text('Cancel goal'), findsOneWidget);

        // The mock streams feedback; advance past its tick.
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        expect(find.textContaining('line '), findsOneWidget);
      });
    });

    testWidgets('a finished goal clears the running state', (tester) async {
      await withApp(tester, (h) async {
        await openDrawing(tester);
        await scrollTo(tester, drawButton);
        await tester.tap(drawButton);
        await tester.pump();
        expect(find.text('Cancel goal'), findsOneWidget);

        // Long enough for the mock's feedback and result.
        await tester.pump(const Duration(seconds: 3));
        await tester.pump();

        expect(find.text('Cancel goal'), findsNothing);
        await scrollTo(tester, find.text('Picture drawn'));
        expect(find.text('Picture drawn'), findsOneWidget);
      });
    });

    testWidgets('cancelling the goal returns to the idle state',
        (tester) async {
      await withApp(tester, (h) async {
        await openDrawing(tester);
        await scrollTo(tester, drawButton);
        await tester.tap(drawButton);
        await tester.pump();

        await tester.tap(find.text('Cancel goal'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 3));
        await tester.pump();

        expect(find.text('Cancel goal'), findsNothing);
        await scrollTo(tester, find.text('Picture failed'));
        expect(find.text('Picture failed'), findsOneWidget);
      });
    });

    testWidgets('an unbound DrawPicture disables the button', (tester) async {
      await withApp(
        tester,
        (h) async {
          await openDrawing(tester);
          await scrollTo(tester, drawButton);
          // A topic binding is not an action, so the goal cannot be sent.
          expect(find.textContaining('/nope/draw'), findsOneWidget);
          expect(callbackOf(tester, drawButton), isNull);
        },
        bindings: Bindings.uasDraw().withOverride(
          LogicalAction.drawPicture,
          const Binding.topic('/nope/draw', 'std_msgs/msg/Bool'),
        ),
      );
    });
  });

  group('capability gating', () {
    testWidgets('run control buttons are disabled without bindings',
        (tester) async {
      await withApp(
        tester,
        (h) async {
          await openDrawing(tester);
          await scrollTo(tester, find.text('Pause'));
          for (final label in ['Pause', 'Resume', 'Cancel drawing']) {
            expect(callbackOf(tester, buttonFor(label)), isNull,
                reason: '$label must be gated on graph discovery');
          }
        },
        bindings: unbound,
      );
    });

    testWidgets('pressing a disabled control produces no status line',
        (tester) async {
      await withApp(
        tester,
        (h) async {
          await openDrawing(tester);
          await scrollTo(tester, find.text('Pause'));
          await tester.tap(buttonFor('Pause'), warnIfMissed: false);
          await tester.pump();

          expect(find.textContaining('Pause:'), findsNothing);
        },
        bindings: unbound,
      );
    });

    testWidgets('SetPen and SetDrawingContext are gated too', (tester) async {
      await withApp(
        tester,
        (h) async {
          await openDrawing(tester);
          await scrollTo(tester, find.text('Set pen'));
          expect(callbackOf(tester, buttonFor('Set pen')), isNull);
          await scrollTo(tester, find.text('Apply context'));
          expect(callbackOf(tester, buttonFor('Apply context')), isNull);
        },
        bindings: unbound,
      );
    });
  });

  testWidgets('leaving the Drawing tab drops its subscriptions',
      (tester) async {
    await withApp(tester, (h) async {
      await openDrawing(tester);
      expect(h.cm.client!.subscribed.keys, contains('/uas_draw/data'));

      await tester.tap(find.text('About'));
      // The unsubscribe is sent from dispose; give the async gap a turn.
      await tester.pump();
      await tester.pump();
      expect(h.cm.client!.subscribed.keys, isNot(contains('/uas_draw/data')));
      expect(h.cm.client!.subscribed.keys, isNot(contains('/uas_draw/buffer_status')));
    });
  });

  testWidgets('the status card tracks /uas_draw/data and BufferStatus',
      (tester) async {
    await withApp(tester, (h) async {
      await openDrawing(tester);
      expect(find.textContaining('Waiting for data'), findsOneWidget);

      // The mock publishes data every 500 ms and buffer status every 800 ms.
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump();

      expect(find.textContaining('Waiting for data'), findsNothing);
      expect(
        find.textContaining('X=1.00 Y=1.00 Z=-0.50'),
        findsOneWidget,
        reason: 'the position from the data topic must reach the screen',
      );
      expect(find.textContaining('buffer free='), findsOneWidget);
      expect(find.textContaining('drawing=true'), findsOneWidget);
    });
  });
}