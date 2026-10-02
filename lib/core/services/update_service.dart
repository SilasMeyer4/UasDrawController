import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateInfo {
  final String version; // tag like v0.0.1
  final String name;
  final String htmlUrl;
  final List<ReleaseAsset> assets;

  UpdateInfo({
    required this.version,
    required this.name,
    required this.htmlUrl,
    required this.assets,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    final tag = (json['tag_name'] as String?) ?? '';
    final assets = (json['assets'] as List<dynamic>?)
            ?.map((e) => ReleaseAsset.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return UpdateInfo(
      version: tag,
      name: (json['name'] as String?) ?? tag,
      htmlUrl: (json['html_url'] as String?) ?? '',
      assets: assets,
    );
  }
}

class ReleaseAsset {
  final String name;
  final String downloadUrl;
  final int size;

  ReleaseAsset({required this.name, required this.downloadUrl, required this.size});

  factory ReleaseAsset.fromJson(Map<String, dynamic> json) {
    return ReleaseAsset(
      name: (json['name'] as String?) ?? '',
      downloadUrl: (json['browser_download_url'] as String?) ?? '',
      size: (json['size'] as int?) ?? 0,
    );
  }
}

class UpdateService {
  static const _repo = 'SilasMeyer4/UasDrawController';
  static const _apiUrl = 'https://api.github.com/repos/$_repo/releases/latest';

  Future<UpdateInfo?> checkForUpdate({bool silent = true}) async {
    try {
      final res = await http.get(Uri.parse(_apiUrl));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      return UpdateInfo.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<String> getCurrentVersion() async {
    final pkg = await PackageInfo.fromPlatform();
    return 'v${pkg.version}';
  }

  bool isNewer(String current, String latest) {
    String c = current.startsWith('v') ? current.substring(1) : current;
    String l = latest.startsWith('v') ? latest.substring(1) : latest;
    final cp = c.split('.').map(int.tryParse).toList();
    final lp = l.split('.').map(int.tryParse).toList();
    int clen = cp.length;
    int llen = lp.length;
    int maxLen = clen > llen ? clen : llen;
    for (int i = 0; i < maxLen; i++) {
      int cv = i < clen && cp[i] != null ? cp[i]! : 0;
      int lv = i < llen && lp[i] != null ? lp[i]! : 0;
      if (lv > cv) return true;
      if (lv < cv) return false;
    }
    return false;
  }

  Future<void> openReleasePage(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<String?> downloadAndroidApk(UpdateInfo info) async {
    if (!Platform.isAndroid) return null;
    // Try to pick best arch heuristically; split apks are built
    ReleaseAsset? best;
    for (final a in info.assets) {
      final n = a.name.toLowerCase();
      if (n.contains('arm64-v8a') && n.endsWith('.apk')) {
        best = a;
        break;
      }
      if (n.contains('armeabi-v7a') && n.endsWith('.apk')) {
        best ??= a;
      }
      if (n.contains('x86_64') && n.endsWith('.apk')) {
        best ??= a;
      }
      if (n.endsWith('.apk') && best == null) best = a;
    }
    if (best == null) return null;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${best.name}');
    final res = await http.get(Uri.parse(best.downloadUrl));
    if (res.statusCode != 200) return null;
    await file.writeAsBytes(res.bodyBytes);
    return file.path;
  }

  Future<void> installAndroidApk(String path) async {
    if (!Platform.isAndroid) return;
    await OpenFilex.open(path);
  }

  Future<String?> downloadLinuxTar(UpdateInfo info) async {
    if (!Platform.isLinux) return null;
    ReleaseAsset? best;
    for (final a in info.assets) {
      if (a.name.contains('linux') && a.name.endsWith('.tar.gz')) {
        best = a;
        break;
      }
    }
    if (best == null) return null;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${best.name}');
    final res = await http.get(Uri.parse(best.downloadUrl));
    if (res.statusCode != 200) return null;
    await file.writeAsBytes(res.bodyBytes);
    return file.path;
  }
}
