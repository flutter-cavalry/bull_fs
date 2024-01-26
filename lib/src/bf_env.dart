import '../bull_fs.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart';
import 'package:tmp_path/tmp_path.dart';

enum BFEnvType { local, saf, icloud }

typedef BFNameUpdaterFunc = String Function(
    String fileName, bool isDir, int attempt);

abstract class BFEnv {
  BFEnvType envType();
  bool isScoped();

  Future<List<BFEntity>> listDir(BFPath path, {bool? recursive});

  Future<void> copyToLocalFile(BFPath src, String dest);
  Future<BFPath> pasteLocalFile(String localSrc, BFPath dir, String unsafeName,
      {BFNameUpdaterFunc? nameUpdater});

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
      BFPath root, IList<String> src, IList<String> destDir, bool isDir,
      {BFNameUpdaterFunc? nameUpdater});

  Future<BFPath> forceMoveToDir(
      BFPath root, IList<String> src, IList<String> destDir, bool isDir,
      {String? newName}) async {
    // Normalize `newName`.
    if (newName != null && newName == src.last) {
      newName = null;
    }

    final fileName = newName ?? src.last;
    final destItemRelPath = [...destDir, fileName].lock;
    final destItemStat = await stat(root, relPath: destItemRelPath);

    // Call `moveToDir` if the destination item does not exist and no new name assigned.
    if (destItemStat == null && newName == null) {
      return moveToDir(root, src, destDir, isDir);
    }

    final destDirStat = await stat(root, relPath: destDir);
    if (destDirStat == null) {
      throw Exception('Destination directory does not exist: $destDir');
    }
    final tmpDestName = tmpFileName();

    // Rename the destination item to a temporary name if it exists.
    BFPath? tmpDestUri;
    if (destItemStat != null) {
      tmpDestUri =
          await rename(root, destItemRelPath, tmpDestName, destItemStat.isDir);
    }
    // Move the source item to the destination.
    var newPath = await moveToDir(root, src, destDir, isDir);
    // Rename the moved item to desired name if needed.
    final newStat = await stat(newPath);
    if (newStat == null) {
      throw Exception('Moved item does not exist: $newPath');
    }
    if (newStat.name != fileName) {
      newPath =
          await rename(root, [...destDir, newStat.name].lock, fileName, isDir);
    }

    // Remove the overwritten destination item if needed.
    if (tmpDestUri != null) {
      await delete(tmpDestUri, destItemStat!.isDir);
    }
    return newPath;
  }

  bool hasStreamSupport();

  Future<Stream<List<int>>> readFileStream(BFPath path);
  Future<BFOutStream> writeFileStream(BFPath dir, String unsafeName,
      {BFNameUpdaterFunc? nameUpdater});
}
