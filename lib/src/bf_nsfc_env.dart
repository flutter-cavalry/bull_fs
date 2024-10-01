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
      return _fromIcloudEntity(e, dirRelPath: dirRelPath?.lock);
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
      return BFPathAndDirRelPath(BFScopedPath(e.url), (dirRelPath ?? []).lock);
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
  Future<BFPath> renameInternal(BFPath path, String newName, bool isDir) async {
    final dirUrl = await _darwinUrlPlugin.dirUrl(path.scopedID());
    final destUrl =
        await _darwinUrlPlugin.append(dirUrl, [newName], isDir: isDir);
    await _plugin.move(path.scopedID(), destUrl);
    return BFScopedPath(destUrl);
  }

  @override
  Future<UpdatedBFPath> moveToDirSafe(
      BFPath src, BFPath srcDir, BFPath destDir, bool isDir,
      {BFNameUpdaterFunc? nameUpdater}) async {
    final srcName = await basenameOfPath(src);
    if (srcName == null) {
      throw Exception('Unexpected null basename from item stat');
    }
    final destItemFileName = await ZBFInternal.nextAvailableFileName(
        this,
        destDir,
        srcName,
        isDir,
        nameUpdater ?? ZBFInternal.defaultFileNameUpdater);
    final destItemPath =
        await destDir.iosJoinRelPath([destItemFileName].lock, isDir);
    await _plugin.move(src.scopedID(), destItemPath.scopedID());
    return UpdatedBFPath(destItemPath, destItemFileName);
  }

  @override
  Future<Stream<List<int>>> readFileStream(BFPath path,
      {int? bufferSize}) async {
    return _plugin.readFileStream(path.scopedID(), bufferSize: bufferSize);
  }

  @override
  Future<BFOutStream> writeFileStream(BFPath dir, String unsafeName,
      {BFNameUpdaterFunc? nameUpdater, bool? overwrite}) async {
    final safeName = overwrite == true
        ? unsafeName
        : await ZBFInternal.nextAvailableFileName(this, dir, unsafeName, false,
            nameUpdater ?? ZBFInternal.defaultFileNameUpdater);
    final destPathUrl =
        await _darwinUrlPlugin.append(dir.toString(), [safeName], isDir: false);
    final destPath = BFScopedPath(destPathUrl);

    final session = await _plugin.startWriteStream(destPathUrl);
    return BFNsfcOutStream(session, _plugin, destPath, safeName);
  }

  @override
  Future<UpdatedBFPath> writeFileSync(
      BFPath dir, String unsafeName, Uint8List bytes,
      {BFNameUpdaterFunc? nameUpdater, bool? overwrite}) async {
    final safeName = overwrite == true
        ? unsafeName
        : await ZBFInternal.nextAvailableFileName(this, dir, unsafeName, false,
            nameUpdater ?? ZBFInternal.defaultFileNameUpdater);
    final destPathUrl =
        await _darwinUrlPlugin.append(dir.toString(), [safeName], isDir: false);
    final destPath = BFScopedPath(destPathUrl);
    await _plugin.writeFile(destPathUrl, bytes);
    return UpdatedBFPath(destPath, safeName);
  }

  @override
  Future<UpdatedBFPath> pasteLocalFile(
      String localSrc, BFPath dir, String unsafeName,
      {BFNameUpdaterFunc? nameUpdater, bool? overwrite}) async {
    final safeName = overwrite == true
        ? unsafeName
        : await ZBFInternal.nextAvailableFileName(this, dir, unsafeName, false,
            nameUpdater ?? ZBFInternal.defaultFileNameUpdater);
    final destPath = await dir.iosJoinRelPath([safeName].lock, false);
    final srcUrl = await _darwinUrlPlugin.filePathToUrl(localSrc);
    await _plugin.copyPath(srcUrl, destPath.scopedID(), overwrite: overwrite);
    return UpdatedBFPath(destPath, safeName);
  }

  @override
  Future<void> copyToLocalFile(BFPath src, String dest) async {
    final destUrl = await _darwinUrlPlugin.filePathToUrl(dest);
    await _plugin.copyPath(src.scopedID(), destUrl);
  }

  @override
  Future<Uint8List> readFileSync(BFPath path, {int? start, int? count}) async {
    return _plugin.readFileSync(path.scopedID(), start: start, count: count);
  }

  @override
  Future<BFPath?> appendPath(
      BFPath path, IList<String> components, bool isDir) async {
    final newPath = await _darwinUrlPlugin
        .append(path.toString(), components.unlock, isDir: isDir);
    return BFScopedPath(newPath);
  }

  @override
  Future<String?> basenameOfPath(BFPath path) async {
    return _darwinUrlPlugin.basename(path.toString());
  }

  Future<BFEntity> _fromIcloudEntity(NsFileCoordinatorEntity entity,
      {required IList<String>? dirRelPath}) async {
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

  bool _closed = false;

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
    if (_closed) {
      return;
    }
    await _plugin.endWriteStream(_session);
    _closed = true;
  }

  @override
  Future<void> flush() async {}
}
