import 'package:darwin_url/darwin_url.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'bf_env.dart';
import 'extensions.dart';
import 'internal.dart';
import 'types.dart';
import 'package:ns_file_coordinator_util/ns_file_coordinator_util_platform_interface.dart';
import 'package:ns_file_coordinator_util/ns_file_coordinator_util.dart';

final _darwinUrlPlugin = DarwinUrl();

class BFEnvAppleCloud extends BFEnv {
  final _icloudPlugin = NsFileCoordinatorUtil();

  @override
  BFEnvType envType() {
    return BFEnvType.icloud;
  }

  @override
  bool isScoped() {
    return true;
  }

  @override
  Future<List<BFEntity>> listDir(BFPath path, {bool? recursive}) async {
    final icloudEntities = await _icloudPlugin.listContents(path.scopedID(),
        recursive: recursive, filesOnly: false);
    final futures = icloudEntities.map((e) => _fromIcloudEntity(e)).toList();
    return await Future.wait(futures);
  }

  @override
  Future<void> delete(BFPath path, bool isDir) async {
    await _icloudPlugin.delete(path.scopedID());
  }

  @override
  Future<BFEntity?> stat(BFPath path, {IList<String>? relPath}) async {
    if (relPath != null) {
      // Use file URI for unknown paths.
      path = await path.iosJoinRelPath(relPath, false);
    }
    try {
      final e = await _icloudPlugin.stat(path.scopedID());
      if (e == null) {
        return null;
      }
      return _fromIcloudEntity(e);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<BFPath> mkdir(BFPath dir, String name) async {
    final newDirUri = await dir.iosJoinRelPath([name].lock, true);
    await _icloudPlugin.mkdir(newDirUri.scopedID());
    return newDirUri;
  }

  @override
  Future<BFPath> mkdirp(BFPath dir, IList<String> path) async {
    final finalPath = await dir.iosJoinRelPath(path, true);
    await _icloudPlugin.mkdir(finalPath.scopedID());
    return finalPath;
  }

  @override
  Future<BFPath> rename(BFPath path, String newName, bool isDir) async {
    final dirUrl = await _darwinUrlPlugin.dirUrl(path.scopedID());
    final destUrl =
        await _darwinUrlPlugin.append(dirUrl, [newName], isDir: isDir);
    await _icloudPlugin.move(path.scopedID(), destUrl);
    return BFScopedPath(destUrl);
  }

  @override
  Future<BFPath> move(
      BFPath root, IList<String> src, IList<String> dest, bool isDir) async {
    final srcPath = (await stat(root, relPath: src))?.path;
    if (srcPath == null) {
      throw Exception('$src is not found');
    }
    // Create dest dir.
    final destDir = await mkdirpForFile(root, dest);
    final destPath = await destDir.iosJoinRelPath([dest.last].lock, isDir);
    await _icloudPlugin.move(srcPath.scopedID(), destPath.scopedID());
    return destPath;
  }

  @override
  bool hasStreamSupport() {
    return false;
  }

  @override
  Future<Stream<List<int>>> readFileStream(BFPath path) async {
    throw Exception('Not supported');
  }

  @override
  Future<BFOutStream> writeFileStream(BFPath dir, String unsafeName) async {
    throw Exception('Not supported');
  }

  @override
  Future<BFPath> pasteLocalFile(
      String localSrc, BFPath dir, String unsafeName) async {
    final safeName =
        await zBFNonSAFNextAvailableFileName(this, dir, unsafeName, false);
    final destPath = await dir.iosJoinRelPath([safeName].lock, false);
    final srcUrl = await _darwinUrlPlugin.filePathToUrl(localSrc);
    await _icloudPlugin.copy(srcUrl, destPath.scopedID());
    return destPath;
  }

  @override
  Future<void> copyToLocalFile(BFPath src, String dest) async {
    final destUrl = await _darwinUrlPlugin.filePathToUrl(dest);
    await _icloudPlugin.readFile(src.scopedID(), destUrl);
  }

  Future<BFEntity> _fromIcloudEntity(NsFileCoordinatorEntity entity) async {
    const icloudExt = '.icloud';
    final eName = entity.name;
    final eUrl = entity.url;
    final isOnCloud = eName.startsWith('.') && eName.endsWith(icloudExt);
    // .ab.icloud
    // 0123456789
    //  []
    final realName =
        isOnCloud ? eName.substring(1, eName.length - icloudExt.length) : eName;
    final eDirUrl = await _darwinUrlPlugin.dirUrl(eUrl);
    final eRealUrl = isOnCloud
        ? await _darwinUrlPlugin.append(eDirUrl, [realName],
            isDir: entity.isDir)
        : eUrl;
    return BFEntity(BFScopedPath(eRealUrl), realName, entity.isDir,
        entity.length, entity.lastMod, isOnCloud);
  }
}
