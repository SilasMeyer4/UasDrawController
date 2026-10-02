import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/services/connection_manager.dart';
import 'core/services/profile_store.dart';
import 'core/models/bindings.dart';
import 'app/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const UasDrawApp());
}

class UasDrawApp extends StatelessWidget {
  const UasDrawApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConnectionManager()),
        Provider(create: (_) => ProfileStore()),
        Provider(create: (_) => Bindings.defaults()),
      ],
      child: MaterialApp.router(
        title: 'UasDraw Controller',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        routerConfig: appRouter,
      ),
    );
  }
}
