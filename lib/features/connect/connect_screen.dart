import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/connection_manager.dart';
import '../../core/services/profile_store.dart';
import '../../core/models/connection_profile.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  List<ConnectionProfile> _profiles = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = context.read<ProfileStore>();
    final ps = await store.loadProfiles();
    if (mounted) setState(() => _profiles = ps);
  }

  @override
  Widget build(BuildContext context) {
    final cm = context.watch<ConnectionManager>();
    return Scaffold(
      appBar: AppBar(title: const Text('Connect')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
        ],
      ),
    );
  }
}
