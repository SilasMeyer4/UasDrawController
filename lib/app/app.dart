import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/connect/connect_screen.dart';
import '../features/diagnostics/diagnostics_screen.dart';
import '../features/drawing/drawing_screen.dart';
import '../features/flight/flight_screen.dart';
import '../features/logs/log_screen.dart';
import '../features/about/about_screen.dart';

class AppShell extends StatefulWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) {
          setState(() => _currentIndex = i);
          switch (i) {
            case 0:
              context.go('/connect');
              break;
            case 1:
              context.go('/diagnostics');
              break;
            case 2:
              context.go('/drawing');
              break;
            case 3:
              context.go('/flight');
              break;
            case 4:
              context.go('/logs');
              break;
            case 5:
              context.go('/about');
              break;
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.link), label: 'Connect'),
          NavigationDestination(icon: Icon(Icons.list), label: 'Diagnostics'),
          NavigationDestination(icon: Icon(Icons.draw), label: 'Drawing'),
          NavigationDestination(icon: Icon(Icons.flight), label: 'Flight'),
          NavigationDestination(icon: Icon(Icons.article_outlined), label: 'Logs'),
          NavigationDestination(icon: Icon(Icons.info), label: 'About'),
        ],
      ),
    );
  }
}

/// Router factory. GoRouter holds navigation state and can only be attached
/// to one widget tree, so build a fresh router per app instance (and in tests).
GoRouter createAppRouter({String initialLocation = '/connect'}) => GoRouter(
      initialLocation: initialLocation,
      routes: [
        ShellRoute(
          builder: (context, state, child) => AppShell(child: child),
          routes: [
            GoRoute(path: '/connect', builder: (context, state) => const ConnectScreen()),
            GoRoute(path: '/diagnostics', builder: (context, state) => const DiagnosticsScreen()),
            GoRoute(path: '/drawing', builder: (context, state) => const DrawingScreen()),
            GoRoute(path: '/flight', builder: (context, state) => const FlightScreen()),
            GoRoute(path: '/logs', builder: (context, state) => const LogScreen()),
            GoRoute(path: '/about', builder: (context, state) => const AboutScreen()),
          ],
        ),
      ],
    );
