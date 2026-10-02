import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/connect/connect_screen.dart';
import '../features/diagnostics/diagnostics_screen.dart';
import '../features/drawing/drawing_screen.dart';
import '../features/flight/flight_screen.dart';
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
              context.go('/about');
              break;
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.link), label: 'Connect'),
          NavigationDestination(icon: Icon(Icons.list), label: 'Diagnostics'),
          NavigationDestination(icon: Icon(Icons.draw), label: 'Drawing'),
          NavigationDestination(icon: Icon(Icons.flight), label: 'Flight'),
          NavigationDestination(icon: Icon(Icons.info), label: 'About'),
        ],
      ),
    );
  }
}

final appRouter = GoRouter(
  initialLocation: '/connect',
  routes: [
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(path: '/connect', builder: (context, state) => const ConnectScreen()),
        GoRoute(path: '/diagnostics', builder: (context, state) => const DiagnosticsScreen()),
        GoRoute(path: '/drawing', builder: (context, state) => const DrawingScreen()),
        GoRoute(path: '/flight', builder: (context, state) => const FlightScreen()),
        GoRoute(path: '/about', builder: (context, state) => const AboutScreen()),
      ],
    ),
  ],
);
