import 'package:bull_fs/bull_fs.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart';
import 'package:tmp_path/tmp_path.dart';

enum BFEnvType { local, saf, icloud }

abstract class BFEnv {
  BFEnvType envType();
  bool isScoped();

  Future<List<BFEntity>> listDir(BFPath path, {bool? recursive});

  Future<void> copyToLocalFile(BFPath src, String dest);
  Future<BFPath> pasteLocalFile(String localSrc, BFPath dir, String unsafeName);

  Future<void> delete(BFPath path, bool isDir);

  Future<BFEntity?> stat(BFPath path, {IList<String>? relPath});

  Future<BFPath> ensureDirCore(
    BFPath dir,
    String name,
  );
  Future<BFPath> ensureDirs(BFPath dir, IList<String> path);

  Future<BFPath> ensureDir(BFPath dir, String name) async {
    final st = await stat(dir, relPath: [name].lock);
    if (st != null) {
      if (st.isDir) {
        return st.path;
      } else {
        throw Exception('Path exists but is not a directory: ${st.path}');
      }
    }
    return ensureDirCore(dir, name);
  }

  @protected
  Future<BFPath> renameInternal(BFPath root, IList<String> src, String newName,
      bool isDir, BFEntity srcStat);

  Future<BFPath> rename(
      BFPath root, IList<String> src, String newName, bool isDir) async {
    final st = await stat(root, relPath: src);
    if (st == null) {
      throw Exception('Path does not exist: ${src.join('/')}');
    }
    final newSt = await stat(root, relPath: [...src.parentDir(), newName].lock);
    if (newSt != null) {
      throw Exception('Path already exists: ${newSt.path}');
    }
    return renameInternal(root, src, newName, isDir, st);
  }

  Future<BFPath> moveToDir(
      BFPath root, IList<String> src, IList<String> destDir, bool isDir);

  Future<BFPath> moveToDirOverwrite(
      BFPath root, IList<String> src, IList<String> destDir, bool isDir) async {
    final fileName = src.last;
    final destItemStat =
        (await stat(root, relPath: [...destDir, fileName].lock));

    // Call `moveToDir` if the destination item does not exist.
    if (destItemStat == null) {
      return moveToDir(root, src, destDir, isDir);
    }

    final destDirStat = await stat(root, relPath: destDir);
    if (destDirStat == null) {
      throw Exception('Destination directory does not exist: $destDir');
    }
    final tmpDestName = tmpFileName();
    // Rename the destination item to a temporary name.
    final tmpDestUri = await rename(
        root, [...destDir, fileName].lock, tmpDestName, destItemStat.isDir);
    // Move the source item to the destination.
    final movedPath = await moveToDir(root, src, destDir, isDir);
    // Remove the tmp item.
    await delete(tmpDestUri, isDir);
    return movedPath;
  }

  bool hasStreamSupport();

  Future<Stream<List<int>>> readFileStream(BFPath path);
  Future<BFOutStream> writeFileStream(BFPath dir, String unsafeName);
}
