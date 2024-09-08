import 'dart:io';
import '../bull_fs.dart';
import 'package:io/io.dart';
import 'package:path/path.dart' as p;
import 'package:collection/collection.dart';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';

class BFEnvLocal extends BFEnv {
  @override
  BFEnvType envType() {
    return BFEnvType.local;
  }

  @override
  bool isScoped() {
    return false;
  }

  @override
  Future<List<BFEntity>> listDir(BFPath path,
      {bool? recursive, bool? relativePathInfo}) async {
    final rootPath = path.localPath();
    final dirObj = Directory(rootPath);
    final entities = await dirObj.list(recursive: recursive ?? false).toList();
    final res = (await Future.wait(entities.map((e) {
      List<String>? dirRelPath;
      if (relativePathInfo == true) {
        final relPath = p.relative(e.path, from: rootPath).split(p.separator);
        if (relPath.length == 1) {
          dirRelPath = [];
        } else if (relPath.length > 1) {
          dirRelPath = relPath.sublist(0, relPath.length - 1);
        }
      }
      return BFEntity.fromLocalEntityNE(e, dirRelPath: dirRelPath);
    })))
        .whereNotNull()
        .toList();
    return res;
  }

  @override
  Future<List<BFPathAndDirRelPath>> listDirContentFiles(BFPath path) async {
    final rootPath = path.localPath();
    final dirObj = Directory(rootPath);
    final paths = await dirObj.list(recursive: true).toList();
    final res = paths
        .whereType<File>()
        .map((e) {
          List<String>? dirRelPath;
          final relPath = p.relative(e.path, from: rootPath).split(p.separator);
          if (relPath.length == 1) {
            dirRelPath = [];
          } else if (relPath.length > 1) {
            dirRelPath = relPath.sublist(0, relPath.length - 1);
          }
          return BFPathAndDirRelPath(BFLocalPath(e.path), dirRelPath ?? []);
        })
        .whereNotNull()
        .toList();
    return res;
  }

  @override
  Future<void> delete(BFPath path, bool isDir) async {
    if (isDir) {
      await Directory(path.localPath()).delete(recursive: true);
    } else {
      await File(path.localPath()).delete();
    }
  }

  @override
  Future<BFEntity?> stat(BFPath path, {IList<String>? relPath}) async {
    var filePath = path.localPath();
    if (relPath != null) {
      filePath = p.joinAll([filePath, ...relPath]);
    }
    // Remove the last /.
    if (filePath.endsWith('/')) {
      filePath = filePath.substring(0, filePath.length - 1);
    }
    final ioType = await FileSystemEntity.type(filePath);
    if (ioType == FileSystemEntityType.notFound) {
      return null;
    }

    if (ioType == FileSystemEntityType.directory) {
      return BFEntity.fromLocalEntity(Directory(filePath), dirRelPath: null);
    }
    return BFEntity.fromLocalEntity(File(filePath), dirRelPath: null);
  }

  @override
  Future<UpdatedBFPath> ensureDir(BFPath dir, String unsafeName) async {
    final path = p.join(dir.localPath(), unsafeName);
    await Directory(path).create(recursive: true);
    return UpdatedBFPath(BFLocalPath(path), null);
  }

  @override
  Future<UpdatedBFPath> ensureDirs(BFPath dir, IList<String> path) async {
    final finalPath = p.joinAll([dir.localPath(), ...path]);
    await Directory(finalPath).create(recursive: true);
    return UpdatedBFPath(BFLocalPath(finalPath), null);
  }

  @override
  Future<UpdatedBFPath> renameInternal(BFPath root, IList<String> src,
      String unsafeNewName, bool isDir, BFEntity srcStat) async {
    final path = srcStat.path;
    final filePath = path.localPath();
    final newPath = p.join(p.dirname(filePath), unsafeNewName);
    await _move(filePath, newPath, isDir);
    return UpdatedBFPath(BFLocalPath(newPath), null);
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
    final destItemPath = p.join(destDirStat.path.toString(), destItemFileName);

    await _move(srcStat.path.localPath(), destItemPath, isDir);
    return UpdatedBFPath(BFLocalPath(destItemPath), null);
  }

  Future<void> _move(String src, String dest, bool isDir) async {
    if (isDir) {
      await Directory(src).rename(dest);
    } else {
      await File(src).rename(dest);
    }
  }

  @override
  bool hasStreamSupport() {
    return true;
  }

  @override
  Future<Stream<List<int>>> readFileStream(BFPath path) async {
    return File(path.localPath()).openRead();
  }

  @override
  Future<BFOutStream> writeFileStream(BFPath dir, String unsafeName,
      {BFNameUpdaterFunc? nameUpdater}) async {
    final dirPath = dir.localPath();
    final safeName = await ZBFInternal.nextAvailableFileName(this, dir,
        unsafeName, false, nameUpdater ?? ZBFInternal.defaultFileNameUpdater);
    final destPath = p.join(dirPath, safeName);
    return writeFileStreamFromPath(destPath);
  }

  @override
  Future<UpdatedBFPath> pasteLocalFile(
      String localSrc, BFPath dir, String unsafeName,
      {BFNameUpdaterFunc? nameUpdater}) async {
    final safeName = await ZBFInternal.nextAvailableFileName(this, dir,
        unsafeName, false, nameUpdater ?? ZBFInternal.defaultFileNameUpdater);
    final dirPath = dir.localPath();
    final destPath = p.join(dirPath, safeName);
    final destBFPath = BFLocalPath(destPath);
    await _copy(localSrc, destBFPath.localPath(), false);
    return UpdatedBFPath(destBFPath, null);
  }

  @override
  Future<void> copyToLocalFile(BFPath src, String dest) async {
    await _copy(src.localPath(), dest, false);
  }

  Future<BFOutStream> writeFileStreamFromPath(String filePath) async {
    return BFLocalOutStream(File(filePath).openWrite(), BFLocalPath(filePath));
  }

  Future<void> _copy(String src, String dest, bool isDir) async {
    if (isDir) {
      await copyPath(src, dest);
    } else {
      await File(src).copy(dest);
    }
  }
}
