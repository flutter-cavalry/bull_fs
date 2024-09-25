import 'dart:io';
import 'dart:typed_data';
import '../bull_fs.dart';
import 'package:io/io.dart';
import 'package:path/path.dart' as p;
import 'package:collection/collection.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

class BFLocalEnv extends BFEnv {
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
      return BFEntity.fromLocalEntityNE(e, dirRelPath: dirRelPath?.lock);
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
          return BFPathAndDirRelPath(
              BFLocalPath(e.path), (dirRelPath ?? []).lock);
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
  Future<BFPath> mkdirp(BFPath dir, IList<String> components) async {
    final finalPath = p.joinAll([dir.localPath(), ...components]);
    await Directory(finalPath).create(recursive: true);
    return BFLocalPath(finalPath);
  }

  @override
  Future<BFPath> renameInternal(BFPath path, String newName, bool isDir) async {
    final filePath = path.localPath();
    final newPath = p.join(p.dirname(filePath), newName);
    await _move(filePath, newPath, isDir);
    return BFLocalPath(newPath);
  }

  @override
  Future<UpdatedBFPath> moveToDirSafe(
      BFPath src, BFPath srcDir, BFPath destDir, bool isDir,
      {BFNameUpdaterFunc? nameUpdater}) async {
    final srcName = p.basename(src.localPath());
    final destItemFileName = await ZBFInternal.nextAvailableFileName(
        this,
        destDir,
        srcName,
        isDir,
        nameUpdater ?? ZBFInternal.defaultFileNameUpdater);
    final destItemPath = p.join(destDir.toString(), destItemFileName);

    await _move(src.localPath(), destItemPath, isDir);
    return UpdatedBFPath(BFLocalPath(destItemPath), destItemFileName);
  }

  Future<void> _move(String src, String dest, bool isDir) async {
    if (isDir) {
      await Directory(src).rename(dest);
    } else {
      await File(src).rename(dest);
    }
  }

  @override
  Future<Stream<List<int>>> readFileStream(BFPath path) async {
    return File(path.localPath()).openRead();
  }

  @override
  Future<BFOutStream> writeFileStream(BFPath dir, String unsafeName,
      {BFNameUpdaterFunc? nameUpdater, bool? overwrite}) async {
    final dirPath = dir.localPath();
    final safeName = overwrite == true
        ? unsafeName
        : await ZBFInternal.nextAvailableFileName(this, dir, unsafeName, false,
            nameUpdater ?? ZBFInternal.defaultFileNameUpdater);
    final destPath = p.join(dirPath, safeName);
    return outStreamForLocalPath(destPath);
  }

  @override
  Future<UpdatedBFPath> writeFileSync(
      BFPath dir, String unsafeName, Uint8List bytes,
      {BFNameUpdaterFunc? nameUpdater, bool? overwrite}) async {
    final dirPath = dir.localPath();
    final safeName = overwrite == true
        ? unsafeName
        : await ZBFInternal.nextAvailableFileName(this, dir, unsafeName, false,
            nameUpdater ?? ZBFInternal.defaultFileNameUpdater);
    final destPath = p.join(dirPath, safeName);
    await File(destPath).writeAsBytes(bytes);
    return UpdatedBFPath(BFLocalPath(destPath), safeName);
  }

  @override
  Future<UpdatedBFPath> pasteLocalFile(
      String localSrc, BFPath dir, String unsafeName,
      {BFNameUpdaterFunc? nameUpdater, bool? overwrite}) async {
    final safeName = overwrite == true
        ? unsafeName
        : await ZBFInternal.nextAvailableFileName(this, dir, unsafeName, false,
            nameUpdater ?? ZBFInternal.defaultFileNameUpdater);
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
  Future<Uint8List> readFileSync(BFPath path) async {
    return await File(path.localPath()).readAsBytes();
  }

  Future<BFOutStream> outStreamForLocalPath(String filePath) async {
    return BFLocalOutStream(File(filePath).openWrite(), BFLocalPath(filePath));
  }

  Future<void> _copy(String src, String dest, bool isDir) async {
    if (isDir) {
      await copyPath(src, dest);
    } else {
      await File(src).copy(dest);
    }
  }

  @override
  Future<BFPath?> appendPath(
      BFPath path, IList<String> components, bool isDir) async {
    final finalPath = p.joinAll([path.localPath(), ...components]);
    return BFLocalPath(finalPath);
  }

  @override
  Future<String?> basenameOfPath(BFPath path) async {
    return p.basename(path.localPath());
  }
}
