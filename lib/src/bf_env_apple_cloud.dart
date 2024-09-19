import 'package:darwin_url/darwin_url.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'bf_env.dart';
import 'zbf_internal.dart';
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
  Future<List<BFEntity>> listDir(BFPath path,
      {bool? recursive, bool? relativePathInfo}) async {
    final icloudEntities = await _icloudPlugin.listContents(path.scopedID(),
        recursive: recursive,
        filesOnly: false,
        relativePathInfo: relativePathInfo);
    final futures = icloudEntities.map((e) {
      List<String>? dirRelPath;
      if (e.relativePath != null) {
        final relPath = e.relativePath!.split('/');
        if (relPath.length == 1) {
          dirRelPath = [];
        } else if (relPath.length > 1) {
          dirRelPath = relPath.sublist(0, relPath.length - 1);
        }
      }
      return _fromIcloudEntity(e, dirRelPath: dirRelPath);
    }).toList();
    return await Future.wait(futures);
  }

  @override
  Future<List<BFPathAndDirRelPath>> listDirContentFiles(BFPath path) async {
    final icloudEntities =
        await _icloudPlugin.listContentFiles(path.scopedID());
    final paths = icloudEntities.map((e) {
      List<String>? dirRelPath;
      if (e.relativePath != null) {
        final relPath = e.relativePath!.split('/');
        if (relPath.length == 1) {
          dirRelPath = [];
        } else if (relPath.length > 1) {
          dirRelPath = relPath.sublist(0, relPath.length - 1);
        }
      }
      return BFPathAndDirRelPath(BFScopedPath(e.url), dirRelPath ?? []);
    }).toList();
    return paths;
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
      return _fromIcloudEntity(e, dirRelPath: null);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<UpdatedBFPath> ensureDir(BFPath dir, String unsafeName) async {
    final destPath = await dir.iosJoinRelPath([unsafeName].lock, true);
    await _icloudPlugin.mkdir(destPath.scopedID());
    return UpdatedBFPath(destPath, unsafeName);
  }

  @override
  Future<UpdatedBFPath> ensureDirs(BFPath dir, IList<String> path) async {
    final destPath = await dir.iosJoinRelPath(path, true);
    await _icloudPlugin.mkdir(destPath.scopedID());
    String lastComponentName;
    if (path.isEmpty) {
      final destDirStat = await stat(destPath);
      if (destDirStat == null) {
        throw Exception('Failed to create dir: $destPath');
      }
      lastComponentName = destDirStat.name;
    } else {
      lastComponentName = path.last;
    }
    return UpdatedBFPath(destPath, lastComponentName);
  }

  @override
  Future<UpdatedBFPath> renameInternal(BFPath root, IList<String> src,
      String unsafeNewName, bool isDir, BFEntity srcStat) async {
    final path = srcStat.path;
    final dirUrl = await _darwinUrlPlugin.dirUrl(path.scopedID());
    final destUrl =
        await _darwinUrlPlugin.append(dirUrl, [unsafeNewName], isDir: isDir);
    await _icloudPlugin.move(path.scopedID(), destUrl);
    return UpdatedBFPath(BFScopedPath(destUrl), unsafeNewName);
  }

  @override
  Future<UpdatedBFPath> moveToDir(
      BFPath root, IList<String> src, IList<String> destDir, bool isDir,
      {BFNameUpdaterFunc? nameUpdater}) async {
    final srcStat = await ZBFInternal.mustGetStat(this, root, src);
    final destDirStat = await ZBFInternal.mustGetStat(this, root, destDir);

    final destItemFileName = await ZBFInternal.nextAvailableFileName(
        this,
        destDirStat.path,
        srcStat.name,
        isDir,
        nameUpdater ?? ZBFInternal.defaultFileNameUpdater);
    final destItemPath =
        await destDirStat.path.iosJoinRelPath([destItemFileName].lock, isDir);
    await _icloudPlugin.move(srcStat.path.scopedID(), destItemPath.scopedID());
    return UpdatedBFPath(destItemPath, destItemFileName);
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
  Future<BFOutStream> writeFileStream(BFPath dir, String unsafeName,
      {BFNameUpdaterFunc? nameUpdater}) async {
    throw Exception('Not supported');
  }

  @override
  Future<UpdatedBFPath> pasteLocalFile(
      String localSrc, BFPath dir, String unsafeName,
      {BFNameUpdaterFunc? nameUpdater}) async {
    final safeName = await ZBFInternal.nextAvailableFileName(this, dir,
        unsafeName, false, nameUpdater ?? ZBFInternal.defaultFileNameUpdater);
    final destPath = await dir.iosJoinRelPath([safeName].lock, false);
    final srcUrl = await _darwinUrlPlugin.filePathToUrl(localSrc);
    await _icloudPlugin.copyPath(srcUrl, destPath.scopedID());
    return UpdatedBFPath(destPath, safeName);
  }

  @override
  Future<void> copyToLocalFile(BFPath src, String dest) async {
    final destUrl = await _darwinUrlPlugin.filePathToUrl(dest);
    await _icloudPlugin.copyPath(src.scopedID(), destUrl);
  }

  Future<BFEntity> _fromIcloudEntity(NsFileCoordinatorEntity entity,
      {required List<String>? dirRelPath}) async {
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
        entity.length, entity.lastMod, isOnCloud,
        dirRelPath: dirRelPath);
  }
}
