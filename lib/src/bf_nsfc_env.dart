import 'dart:typed_data';

import 'package:darwin_url/darwin_url.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'bf_env.dart';
import 'zbf_internal.dart';
import 'types.dart';
import 'package:ns_file_coordinator_util/ns_file_coordinator_util_platform_interface.dart';
import 'package:ns_file_coordinator_util/ns_file_coordinator_util.dart';

final _darwinUrlPlugin = DarwinUrl();

/// [BFEnv] for NSFileCoordinator.
class BFNsfcEnv extends BFEnv {
  final _plugin = NsFileCoordinatorUtil();

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
    final icloudEntities = await _plugin.listContents(path.scopedID(),
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
    final icloudEntities = await _plugin.listContentFiles(path.scopedID());
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
    await _plugin.delete(path.scopedID());
  }

  @override
  Future<BFEntity?> stat(BFPath path, {IList<String>? relPath}) async {
    if (relPath != null) {
      // Use file URI for unknown paths.
      path = await path.iosJoinRelPath(relPath, false);
    }
    try {
      final e = await _plugin.stat(path.scopedID());
      if (e == null) {
        return null;
      }
      return _fromIcloudEntity(e, dirRelPath: null);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<BFPath> mkdirp(BFPath dir, IList<String> components) async {
    final destPath = await _plugin.mkdirp(dir.scopedID(), components.unlock);
    return BFScopedPath(destPath);
  }

  @override
  Future<UpdatedBFPath> renameInternal(BFPath root, IList<String> src,
      String unsafeNewName, bool isDir, BFEntity srcStat) async {
    final path = srcStat.path;
    final dirUrl = await _darwinUrlPlugin.dirUrl(path.scopedID());
    final destUrl =
        await _darwinUrlPlugin.append(dirUrl, [unsafeNewName], isDir: isDir);
    await _plugin.move(path.scopedID(), destUrl);
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
    await _plugin.move(srcStat.path.scopedID(), destItemPath.scopedID());
    return UpdatedBFPath(destItemPath, destItemFileName);
  }

  @override
  bool hasStreamSupport() {
    return true;
  }

  @override
  Future<Stream<List<int>>> readFileStream(BFPath path) async {
    return _plugin.readFileStream(path.scopedID());
  }

  @override
  Future<BFOutStream> writeFileStream(BFPath dir, String unsafeName,
      {BFNameUpdaterFunc? nameUpdater}) async {
    final safeName = await ZBFInternal.nextAvailableFileName(this, dir,
        unsafeName, false, nameUpdater ?? ZBFInternal.defaultFileNameUpdater);
    final destPathUrl = await _darwinUrlPlugin
        .append(dir.toString(), [unsafeName], isDir: false);
    final destPath = BFScopedPath(destPathUrl);

    final session = await _plugin.startWriteStream(destPathUrl);
    return BFNsfcOutStream(session, _plugin, destPath, safeName);
  }

  @override
  Future<UpdatedBFPath> pasteLocalFile(
      String localSrc, BFPath dir, String unsafeName,
      {BFNameUpdaterFunc? nameUpdater}) async {
    final safeName = await ZBFInternal.nextAvailableFileName(this, dir,
        unsafeName, false, nameUpdater ?? ZBFInternal.defaultFileNameUpdater);
    final destPath = await dir.iosJoinRelPath([safeName].lock, false);
    final srcUrl = await _darwinUrlPlugin.filePathToUrl(localSrc);
    await _plugin.copyPath(srcUrl, destPath.scopedID());
    return UpdatedBFPath(destPath, safeName);
  }

  @override
  Future<void> copyToLocalFile(BFPath src, String dest) async {
    final destUrl = await _darwinUrlPlugin.filePathToUrl(dest);
    await _plugin.copyPath(src.scopedID(), destUrl);
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

class BFNsfcOutStream extends BFOutStream {
  final int _session;
  final NsFileCoordinatorUtil _plugin;
  final BFPath _path;
  final String _fileName;

  BFNsfcOutStream(this._session, this._plugin, this._path, this._fileName);

  @override
  BFPath getPath() {
    return _path;
  }

  @override
  String getFileName() {
    return _fileName;
  }

  @override
  Future<void> write(Uint8List data) async {
    await _plugin.writeChunk(_session, data);
  }

  @override
  Future<void> close() async {
    await _plugin.endWriteStream(_session);
  }

  @override
  Future<void> flush() async {}
}
