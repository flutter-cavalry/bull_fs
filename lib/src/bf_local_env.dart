import 'dart:io';
import 'dart:typed_data';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:io/io.dart';
import 'package:path/path.dart' as p;

import '../bull_fs.dart';

/// A [BFEnv] implementation for local file system.
class BFLocalEnv extends BFEnv {
  static final BFLocalEnv instance = BFLocalEnv();

  @override
  BFEnvType envType() {
    return BFEnvType.local;
  }

  @override
  bool isScoped() {
    return false;
  }

  @override
  Future<List<BFEntity>> listDir(
    BFPath path, {
    bool? recursive,
    bool? relativePathInfo,
  }) async {
    final rootPath = path.localPath();
    final dirObj = Directory(rootPath);
    final entities = await dirObj.list(recursive: recursive ?? false).toList();
    final res = (await Future.wait(
      entities.map((e) {
        List<String>? dirRelPath;
        if (relativePathInfo == true) {
          final relPath = p.relative(e.path, from: rootPath).split(p.separator);
          if (relPath.length == 1) {
            dirRelPath = [];
          } else if (relPath.length > 1) {
            dirRelPath = relPath.sublist(0, relPath.length - 1);
          }
        }
        return BFEntity.fromLocalEntityNE(e, dirRelPath: dirRelPath?.lock);
      }),
    )).nonNulls.toList();
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
          return BFPathAndDirRelPath(
            BFLocalPath(e.path),
            (dirRelPath ?? []).lock,
          );
        })
        .nonNulls
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
  Future<BFEntity?> stat(BFPath path, bool? isDir) async {
    return _stat(path.localPath());
  }

  @override
  Future<BFEntity?> child(BFPath path, IList<String> names) async {
    var filePath = p.joinAll([path.localPath(), ...names]);
    // Remove the last /.
    if (filePath.endsWith('/')) {
      filePath = filePath.substring(0, filePath.length - 1);
    }
    return _stat(filePath);
  }

  Future<BFEntity?> _stat(String filePath) async {
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
  Future<BFPath> mkdirp(BFPath dir, IList<String> components) async {
    final finalPath = p.joinAll([dir.localPath(), ...components]);
    await Directory(finalPath).create(recursive: true);
    return BFLocalPath(finalPath);
  }

  @override
  Future<BFPath> renameInternal(BFPath path, bool isDir, String newName) async {
    final filePath = path.localPath();
    final newPath = p.join(p.dirname(filePath), newName);
    await _move(filePath, newPath, isDir);
    return BFLocalPath(newPath);
  }

  @override
  Future<UpdatedBFPath> moveToDirSafe(
    BFPath src,
    bool isDir,
    BFPath srcDir,
    BFPath destDir, {
    BFNameFinder? nameFinder,
    Set<String>? pendingNames,
  }) async {
    final unsafeSrcName = p.basename(src.localPath());
    final safeDestName = await (nameFinder ?? BFNameFinder.instance)
        .findFileName(
          this,
          destDir,
          unsafeSrcName,
          isDir,
          pendingNames: pendingNames,
        );
    final destItemPath = p.join(destDir.toString(), safeDestName);

    await _move(src.localPath(), destItemPath, isDir);
    return UpdatedBFPath(BFLocalPath(destItemPath), safeDestName);
  }

  Future<void> _move(String src, String dest, bool isDir) async {
    if (isDir) {
      await Directory(src).rename(dest);
    } else {
      await File(src).rename(dest);
    }
  }

  @override
  Future<Stream<List<int>>> readFileStream(
    BFPath path, {
    int? bufferSize,
    int? start,
  }) async {
    return File(path.localPath()).openRead(start);
  }

  @override
  Future<BFOutStream> writeFileStream(
    BFPath dir,
    String unsafeName, {
    BFNameFinder? nameFinder,
    Set<String>? pendingNames,
    bool? overwrite,
  }) async {
    final dirPath = dir.localPath();
    final safeName = overwrite == true
        ? unsafeName
        : await (nameFinder ?? BFNameFinder.instance).findFileName(
            this,
            dir,
            unsafeName,
            false,
            pendingNames: pendingNames,
          );
    final destPath = p.join(dirPath, safeName);
    return await outStreamForLocalPath(destPath);
  }

  @override
  Future<UpdatedBFPath> writeFileBytes(
    BFPath dir,
    String unsafeName,
    Uint8List bytes, {
    BFNameFinder? nameFinder,
    Set<String>? pendingNames,
    bool? overwrite,
  }) async {
    final dirPath = dir.localPath();
    final safeName = overwrite == true
        ? unsafeName
        : await (nameFinder ?? BFNameFinder.instance).findFileName(
            this,
            dir,
            unsafeName,
            false,
            pendingNames: pendingNames,
          );
    final destPath = p.join(dirPath, safeName);
    await File(destPath).writeAsBytes(bytes);
    return UpdatedBFPath(BFLocalPath(destPath), safeName);
  }

  @override
  Future<UpdatedBFPath> pasteLocalFile(
    String localSrc,
    BFPath dir,
    String unsafeName, {
    BFNameFinder? nameFinder,
    Set<String>? pendingNames,
    bool? overwrite,
  }) async {
    final safeName = overwrite == true
        ? unsafeName
        : await (nameFinder ?? BFNameFinder.instance).findFileName(
            this,
            dir,
            unsafeName,
            false,
            pendingNames: pendingNames,
          );
    final dirPath = dir.localPath();
    final destPath = p.join(dirPath, safeName);
    final destBFPath = BFLocalPath(destPath);
    await _copy(localSrc, destBFPath.localPath(), false);
    return UpdatedBFPath(destBFPath, safeName);
  }

  @override
  Future<void> copyToLocalFile(BFPath src, String dest) async {
    await _copy(src.localPath(), dest, false);
  }

  @override
  Future<Uint8List> readFileBytes(BFPath path, {int? start, int? count}) async {
    if (start != null || count != null) {
      final randomAccessFile = await File(path.localPath()).open();
      try {
        await randomAccessFile.setPosition(start ?? 0);
        final bytes = count != null
            ? await randomAccessFile.read(count)
            : await randomAccessFile.read(await randomAccessFile.length());
        return bytes;
      } finally {
        await randomAccessFile.close();
      }
    }
    return await File(path.localPath()).readAsBytes();
  }

  Future<BFOutStream> outStreamForLocalPath(String filePath) async {
    return BFLocalRafOutStream(
      await File(filePath).open(mode: FileMode.writeOnly),
      BFLocalPath(filePath),
    );
  }

  Future<void> _copy(String src, String dest, bool isDir) async {
    if (isDir) {
      await copyPath(src, dest);
    } else {
      await File(src).copy(dest);
    }
  }

  @override
  Future<BFPath?> fileExists(BFPath path, IList<String>? extendedPath) async {
    final finalPath = p.joinAll([path.localPath(), ...(extendedPath ?? [])]);
    final ioType = await FileSystemEntity.type(finalPath);
    if (ioType == FileSystemEntityType.file) {
      return BFLocalPath(finalPath);
    }
    return null;
  }

  @override
  Future<BFPath?> directoryExists(
    BFPath path,
    IList<String>? extendedPath,
  ) async {
    final finalPath = p.joinAll([path.localPath(), ...(extendedPath ?? [])]);
    final ioType = await FileSystemEntity.type(finalPath);
    if (ioType == FileSystemEntityType.directory) {
      return BFLocalPath(finalPath);
    }
    return null;
  }

  @override
  Future<String?> findBasename(BFPath path, bool isDir) async {
    return p.basename(path.localPath());
  }
}
