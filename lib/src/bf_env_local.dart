import 'dart:io';
import 'package:io/io.dart';
import 'extensions.dart';
import 'package:path/path.dart' as p;
import 'package:collection/collection.dart';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'bf_env.dart';
import 'internal.dart';
import 'types.dart';

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
  Future<BFPath> mkdir(BFPath dir, String name) async {
    final path = p.join(dir.localPath(), name);
    await Directory(path).create(recursive: true);
    return BFLocalPath(path);
  }

  @override
  Future<BFPath> mkdirp(BFPath dir, IList<String> path) async {
    final finalPath = p.joinAll([dir.localPath(), ...path]);
    await Directory(finalPath).create(recursive: true);
    return BFLocalPath(finalPath);
  }

  @override
  Future<BFPath> rename(BFPath path, String newName, bool isDir) async {
    final filePath = path.localPath();
    final newPath = p.join(p.dirname(filePath), newName);
    if (await stat(BFLocalPath(newPath)) != null) {
      throw Exception('$newPath already exists');
    }

    await _move(filePath, newPath, isDir);
    return BFLocalPath(newPath);
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
    final destPathString = p.join(destDir.localPath(), dest.last);
    await _move(srcPath.localPath(), destPathString, isDir);
    return BFLocalPath(destPathString);
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
  Future<BFOutStream> writeFileStream(BFPath dir, String unsafeName) async {
    final dirPath = dir.localPath();
    final safeName =
        await zBFNonSAFNextAvailableFileName(this, dir, unsafeName, false);
    final destPath = p.join(dirPath, safeName);
    return writeFileStreamFromPath(destPath);
  }

  @override
  Future<BFPath> pasteLocalFile(
      String localSrc, BFPath dir, String unsafeName) async {
    final safeName =
        await zBFNonSAFNextAvailableFileName(this, dir, unsafeName, false);
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
