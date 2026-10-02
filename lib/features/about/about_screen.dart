import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/update_service.dart';
import '../../core/services/connection_manager.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  final _updateService = UpdateService();
  String _currentVersion = '';
  UpdateInfo? _latestUpdate;
  bool _checking = false;
  String? _error;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await _updateService.getCurrentVersion();
    if (mounted) setState(() => _currentVersion = v);
    unawaited(_check(silent: true));
  }

  Future<void> _check({bool silent = false}) async {
    if (_checking) return;
    setState(() {
      _checking = true;
      if (!silent) _error = null;
    });
    final u = await _updateService.checkForUpdate(silent: silent);
    if (mounted) {
      setState(() {
        _latestUpdate = u;
        _checking = false;
        if (!silent && u == null) _error = 'No update information found';
      });
    }
    if (!silent && u != null) {
      await _showUpdateDialog(u);
    }
  }

  Future<void> _showUpdateDialog(UpdateInfo u) async {
    final hasNewer = _updateService.isNewer(_currentVersion, u.version);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(hasNewer ? 'Update Available' : 'Up to Date'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Current: $_currentVersion'),
              Text('Latest: ${u.version}'),
              const SizedBox(height: 8),
              if (u.name.isNotEmpty) Text(u.name),
              const SizedBox(height: 12),
              if (hasNewer)
                const Text('A new release is available.'),
              if (!hasNewer) const Text('You are running the latest version.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            if (hasNewer)
              TextButton(
                onPressed: () async {
                  await _updateService.openReleasePage(u.htmlUrl);
                },
                child: const Text('Open Releases'),
              ),
            if (hasNewer)
              FilledButton(
                onPressed: _downloading
                    ? null
                    : () async {
                        setState(() => _downloading = true);
                        String? path;
                        if (!mounted) return;
                        final messenger = ScaffoldMessenger.of(context);
                        final platform = Theme.of(context).platform;
                        if (platform == TargetPlatform.android) {
                          path = await _updateService.downloadAndroidApk(u);
                        } else if (platform == TargetPlatform.linux) {
                          path = await _updateService.downloadLinuxTar(u);
                        }
                        if (!mounted) return;
                        if (path != null) {
                          if (platform == TargetPlatform.android) {
                            await _updateService.installAndroidApk(path);
                          } else {
                            messenger.showSnackBar(
                              SnackBar(content: Text('Downloaded: $path')),
                            );
                          }
                        } else {
                          messenger.showSnackBar(
                            const SnackBar(content: Text('Download failed')),
                          );
                        }
                        if (!mounted) return;
                        setState(() => _downloading = false);
                      },
                child: _downloading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Download & Install'),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cm = context.watch<ConnectionManager>();
    final hasNewer = _latestUpdate != null &&
        _updateService.isNewer(_currentVersion, _latestUpdate!.version);
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const ListTile(
            title: Text('UasDrawController'),
            subtitle: Text('AI-generated controller for UasDraw (in development)'),
          ),
          ListTile(
            title: const Text('Version'),
            subtitle: Text(_currentVersion.isEmpty ? '...' : _currentVersion),
          ),
          ListTile(
            title: const Text('Connection'),
            subtitle: Text(cm.isConnected ? 'Connected' : 'Not connected'),
          ),
          const Divider(),
          ListTile(
            title: const Text('Check for Updates'),
            subtitle: Text(hasNewer
                ? 'Update available (${_latestUpdate!.version})'
                : 'Tap to check for updates'),
            trailing: _checking
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator())
                : hasNewer
                    ? const Icon(Icons.download, color: Colors.orange)
                    : const Icon(Icons.update),
            onTap: () => _check(silent: false),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 16),
          const Text(
            'Releases are published on GitHub. On Android, download the APK and install it. On Linux, extract the tarball from the release.',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

void unawaited(Future<void> future) {}
