import 'dart:typed_data';

import 'package:darwin_url/darwin_url.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:ns_file_coordinator_util/ns_file_coordinator_util.dart';
import 'package:ns_file_coordinator_util/ns_file_coordinator_util_platform_interface.dart';

import 'bf_env.dart';
import 'types.dart';
import 'zbf_internal.dart';

final _darwinUrlPlugin = DarwinUrl();

/// A [BFEnv] implementation for Apple system [NSFileCoordinator], which is used
/// for access iOS directories or iCloud directories.
class BFNsfcEnv extends BFEnv {
  static final BFNsfcEnv instance = BFNsfcEnv();

  final _plugin = NsFileCoordinatorUtil();

  @override
  BFEnvType envType() {
    return BFEnvType.nsfc;
  }

  @override
  bool isScoped() {
    return true;
  }

  @override
  Future<List<BFEntity>> listDir(
    BFPath path, {
    bool? recursive,
    bool? relativePathInfo,
  }) async {
    final icloudEntities = await _plugin.listContents(
      path.scopedUri(),
      recursive: recursive,
      filesOnly: false,
      relativePathInfo: relativePathInfo,
    );
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
    final icloudEntities = await _plugin.listContentFiles(path.scopedUri());
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
    await _plugin.delete(path.scopedUri());
  }

  @override
  Future<BFEntity?> stat(BFPath path, bool? isDir) async {
    final e = await _plugin.stat(path.scopedUri());
    if (e == null) {
      return null;
    }
    return _fromIcloudEntity(e, dirRelPath: null);
  }

  @override
  Future<BFEntity?> child(BFPath path, IList<String> names) async {
    path = await path.iosJoinRelPath(names, false);
    final e = await _plugin.stat(path.scopedUri());
    if (e == null) {
      return null;
    }
    return _fromIcloudEntity(e, dirRelPath: names);
  }

  @override
  Future<BFPath> mkdirp(BFPath dir, IList<String> components) async {
    final destPath = await _plugin.mkdirp(dir.scopedUri(), components.unlock);
    return BFScopedPath(destPath);
  }

  @override
  Future<BFPath> renameInternal(BFPath path, bool isDir, String newName) async {
    final dirUrl = await _darwinUrlPlugin.dirUrl(path.scopedUri());
    final destUrl = await _darwinUrlPlugin.append(dirUrl, [
      newName,
    ], isDir: isDir);
    await _plugin.move(path.scopedUri(), destUrl);
    return BFScopedPath(destUrl);
  }

  @override
  Future<UpdatedBFPath> moveToDirSafe(
    BFPath src,
    bool isDir,
    BFPath srcDir,
    BFPath destDir, {
    BFNameUpdater? nameUpdater,
  }) async {
    final srcName = await findBasename(src, isDir);
    if (srcName == null) {
      throw Exception('Unexpected null basename from item stat');
    }
    final destItemFileName = await ZBFInternal.nextAvailableFileName(
      this,
      destDir,
      srcName,
      isDir,
      nameUpdater ?? BFDefaultNameUpdater.noRegistry,
    );
    final destItemPath = await destDir.iosJoinRelPath(
      [destItemFileName].lock,
      isDir,
    );
    await _plugin.move(src.scopedUri(), destItemPath.scopedUri());
    return UpdatedBFPath(destItemPath, destItemFileName);
  }

  @override
  Future<Stream<List<int>>> readFileStream(
    BFPath path, {
    int? bufferSize,
    int? start,
  }) async {
    return _plugin.readFileStream(
      path.scopedUri(),
      bufferSize: bufferSize,
      start: start,
    );
  }

  @override
  Future<BFOutStream> writeFileStream(
    BFPath dir,
    String unsafeName, {
    BFNameUpdater? nameUpdater,
    bool? overwrite,
  }) async {
    final safeName = overwrite == true
        ? unsafeName
        : await ZBFInternal.nextAvailableFileName(
            this,
            dir,
            unsafeName,
            false,
            nameUpdater ?? BFDefaultNameUpdater.noRegistry,
          );
    final destPathUrl = await _darwinUrlPlugin.append(dir.toString(), [
      safeName,
    ], isDir: false);
    final destPath = BFScopedPath(destPathUrl);

    final session = await _plugin.startWriteStream(destPathUrl);
    return BFNsfcOutStream(session, _plugin, destPath, safeName);
  }

  @override
  Future<UpdatedBFPath> writeFileBytes(
    BFPath dir,
    String unsafeName,
    Uint8List bytes, {
    BFNameUpdater? nameUpdater,
    bool? overwrite,
  }) async {
    final safeName = overwrite == true
        ? unsafeName
        : await ZBFInternal.nextAvailableFileName(
            this,
            dir,
            unsafeName,
            false,
            nameUpdater ?? BFDefaultNameUpdater.noRegistry,
          );
    final destPathUrl = await _darwinUrlPlugin.append(dir.toString(), [
      safeName,
    ], isDir: false);
    final destPath = BFScopedPath(destPathUrl);
    await _plugin.writeFile(destPathUrl, bytes);
    return UpdatedBFPath(destPath, safeName);
  }

  @override
  Future<UpdatedBFPath> pasteLocalFile(
    String localSrc,
    BFPath dir,
    String unsafeName, {
    BFNameUpdater? nameUpdater,
    bool? overwrite,
  }) async {
    final safeName = overwrite == true
        ? unsafeName
        : await ZBFInternal.nextAvailableFileName(
            this,
            dir,
            unsafeName,
            false,
            nameUpdater ?? BFDefaultNameUpdater.noRegistry,
          );
    final destPath = await dir.iosJoinRelPath([safeName].lock, false);
    final srcUrl = await _darwinUrlPlugin.filePathToUrl(localSrc);
    await _plugin.copyPath(srcUrl, destPath.scopedUri(), overwrite: overwrite);
    return UpdatedBFPath(destPath, safeName);
  }

  @override
  Future<void> copyToLocalFile(BFPath src, String dest) async {
    final destUrl = await _darwinUrlPlugin.filePathToUrl(dest);
    await _plugin.copyPath(src.scopedUri(), destUrl);
  }

  @override
  Future<Uint8List> readFileBytes(BFPath path, {int? start, int? count}) async {
    return _plugin.readFileBytes(path.scopedUri(), start: start, count: count);
  }

  @override
  Future<BFPath?> fileExists(BFPath path, IList<String>? extendedPath) async {
    final finalPath = await _darwinUrlPlugin.append(
      path.toString(),
      extendedPath?.unlock ?? [],
      isDir: false,
    );
    final isDirRes = await _plugin.isDirectory(finalPath);
    if (isDirRes == false) {
      return BFScopedPath(finalPath);
    }
    return null;
  }

  @override
  Future<BFPath?> directoryExists(
    BFPath path,
    IList<String>? extendedPath,
  ) async {
    final finalPath = await _darwinUrlPlugin.append(
      path.toString(),
      extendedPath?.unlock ?? [],
      isDir: true,
    );
    final isDirRes = await _plugin.isDirectory(finalPath);
    if (isDirRes == true) {
      return BFScopedPath(finalPath);
    }
    return null;
  }

  @override
  Future<String?> findBasename(BFPath path, bool isDir) async {
    return _darwinUrlPlugin.basename(path.toString());
  }

  Future<BFEntity> _fromIcloudEntity(
    NsFileCoordinatorEntity entity, {
    required IList<String>? dirRelPath,
  }) async {
    const icloudExt = '.icloud';
    final eName = entity.name;
    final eUrl = entity.url;
    final isOnCloud = eName.startsWith('.') && eName.endsWith(icloudExt);
    // .ab.icloud
    // 0123456789
    //  []
    final realName = isOnCloud
        ? eName.substring(1, eName.length - icloudExt.length)
        : eName;
    final eDirUrl = await _darwinUrlPlugin.dirUrl(eUrl);
    final eRealUrl = isOnCloud
        ? await _darwinUrlPlugin.append(eDirUrl, [
            realName,
          ], isDir: entity.isDir)
        : eUrl;
    return BFEntity(
      BFScopedPath(eRealUrl),
      realName,
      entity.isDir,
      entity.length,
      entity.lastMod,
      isOnCloud,
      dirRelPath: dirRelPath,
    );
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
