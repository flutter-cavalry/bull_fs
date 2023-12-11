import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:tmp_path/tmp_path.dart';
import 'bf_env.dart';
import 'internal.dart';
import 'types.dart';

extension IListStringExtension on IList<String> {
  IList<String> parentDir() {
    if (length == 0) {
      throw Exception('Cannot get parent dir of a root dir');
    }
    if (length == 1) {
      return IList<String>();
    }
    return take(length - 1).toIList();
  }
}

extension BFEnvExtension on BFEnv {
  Future<BFPath?> statPath(BFPath path, {IList<String>? relPath}) async {
    final res = await stat(path, relPath: relPath);
    return res?.path;
  }

  Future<BFPath?> child(BFPath path, {IList<String>? relPath}) async {
    final st = await stat(path, relPath: relPath);
    if (st == null) {
      return null;
    }
    return st.path;
  }

  Future<void> deletePathIfExists(BFPath path, {IList<String>? relPath}) async {
    final st = await stat(path, relPath: relPath);
    if (st == null) {
      return;
    }
    await delete(st.path, st.isDir);
  }

  Future<BFPath> mkdirpForFile(BFPath dir, IList<String> relFilePath) async {
    if (relFilePath.length == 1) {
      return dir;
    }
    return mkdirp(dir, relFilePath.take(relFilePath.length - 1).toIList());
  }

  Future<void> _listRecursiveFat(BFPath path, IList<String> dirRelPath,
      List<BFFatEntity> collector) async {
    final directChildren = await listDir(path);
    for (final child in directChildren) {
      if (child.isDir) {
        await _listRecursiveFat(
            child.path, [...dirRelPath, child.name].lock, collector);
      } else {
        collector.add(BFFatEntity(child, dirRelPath));
      }
    }
  }

  // Compared to `listDir`, it returns a list of `BFFatEntity` which contains
  // the dir rel path.
  Future<List<BFFatEntity>> listDirFat(BFPath path, IList<String>? dirRelPath) {
    final List<BFFatEntity> result = [];
    return _listRecursiveFat(path, dirRelPath ?? <String>[].lock, result)
        .then((_) => result);
  }

  Future<BFEntity?> fileExists(BFPath path, {IList<String>? relPath}) async {
    final st = await stat(path, relPath: relPath);
    if (st == null) {
      return null;
    }
    if (st.isDir) {
      return null;
    }
    return st;
  }

  Future<BFEntity?> directoryExists(BFPath path,
      {IList<String>? relPath}) async {
    final st = await stat(path, relPath: relPath);
    if (st == null) {
      return null;
    }
    if (!st.isDir) {
      return null;
    }
    return st;
  }

  Future<BFPath> moveAndReplace(
      BFPath root, IList<String> src, IList<String> dest, bool isDir) async {
    final srcPath = (await stat(root, relPath: src))?.path;
    if (srcPath == null) {
      throw Exception('$src is not found');
    }
    final destPath = (await stat(root, relPath: dest))?.path;
    if (destPath == null) {
      return move(root, src, dest, isDir);
    }

    final tmpDestName = tmpFileName();
    final tmpDestUri = await rename(destPath, tmpDestName, isDir);
    final movedPath = await move(root, src, dest, isDir);
    // Remove the renamed dest Uri after moving.
    await delete(tmpDestUri, isDir);
    return movedPath;
  }

  Future<BFPathAndName> moveAndKeepBoth(
      BFPath root, IList<String> src, IList<String> dest, bool isDir) async {
    final srcPath = (await stat(root, relPath: src))?.path;
    if (srcPath == null) {
      throw Exception('$src is not found');
    }
    final destPath = (await stat(root, relPath: dest))?.path;
    if (destPath == null) {
      final movedPath = await move(root, src, dest, isDir);
      return BFPathAndName(movedPath, dest.last);
    }

    final destDirPath = (await stat(root, relPath: dest.parentDir()))?.path;
    if (destDirPath == null) {
      throw Exception('Unexpected null stat at dest dir ${dest.parentDir()}');
    }

    final safeName = await zBFNonSAFNextAvailableFileName(
        this, destDirPath, dest.last, isDir);
    dest = [...dest.parentDir(), safeName].lock;
    final movedPath = await move(root, src, dest, isDir);
    return BFPathAndName(movedPath, safeName);
  }
}
