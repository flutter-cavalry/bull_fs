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

  /// NSFileCoordinator, which is used by iOS and macOS icloud documents.
  nsfc
}

typedef BFNameUpdaterFunc = String Function(
    String fileName, bool isDir, int attempt);

/// Base class for file system environments.
abstract class BFEnv {
  /// Type of the environment.
  BFEnvType envType();

  /// Whether the environment is Uri-based.
  /// This is true when for [BFEnvType.saf] and [BFEnvType.nsfc].
  bool isScoped();

  /// Lists sub-directories and files in a directory.
  ///
  /// [path] is the directory to list.
  /// [recursive] is whether to list recursively.
  Future<List<BFEntity>> listDir(BFPath path,
      {bool? recursive, bool? relativePathInfo});

  /// Lists only sub-files and their relative paths in a directory recursively.
  /// You can achieve the same thing with [listDir] with [recursive] and
  /// [relativePathInfo] set to `true`. But this function is much faster as it
  /// doesn't fetch file stats.
  ///
  /// [path] is the directory to list.
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
  /// [path] is the path to delete.
  /// [isDir] is whether the path is a directory.
  Future<BFEntity?> stat(BFPath path, bool isDir);

  /// Gets a child identified by [path] + [names].
  ///
  /// [path] starting path.
  /// [names] path components to be appended to the path.
  Future<BFEntity?> child(BFPath path, IList<String> names);

  /// Like mkdir -p. Makes sure [dir]/[components]/ is created.
  ///
  /// [dir] is the parent directory.
  /// [components] is the path to create.
  Future<BFPath> mkdirp(BFPath dir, IList<String> components);

  /// Creates a new directory. Unlike [mkdirp], this function always creates a new directory.
  /// If the directory already exists, it uses [nameUpdater] to find a new name.
  ///
  /// [dir] is the parent directory.
  /// [unsafeName] is the directory name. It's unsafe because it may conflict
  /// with existing files and may change.
  /// [nameUpdater] is a function to update the file name if it conflicts with existing files.
  Future<UpdatedBFPath> createDir(BFPath dir, String unsafeName,
      {BFNameUpdaterFunc? nameUpdater}) async {
    final safeName = await ZBFInternal.nextAvailableFileName(this, dir,
        unsafeName, true, nameUpdater ?? ZBFInternal.defaultFileNameUpdater);
    final newDir = await mkdirp(dir, [safeName].lock);
    return UpdatedBFPath(newDir, safeName);
  }

  /// Platform implementation of [BFEnv.rename].
  ///
  /// [path] is the item path.
  /// [isDir] is whether the source is a directory.
  /// [newName] is the new name.
  @protected
  Future<BFPath> renameInternal(BFPath path, bool isDir, String newName);

  /// Renames a file or directory.
  ///
  /// [path] is the item path.
  /// [isDir] is whether the source is a directory.
  /// [parentDir] is the parent directory.
  /// [newName] is the new name.
  Future<BFPath> rename(
      BFPath path, bool isDir, BFPath parentDir, String newName) async {
    final newSt = await child(parentDir, [newName].lock);
    if (newSt != null) {
      throw Exception('Path already exists: ${newSt.path}');
    }
    return renameInternal(path, isDir, newName);
  }

  /// Moves a file or directory to a directory.
  /// Use [nameUpdater] to update the file name if it conflicts with existing files.
  ///
  /// [src] is the source path.
  /// [isDir] is whether the source is a directory.
  /// [srcDir] is the parent directory of the source.
  /// [destDir] is the destination directory.
  /// [nameUpdater] is a function to update the file name if it conflicts with existing files.
  /// [overwrite] is whether to overwrite the existing file.
  Future<UpdatedBFPath> moveToDir(
      BFPath src, bool isDir, BFPath srcDir, BFPath destDir,
      {BFNameUpdaterFunc? nameUpdater, bool? overwrite}) {
    if (overwrite == true) {
      return _moveToDirByForce(src, isDir, srcDir, destDir);
    }
    return moveToDirSafe(src, isDir, srcDir, destDir, nameUpdater: nameUpdater);
  }

  /// Moves a file or directory to a directory.
  /// This is called by [moveToDir] when [overwrite] is `false`.
  /// Use [nameUpdater] to update the file name if it conflicts with existing files.
  ///
  /// [src] is the source path.
  /// [isDir] whether the source is a directory.
  /// [srcDir] is the parent directory of the source.
  /// [destDir] is the destination directory.
  /// [nameUpdater] is a function to update the file name if it conflicts with existing files.
  @protected
  Future<UpdatedBFPath> moveToDirSafe(
      BFPath src, bool isDir, BFPath srcDir, BFPath destDir,
      {BFNameUpdaterFunc? nameUpdater});

  /// Moves a file or directory to a directory and overwrites the existing item.
  /// This is called by [moveToDir] when [overwrite] is `true`.
  Future<UpdatedBFPath> _moveToDirByForce(
      BFPath src, bool isDir, BFPath srcDir, BFPath destDir) async {
    final srcName = await findBasename(src, isDir);
    if (srcName == null) {
      throw Exception('Unexpected null basename from item stat');
    }
    final destItemStat = await child(destDir, [srcName].lock);

    // Call `moveToDir` if the destination item does not exist and no new name assigned.
    if (destItemStat == null) {
      final newPath = await moveToDirSafe(src, isDir, srcDir, destDir);
      if (newPath.newName != srcName) {
        throw Exception(
            'Unexpected new name: ${newPath.newName}, expected: $srcName');
      }
      return newPath;
    }

    final tmpDestName = tmpFileName();
    // Rename the destination item to a temporary name if it exists.
    final tmpDestPath = await rename(
        destItemStat.path, destItemStat.isDir, destDir, tmpDestName);

    // Move the source item to the destination.
    final newPath = await moveToDirSafe(src, isDir, srcDir, destDir);
    if (newPath.newName != srcName) {
      throw Exception(
          'Unexpected new name: ${newPath.newName}, expected: $srcName');
    }

    // Remove the tmp file after it's been overwritten.
    await delete(tmpDestPath, destItemStat.isDir);
    return newPath;
  }

  /// Reads a file as a stream of bytes.
  ///
  /// [path] is the file path.
  /// [bufferSize] is the buffer size.
  /// [start] is the start position.
  Future<Stream<List<int>>> readFileStream(BFPath path,
      {int? bufferSize, int? start});

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
  /// [start] is the start position.
  /// [count] is the number of bytes to read.
  Future<Uint8List> readFileBytes(BFPath path, {int? start, int? count});

  /// Writes a file as a byte array.
  ///
  /// [dir] is the directory to write the file.
  /// [unsafeName] is the file name. It's unsafe because it may conflict
  /// with existing files and may change.
  /// [nameUpdater] is a function to update the file name if it conflicts with existing files.
  /// [overwrite] is whether to overwrite the existing file.
  Future<UpdatedBFPath> writeFileBytes(
      BFPath dir, String unsafeName, Uint8List bytes,
      {BFNameUpdaterFunc? nameUpdater, bool? overwrite});

  /// Returns a [BFPath] if the specified [path]/[extendedPath] exists and is a file.
  Future<BFPath?> fileExists(BFPath path, IList<String>? extendedPath);

  /// Returns a [BFPath] if the specified [path]/[extendedPath] exists and is a directory.
  Future<BFPath?> directoryExists(BFPath path, IList<String>? extendedPath);

  /// Gets the basename of a path.
  ///
  /// [path] is the path to get the basename.
  /// [isDir] whether the path is a directory.
  Future<String?> findBasename(BFPath path, bool isDir);
}
