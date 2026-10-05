import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/bindings.dart';
import '../../core/models/connection_profile.dart';
import '../../core/services/connection_manager.dart';
import '../../core/services/profile_store.dart';

/// Pick a connection profile, edit it, and connect to rosbridge.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  List<ConnectionProfile> _profiles = <ConnectionProfile>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profiles = await context.read<ProfileStore>().loadProfiles();
    if (!mounted) return;
    setState(() => _profiles = profiles);
  }

  /// Inserts or replaces [profile]. `ConnectionProfile` compares by value, so
  /// an edited profile replaces the matching one instead of duplicating it.
  Future<void> _save(ConnectionProfile profile) async {
    final profiles = [..._profiles];
    final index = profiles.indexOf(profile);
    if (index >= 0) {
      profiles[index] = profile;
    } else {
      profiles.add(profile);
    }
    await context.read<ProfileStore>().saveProfiles(profiles);
    if (!mounted) return;
    setState(() => _profiles = profiles);
  }

  Future<void> _remove(ConnectionProfile profile) async {
    if (_profiles.length <= 1) return;
    final profiles = _profiles.where((p) => p != profile).toList();
    await context.read<ProfileStore>().saveProfiles(profiles);
    if (!mounted) return;
    setState(() => _profiles = profiles);
  }

  @override
  Widget build(BuildContext context) {
    final cm = context.watch<ConnectionManager>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect'),
        actions: [
          IconButton(
            tooltip: 'Add profile',
            icon: const Icon(Icons.add),
            onPressed: () => _edit(null),
          ),
          if (cm.isConnected)
            IconButton(
              tooltip: 'Disconnect',
              icon: const Icon(Icons.link_off),
              onPressed: cm.disconnect,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final profile in _profiles)
            Card(
              child: ListTile(
                title: Text(profile.name),
                subtitle: Text(
                  '${profile.isMock ? 'simulation' : profile.wsUrl}\n'
                  'bindings: ${Bindings.presetName(profile.bindings)}',
                ),
                isThreeLine: true,
                trailing: cm.isConnecting && cm.profile == profile
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(),
                      )
                    : cm.isConnected && cm.profile == profile
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : null,
                onTap: cm.isConnecting
                    ? null
                    : () => cm.connect(profile),
                onLongPress: () => _edit(profile),
                leading: PopupMenuButton<String>(
                  tooltip: 'Profile actions',
                  icon: const Icon(Icons.more_vert),
                  onSelected: (action) => switch (action) {
                    'edit' => _edit(profile),
                    'remove' => _confirmRemove(profile),
                    _ => null,
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'remove', child: Text('Remove')),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            'Tap a profile to connect. Use the pencil to change the rosbridge '
            'URL or the ROS names it sends to.',
            style: TextStyle(fontSize: 12),
          ),
          if (cm.error != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: const Text('Connection failed'),
                subtitle: Text(cm.error!),
              ),
            ),
          ],
          if (cm.notice != null) ...[
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(cm.notice!),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _edit(ConnectionProfile? existing) async {
    final result = await showModalBottomSheet<ConnectionProfile>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProfileEditor(initial: existing),
    );
    if (result == null) return;
    await _save(result);
  }

  /// Asks before dropping a profile. Kept separate from [_edit] so that saving
  /// an edited profile never looks like a removal.
  Future<void> _confirmRemove(ConnectionProfile existing) async {
    if (_profiles.length <= 1) return;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove "${existing.name}"?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _remove(existing);
  }
}

class _ProfileEditor extends StatefulWidget {
  const _ProfileEditor({this.initial});

  final ConnectionProfile? initial;

  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initial?.name ?? 'New profile');
  late final TextEditingController _url = TextEditingController(
    text: widget.initial?.wsUrl ?? 'ws://localhost:9090',
  );
  late bool _isMock = widget.initial?.isMock ?? false;
  late Bindings _bindings = widget.initial?.bindings ?? Bindings.uasDraw();

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preset = Bindings.presetName(_bindings);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.initial == null ? 'New profile' : 'Edit profile',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _url,
              enabled: !_isMock,
              decoration: const InputDecoration(
                labelText: 'rosbridge WebSocket URL',
                hintText: 'ws://localhost:9090',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Simulation (no ROS needed)'),
              value: _isMock,
              onChanged: (v) => setState(() => _isMock = v),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: Bindings.presets.containsKey(preset)
                  ? preset
                  : 'uasDraw',
              decoration: const InputDecoration(labelText: 'Binding preset'),
              items: [
                for (final entry in Bindings.presets.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.key)),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _bindings = Bindings.presets[value]!);
              },
            ),
            const SizedBox(height: 8),
            Text(
              'ROS names in use ($preset)',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            for (final action in LogicalAction.values)
              _bindingRow(action),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(
                    ConnectionProfile(
                      name: _name.text.trim().isEmpty
                          ? 'Unnamed'
                          : _name.text.trim(),
                      wsUrl: _url.text.trim(),
                      isMock: _isMock,
                      bindings: _bindings,
                    ),
                  ),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _bindingRow(LogicalAction action) {
    final binding = _bindings.get(action);
    if (binding == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(action.name, style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            child: Text(
              '${binding.isService ? 'srv' : 'top'} ${binding.name}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          IconButton(
            tooltip: 'Edit ${action.name}',
            icon: const Icon(Icons.tune, size: 18),
            onPressed: () => _editBinding(action, binding),
          ),
        ],
      ),
    );
  }

  Future<void> _editBinding(LogicalAction action, Binding binding) async {
    final nameController = TextEditingController(text: binding.name);
    final typeController = TextEditingController(text: binding.type);
    final result = await showDialog<Binding>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(action.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'ROS name'),
            ),
            TextField(
              controller: typeController,
              decoration: const InputDecoration(labelText: 'ROS type'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(
              binding.copyWith(
                name: nameController.text.trim(),
                type: typeController.text.trim(),
              ),
            ),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    nameController.dispose();
    typeController.dispose();
    if (result != null) setState(() => _bindings = _bindings.withOverride(action, result));
  }
}