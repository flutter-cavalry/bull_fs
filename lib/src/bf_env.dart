import '../bull_fs.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart';
import 'package:tmp_path/tmp_path.dart';

/// Type of [BFEnv].
enum BFEnvType {
  /// Local path.
  local,

  /// Android SAF.
  saf,

  /// Apple iCloud.
  icloud
}

typedef BFNameUpdaterFunc = String Function(
    String fileName, bool isDir, int attempt);

/// Base class for file system environments.
abstract class BFEnv {
  /// Type of the environment.
  BFEnvType envType();

  /// Whether the environment is Uri-based.
  /// This is true when for [BFEnvType.saf] and [BFEnvType.icloud].
  bool isScoped();

  /// Lists sub-directories and files in a directory.
  ///
  /// [path] is the directory to list.
  /// [recursive] is whether to list recursively.
  Future<List<BFEntity>> listDir(BFPath path, {bool? recursive});

  /// Copies a [BFPath] to a local file.
  ///
  /// [src] is the source path.
  /// [dest] is the destination file path.
  Future<void> copyToLocalFile(BFPath src, String dest);

  /// Copies a local file to a [BFPath].
  ///
  /// [localSrc] is the source local file path.
  /// [dir] is the destination directory.
  /// [unsafeName] is the destination file name. It's unsafe because it may conflict
  /// with existing files and may change.
  /// [nameUpdater] is a function to update the file name if it conflicts with existing files.
  Future<BFPath> pasteLocalFile(String localSrc, BFPath dir, String unsafeName,
      {BFNameUpdaterFunc? nameUpdater});

  /// Deletes a file or directory.
  ///
  /// [path] is the path to delete.
  /// [isDir] is whether the path is a directory.
  Future<void> delete(BFPath path, bool isDir);

  /// Gets the stat of a file or directory.
  ///
  /// [path] is the path to get the stat.
  /// [relPath] is the relative path to get the stat.
  Future<BFEntity?> stat(BFPath path, {IList<String>? relPath});

  /// Like mkdir. Makes sure [dir]/[name]/ is created.
  /// Use [ensureDir] instead of [ensureDirCore] for better error handling.
  ///
  /// [dir] is the parent directory.
  /// [name] is the directory name.
  Future<BFPath> ensureDirCore(
    BFPath dir,
    String name,
  );

  /// Like mkdir -p. Makes sure [dir]/[path]/ is created.
  ///
  /// [dir] is the parent directory.
  /// [path] is the path to create.
  Future<BFPath> ensureDirs(BFPath dir, IList<String> path);

  /// Based on [ensureDirCore], but throws an error if the path exists but is not a directory.
  ///
  /// [dir] is the parent directory.
  /// [name] is the directory name.
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

  /// Platform implementation of [BFEnv.rename].
  ///
  /// [root] is the root directory.
  /// [src] is the source path.
  /// [newName] is the new name.
  /// [isDir] is whether the source is a directory.
  /// [srcStat] is the stat of the source path.
  @protected
  Future<BFPath> renameInternal(BFPath root, IList<String> src, String newName,
      bool isDir, BFEntity srcStat);

  /// Renames a file or directory.
  ///
  /// [root] is the root directory.
  /// [src] is the source path.
  /// [newName] is the new name.
  /// [isDir] is whether the source is a directory.
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

  /// Moves a file or directory to a directory.
  /// Use [nameUpdater] to update the file name if it conflicts with existing files.
  ///
  /// [root] is the root directory.
  /// [src] is the source path.
  /// [destDir] is the destination directory.
  /// [isDir] is whether the source is a directory.
  /// [nameUpdater] is a function to update the file name if it conflicts with existing files.
  Future<BFPath> moveToDir(
      BFPath root, IList<String> src, IList<String> destDir, bool isDir,
      {BFNameUpdaterFunc? nameUpdater});

  /// Moves a file or directory to a directory.
  /// Unlike [moveToDir], this function will overwrite the destination item if it exists.
  ///
  /// [root] is the root directory.
  /// [src] is the source path.
  /// [destDir] is the destination directory.
  /// [isDir] is whether the source is a directory.
  /// [newName] is the new name.
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
