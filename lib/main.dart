import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/services/connection_manager.dart';
import 'core/services/profile_store.dart';
import 'core/models/connection_profile.dart';
import 'core/models/bindings.dart';

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
      child: MaterialApp(
        title: 'UasDraw Controller',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<ConnectionProfile> _profiles = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = context.read<ProfileStore>();
    final ps = await store.loadProfiles();
    setState(() => _profiles = ps);
  }

  @override
  Widget build(BuildContext context) {
    final cm = context.watch<ConnectionManager>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('UasDraw Controller'),
        actions: [
          if (cm.isConnected)
            IconButton(
              icon: const Icon(Icons.link_off),
              onPressed: () => cm.disconnect(),
            )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Profiles', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ..._profiles.map((p) => Card(
                child: ListTile(
                  title: Text(p.name),
                  subtitle: Text(p.wsUrl),
                  trailing: cm.isConnecting && cm.profile == p
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator())
                      : cm.isConnected && cm.profile == p
                          ? const Icon(Icons.link, color: Colors.green)
                          : null,
                  onTap: cm.isConnecting ? null : () => cm.connect(p),
                ),
              )),
          if (cm.error != null) ...[
            const SizedBox(height: 16),
            Text(cm.error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 24),
          const Text('ROS Graph', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (cm.isConnected) ...[
            _kv('Nodes', cm.graph.nodes.length.toString()),
            _kv('Topics', cm.graph.topics.length.toString()),
            _kv('Services', cm.graph.services.length.toString()),
          ] else
            const Text('Not connected'),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [Text('$k: '), Text(v, style: const TextStyle(fontWeight: FontWeight.bold))],
      ),
    );
  }
}
