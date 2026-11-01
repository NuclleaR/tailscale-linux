import 'dart:convert';
import 'dart:io';

/// The GitHub repository releases come from.
const releaseRepo = 'NuclleaR/tailscale-linux';

/// The release asset that `install.sh` and the in-app update both use.
const linuxArchiveName = 'tailscale-linux-x64.tar.gz';

/// The folder inside the archive, which is also the name of the folder
/// `install.sh` installs into.
const appFolderName = 'tailscale-linux';

/// The executable inside that folder.
const executableName = 'tailscale_linux';

/// The newest release, pre-releases included, as `install.sh` picks it.
final newestReleaseApi = Uri.parse(
  'https://api.github.com/repos/$releaseRepo/releases?per_page=1',
);

class UpdateException implements Exception {
  const UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

class Release {
  const Release({
    required this.version,
    required this.archiveUrl,
    required this.pageUrl,
  });

  /// Without the tag's leading `v`.
  final String version;
  final Uri archiveUrl;

  /// The release on GitHub, with its notes.
  final Uri pageUrl;
}

/// Semantic version order: `0.0.2-beta` < `0.0.2` < `0.0.10`.
int compareVersions(String a, String b) {
  (List<int>, List<String>?) parse(String v) {
    final dash = v.indexOf('-');
    final core = dash < 0 ? v : v.substring(0, dash);
    return (
      [for (final p in core.split('.')) int.tryParse(p) ?? 0],
      dash < 0 ? null : v.substring(dash + 1).split('.'),
    );
  }

  final (coreA, preA) = parse(a);
  final (coreB, preB) = parse(b);
  for (var i = 0; i < 3; i++) {
    final c = (i < coreA.length ? coreA[i] : 0).compareTo(
      i < coreB.length ? coreB[i] : 0,
    );
    if (c != 0) return c;
  }
  // A version without a pre-release suffix is the newer one.
  if (preA == null || preB == null) {
    return preA == preB ? 0 : (preA == null ? 1 : -1);
  }
  for (var i = 0; i < preA.length && i < preB.length; i++) {
    final x = int.tryParse(preA[i]), y = int.tryParse(preB[i]);
    final c = x != null && y != null
        ? x.compareTo(y)
        : x != null
        ? -1
        : y != null
        ? 1
        : preA[i].compareTo(preB[i]);
    if (c != 0) return c;
  }
  return preA.length.compareTo(preB.length);
}

/// The first release in a GitHub `releases` listing, or null if there is
/// none or it has no Linux archive.
Release? parseNewestRelease(String body) {
  final list = jsonDecode(body);
  if (list is! List || list.isEmpty) return null;
  final r = list.first as Map<String, Object?>;
  final tag = r['tag_name'] as String? ?? '';
  for (final a in r['assets'] as List<Object?>? ?? const []) {
    if (a case {
      'name': linuxArchiveName,
      'browser_download_url': final String url,
    }) {
      return Release(
        version: tag.startsWith('v') ? tag.substring(1) : tag,
        archiveUrl: Uri.parse(url),
        pageUrl: Uri.parse(r['html_url'] as String? ?? ''),
      );
    }
  }
  return null;
}

Future<Release?> fetchNewestRelease() async {
  final client = HttpClient()..userAgent = appFolderName;
  try {
    final request = await client.getUrl(newestReleaseApi);
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/vnd.github+json',
    );
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != HttpStatus.ok) {
      throw UpdateException('GitHub answered ${response.statusCode}');
    }
    return parseNewestRelease(body);
  } finally {
    client.close();
  }
}

/// Downloads the archive of [release] into [dir].
Future<File> downloadRelease(Release release, Directory dir) async {
  final client = HttpClient()..userAgent = appFolderName;
  try {
    final response = await (await client.getUrl(release.archiveUrl)).close();
    if (response.statusCode != HttpStatus.ok) {
      throw UpdateException('download failed: HTTP ${response.statusCode}');
    }
    final file = File('${dir.path}/$linuxArchiveName');
    await response.pipe(file.openWrite());
    return file;
  } finally {
    client.close();
  }
}

/// Unpacks a release [archive] and puts its `tailscale-linux/` in place of
/// [appDir]. Any failure leaves [appDir] as it was.
Future<void> installArchive(File archive, Directory appDir) async {
  // Next to the app, so the swap is two renames on one file system.
  final staging = await appDir.parent.createTemp('.$appFolderName-update-');
  try {
    final tar = await Process.run('tar', [
      '-xzf',
      archive.path,
      '-C',
      staging.path,
    ]);
    if (tar.exitCode != 0) {
      throw UpdateException(
        'cannot unpack the archive: ${'${tar.stderr}'.trim()}',
      );
    }
    final fresh = Directory('${staging.path}/$appFolderName');
    if (!File('${fresh.path}/$executableName').existsSync()) {
      throw const UpdateException(
        'the archive has no $appFolderName/$executableName',
      );
    }
    final old = '${staging.path}/old';
    await appDir.rename(old);
    try {
      await fresh.rename(appDir.path);
    } on FileSystemException catch (e) {
      await Directory(old).rename(appDir.path);
      throw UpdateException('cannot replace the app: $e');
    }
  } finally {
    await staging.delete(recursive: true);
  }
}

/// Where this copy of the app runs from, and its version.
class AppInstall {
  const AppInstall({
    required this.version,
    required this.dir,
    required this.installed,
  });

  /// The bundle at [dir]; [environment] decides where `install.sh` puts the
  /// app.
  factory AppInstall.at(Directory dir, [Map<String, String>? environment]) {
    var version = '';
    try {
      final info = jsonDecode(
        File('${dir.path}/data/flutter_assets/version.json').readAsStringSync(),
      );
      if (info case {'version': final String v}) version = v;
    } on FileSystemException {
      // A test run or an odd bundle: the version stays unknown.
    } on FormatException {
      // Likewise.
    }
    final env = environment ?? Platform.environment;
    final xdg = env['XDG_DATA_HOME'] ?? '';
    final data = xdg.isNotEmpty ? xdg : '${env['HOME']}/.local/share';
    return AppInstall(
      version: version,
      dir: dir,
      installed: dir.path == '$data/$appFolderName',
    );
  }

  factory AppInstall.current() =>
      AppInstall.at(File(Platform.resolvedExecutable).parent);

  /// Empty when unknown.
  final String version;
  final Directory dir;

  /// Put there by `install.sh`, so an update may replace [dir]. A build run
  /// from the source tree is never replaced.
  final bool installed;
}
