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
  Future<List<BFEntity>> listDir(BFPath path,
      {bool? recursive, bool? relativePathInfo});

  /// Unlike [listDir] with [recursive] and [relativePathInfo] set to `true`,
  /// this function doesn't fetch item stats. So it's faster.
  Future<List<BFPathAndDirRelPath>> listDirContentFiles(BFPath path);

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
  /// [overwrite] is whether to overwrite the existing file.
  Future<UpdatedBFPath> pasteLocalFile(
      String localSrc, BFPath dir, String unsafeName,
      {BFNameUpdaterFunc? nameUpdater, bool? overwrite});

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

  /// Like mkdir -p. Makes sure [dir]/[components]/ is created.
  ///
  /// [dir] is the parent directory.
  /// [components] is the path to create.
  Future<BFPath> mkdirp(BFPath dir, IList<String> components);

  /// Platform implementation of [BFEnv.rename].
  ///
  /// [root] is the root directory.
  /// [src] is the source path.
  /// [unsafeNewName] is the new name.
  /// [isDir] is whether the source is a directory.
  /// [srcStat] is the stat of the source path.
  @protected
  Future<UpdatedBFPath> renameInternal(BFPath root, IList<String> src,
      String unsafeNewName, bool isDir, BFEntity srcStat);

  /// Renames a file or directory.
  ///
  /// [root] is the root directory.
  /// [src] is the source path.
  /// [unsafeNewName] is the new name.
  /// [isDir] is whether the source is a directory.
  Future<UpdatedBFPath> rename(
      BFPath root, IList<String> src, String unsafeNewName, bool isDir) async {
    final st = await stat(root, relPath: src);
    if (st == null) {
      throw Exception('Path does not exist: ${src.join('/')}');
    }
    final newSt =
        await stat(root, relPath: [...src.parentDir(), unsafeNewName].lock);
    if (newSt != null) {
      throw Exception('Path already exists: ${newSt.path}');
    }
    return renameInternal(root, src, unsafeNewName, isDir, st);
  }

  /// Moves a file or directory to a directory.
  /// Use [nameUpdater] to update the file name if it conflicts with existing files.
  ///
  /// [root] is the root directory.
  /// [src] is the source path.
  /// [destDir] is the destination directory.
  /// [isDir] is whether the source is a directory.
  /// [nameUpdater] is a function to update the file name if it conflicts with existing files.
  /// [overwrite] is whether to overwrite the existing file.
  Future<UpdatedBFPath> moveToDir(
      BFPath root, IList<String> src, IList<String> destDir, bool isDir,
      {BFNameUpdaterFunc? nameUpdater, bool? overwrite}) {
    if (overwrite == true) {
      return _moveToDirByForce(root, src, destDir, isDir);
    }
    return moveToDirSafe(root, src, destDir, isDir, nameUpdater: nameUpdater);
  }

  /// Moves a file or directory to a directory.
  /// This is called by [moveToDir] when [overwrite] is `false`.
  /// Use [nameUpdater] to update the file name if it conflicts with existing files.
  ///
  /// [root] is the root directory.
  /// [src] is the source path.
  /// [destDir] is the destination directory.
  /// [isDir] is whether the source is a directory.
  /// [nameUpdater] is a function to update the file name if it conflicts with existing files.
  @protected
  Future<UpdatedBFPath> moveToDirSafe(
      BFPath root, IList<String> src, IList<String> destDir, bool isDir,
      {BFNameUpdaterFunc? nameUpdater});

  /// Moves a file or directory to a directory and overwrites the existing item.
  /// This is called by [moveToDir] when [overwrite] is `true`.
  Future<UpdatedBFPath> _moveToDirByForce(
      BFPath root, IList<String> src, IList<String> destDir, bool isDir) async {
    final fileName = src.last;
    final destItemRelPath = [...destDir, fileName].lock;
    final destItemStat = await stat(root, relPath: destItemRelPath);

    // Call `moveToDir` if the destination item does not exist and no new name assigned.
    if (destItemStat == null) {
      return moveToDirSafe(root, src, destDir, isDir);
    }

    final destDirStat = await stat(root, relPath: destDir);
    if (destDirStat == null) {
      throw Exception('Destination directory does not exist: $destDir');
    }
    final unsafeTmpDestName = tmpFileName();
    // Rename the destination item to a temporary name if it exists.
    final tmpDestInfo = await rename(
        root, destItemRelPath, unsafeTmpDestName, destItemStat.isDir);

    // Move the source item to the destination.
    final newPath = await moveToDirSafe(root, src, destDir, isDir);
    if (newPath.newName != fileName) {
      throw Exception(
          'Unexpected new name: ${newPath.newName}, expected: $fileName');
    }

    // Remove the overwritten destination item.
    await delete(tmpDestInfo.path, destItemStat.isDir);
    return newPath;
  }

  /// Reads a file as a stream of bytes.
  ///
  /// [path] is the file path.
  Future<Stream<List<int>>> readFileStream(BFPath path);

  /// Writes a file as a stream of bytes.
  ///
  /// [dir] is the directory to write the file.
  /// [unsafeName] is the file name. It's unsafe because it may conflict
  /// with existing files and may change.
  /// [nameUpdater] is a function to update the file name if it conflicts with existing files.
  /// [overwrite] is whether to overwrite the existing file.
  Future<BFOutStream> writeFileStream(BFPath dir, String unsafeName,
      {BFNameUpdaterFunc? nameUpdater, bool? overwrite});

  /// Reads a file as a byte array.
  ///
  /// [path] is the file path.
  Future<Uint8List> readFileSync(BFPath path);

  /// Writes a file as a byte array.
  ///
  /// [dir] is the directory to write the file.
  /// [unsafeName] is the file name. It's unsafe because it may conflict
  /// with existing files and may change.
  /// [nameUpdater] is a function to update the file name if it conflicts with existing files.
  /// [overwrite] is whether to overwrite the existing file.
  Future<UpdatedBFPath> writeFileSync(
      BFPath dir, String unsafeName, Uint8List bytes,
      {BFNameUpdaterFunc? nameUpdater, bool? overwrite});
}
