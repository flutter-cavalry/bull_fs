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
  Future<List<BFEntity>> listDir(BFPath path, {bool? recursive}) async {
    final dirObj = Directory(path.localPath());
    final entities = await dirObj.list(recursive: recursive ?? false).toList();
    final res =
        (await Future.wait(entities.map((e) => BFEntity.fromLocalEntityNE(e))))
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
      return BFEntity.fromLocalEntity(Directory(filePath));
    }
    return BFEntity.fromLocalEntity(File(filePath));
  }

  @override
  Future<BFPath> ensureDirCore(BFPath dir, String name) async {
    final path = p.join(dir.localPath(), name);
    await Directory(path).create(recursive: true);
    return BFLocalPath(path);
  }

  @override
  Future<BFPath> ensureDirs(BFPath dir, IList<String> path) async {
    final finalPath = p.joinAll([dir.localPath(), ...path]);
    await Directory(finalPath).create(recursive: true);
    return BFLocalPath(finalPath);
  }

  @override
  Future<BFPath> renameInternal(BFPath root, IList<String> src, String newName,
      bool isDir, BFEntity srcStat) async {
    final path = srcStat.path;
    final filePath = path.localPath();
    final newPath = p.join(p.dirname(filePath), newName);
    await _move(filePath, newPath, isDir);
    return BFLocalPath(newPath);
  }

  @override
  Future<BFPath> moveToDir(
      BFPath root, IList<String> src, IList<String> destDir, bool isDir,
      {String Function(String fileName, int attempt)? nameUpdater}) async {
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
    return BFLocalPath(destItemPath);
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
      {String Function(String fileName, int attempt)? nameUpdater}) async {
    final dirPath = dir.localPath();
    final safeName = await ZBFInternal.nextAvailableFileName(this, dir,
        unsafeName, false, nameUpdater ?? ZBFInternal.defaultFileNameUpdater);
    final destPath = p.join(dirPath, safeName);
    return writeFileStreamFromPath(destPath);
  }

  @override
  Future<BFPath> pasteLocalFile(String localSrc, BFPath dir, String unsafeName,
      {String Function(String fileName, int attempt)? nameUpdater}) async {
    final safeName = await ZBFInternal.nextAvailableFileName(this, dir,
        unsafeName, false, nameUpdater ?? ZBFInternal.defaultFileNameUpdater);
    final dirPath = dir.localPath();
    final destPath = p.join(dirPath, safeName);
    final destBFPath = BFLocalPath(destPath);
    await _copy(localSrc, destBFPath.localPath(), false);
    return destBFPath;
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
