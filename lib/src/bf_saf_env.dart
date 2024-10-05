import '../bull_fs.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:saf_stream/saf_stream.dart';
import 'package:mg_shared_storage/shared_storage.dart' as saf;
import 'package:path/path.dart' as p;
import 'package:tmp_path/tmp_path.dart';

class BFSafEnv extends BFEnv {
  final _plugin = SafStream();

  @override
  BFEnvType envType() {
    return BFEnvType.saf;
  }

  @override
  bool isScoped() {
    return true;
  }

  Future<void> _listDirectChildren(
      BFPath path, List<BFEntity> collector, List<String>? dirRelPath) async {
    final objs = await saf.listFiles2(path.scopedSafUri());
    if (objs != null) {
      collector.addAll(objs
          .map((e) => _fromSAFEntity(e, dirRelPath: dirRelPath?.lock))
          .whereType<BFEntity>());
    }
  }

  Future<void> _listRecursiveChildren(
      BFPath path, List<BFEntity> collector, List<String>? dirRelPath) async {
    final List<BFEntity> firstLevel = [];
    await _listDirectChildren(path, firstLevel, dirRelPath);

    collector.addAll(firstLevel);
    final subDirs = firstLevel.where((e) => e.isDir);
    await Future.wait(subDirs.map((e) => _listRecursiveChildren(e.path,
        collector, dirRelPath == null ? null : [...dirRelPath, e.name])));
  }

  @override
  Future<List<BFEntity>> listDir(BFPath path,
      {bool? recursive, bool? relativePathInfo}) async {
    final res = <BFEntity>[];
    if (recursive == true) {
      await _listRecursiveChildren(
          path, res, relativePathInfo == true ? [] : null);
    } else {
      await _listDirectChildren(path, res, null);
    }
    return res;
  }

  @override
  Future<List<BFPathAndDirRelPath>> listDirContentFiles(BFPath path) async {
    final entities =
        await listDir(path, recursive: true, relativePathInfo: true);
    return entities
        .where((e) => !e.isDir)
        .map((e) => BFPathAndDirRelPath(e.path, e.dirRelPath))
        .toList();
  }

  @override
  Future<void> delete(BFPath path, bool isDir) async {
    await saf.delete(path.scopedSafUri());
  }

  @override
  Future<BFEntity?> stat(BFPath path, {IList<String>? relPath}) async {
    return _locate(path, relPath);
  }

  Future<UpdatedBFPath> _safMove(
      BFPath srcPath, BFPath srcDir, BFPath destDir) async {
    final res = await saf.moveEx(
        srcPath.scopedSafUri(), srcDir.scopedSafUri(), destDir.scopedSafUri());
    if (res == null) {
      throw Exception('Unexpected null result from moveEx');
    }
    final fileName = res.name;
    if (fileName == null || fileName.isEmpty) {
      throw Exception('Unexpected null or empty name from item stat');
    }
    return UpdatedBFPath(BFScopedPath(res.uri.toString()), fileName);
  }

  @override
  Future<UpdatedBFPath> moveToDirSafe(
      BFPath src, BFPath srcDir, BFPath destDir, bool isDir,
      {BFNameUpdaterFunc? nameUpdater}) async {
    // Since SAF doesn't allow renaming a file while moving. We first rename src file to a random name.
    // Then move the file to dest and rename it back to the desired name.
    BFPath? srcTmpUri;
    final srcName = await findBasename(src);
    if (srcName == null) {
      throw Exception('Unexpected null basename from item stat');
    }
    final srcTmpName = tmpFileName() + (isDir ? '' : p.extension(srcName));
    try {
      srcTmpUri = await rename(src, srcDir, srcTmpName, isDir);

      final unsafeDestName = srcName;
      final safeDestName = await ZBFInternal.nextAvailableFileName(
          this,
          destDir,
          unsafeDestName,
          isDir,
          nameUpdater ?? ZBFInternal.defaultFileNameUpdater);

      final tmpDestInfo = await _safMove(srcTmpUri, srcDir, destDir);

      // Rename it back to desired name.
      final destUri =
          await rename(tmpDestInfo.path, destDir, safeDestName, isDir);
      return UpdatedBFPath(destUri, safeDestName);
    } catch (err) {
      // Try reverting changes if exception happened.
      if (srcTmpUri != null && await stat(srcTmpUri) != null) {
        try {
          await rename(srcTmpUri, srcDir, srcName, isDir);
        } catch (_) {
          // Ignore exceptions during reverting.
          if (kDebugMode) {
            rethrow;
          }
        }
      }
      rethrow;
    }
  }

  Future<BFEntity?> _locate(BFPath path, IList<String>? relPath) async {
    final df = await saf.child(
        path.scopedSafUri(), relPath == null ? '' : relPath.join('/'));
    if (df == null) {
      return null;
    }
    return _fromSAFEntity(df, dirRelPath: null);
  }

  @override
  Future<BFPath> mkdirp(BFPath dir, IList<String> components) async {
    final stat = await saf.mkdirp(dir.scopedSafUri(), components.unlock);
    if (stat == null) {
      throw Exception('mkdirp of $dir + $components has failed');
    }
    if (stat.name == null || stat.name!.isEmpty) {
      throw Exception('Unexpected null or empty name from item stat');
    }
    return BFScopedPath(stat.uri.toString());
  }

  @override
  Future<BFPath> renameInternal(BFPath path, String newName, bool isDir) async {
    final newDF = await saf.renameTo(path.scopedSafUri(), newName);
    if (newDF == null) {
      throw Exception('rename failed at $path');
    }
    if (newDF.name == null || newDF.name!.isEmpty) {
      throw Exception('Unexpected null or empty name from item stat');
    }
    return BFScopedPath(newDF.uri.toString());
  }

  @override
  Future<Stream<List<int>>> readFileStream(BFPath path,
      {int? bufferSize, int? start}) async {
    return _plugin.readFileStream(path.scopedSafUri(),
        bufferSize: bufferSize, start: start);
  }

  @override
  Future<BFOutStream> writeFileStream(BFPath dir, String unsafeName,
      {BFNameUpdaterFunc? nameUpdater, bool? overwrite}) async {
    final safeName = overwrite == true
        ? unsafeName
        : await ZBFInternal.nextAvailableFileName(this, dir, unsafeName, false,
            nameUpdater ?? ZBFInternal.defaultFileNameUpdater);
    final res = await _plugin.startWriteStream(
        dir.scopedSafUri(), safeName, _getMime(safeName),
        overwrite: overwrite);
    final newFileName = res.fileResult.fileName;
    if (newFileName == null || newFileName.isEmpty) {
      throw Exception('Unexpected null fileName from writeFileStream');
    }
    return BFSafOutStream(res.session, _plugin,
        BFScopedPath(res.fileResult.uri.toString()), newFileName);
  }

  @override
  Future<UpdatedBFPath> writeFileSync(
      BFPath dir, String unsafeName, Uint8List bytes,
      {BFNameUpdaterFunc? nameUpdater, bool? overwrite}) async {
    final safeName = overwrite == true
        ? unsafeName
        : await ZBFInternal.nextAvailableFileName(this, dir, unsafeName, false,
            nameUpdater ?? ZBFInternal.defaultFileNameUpdater);
    final res = await _plugin.writeFileSync(
        dir.scopedSafUri(), safeName, _getMime(safeName), bytes,
        overwrite: overwrite);
    final fileName = res.fileName;
    if (fileName == null || fileName.isEmpty) {
      throw Exception('Unexpected null fileName from writeFileSync');
    }
    return UpdatedBFPath(BFScopedPath(res.uri.toString()), fileName);
  }

  String _getMime(String fileName) {
    return lookupMimeType(fileName) ??
        lookupMimeType(fileName) ??
        'application/octet-stream';
  }

  @override
  Future<UpdatedBFPath> pasteLocalFile(
      String localSrc, BFPath dir, String unsafeName,
      {BFNameUpdaterFunc? nameUpdater, bool? overwrite}) async {
    final safeName = overwrite == true
        ? unsafeName
        : await ZBFInternal.nextAvailableFileName(this, dir, unsafeName, false,
            nameUpdater ?? ZBFInternal.defaultFileNameUpdater);
    final res = await _plugin.pasteLocalFile(
        localSrc, dir.scopedSafUri(), safeName, _getMime(safeName),
        overwrite: overwrite);
    final fileName = res.fileName;
    if (fileName == null || fileName.isEmpty) {
      throw Exception('Unexpected null fileName from writeFileFromLocal');
    }
    return UpdatedBFPath(BFScopedPath(res.uri.toString()), fileName);
  }

  @override
  Future<void> copyToLocalFile(BFPath src, String dest) async {
    await _plugin.copyToLocalFile(src.scopedSafUri(), dest);
  }

  @override
  Future<Uint8List> readFileSync(BFPath path, {int? start, int? count}) async {
    return _plugin.readFileSync(path.scopedSafUri(),
        start: start, count: count);
  }

  @override
  Future<BFPath?> findPath(
      BFPath path, IList<String> components, bool isDir) async {
    final st = await stat(path, relPath: components);
    if (st == null) {
      return null;
    }
    if (st.isDir != isDir) {
      return null;
    }
    return st.path;
  }

  @override
  Future<String?> findBasename(BFPath path) async {
    final st = await stat(path);
    if (st == null) {
      return null;
    }
    return st.name;
  }

  BFEntity? _fromSAFEntity(saf.DocumentFile e,
      {required IList<String>? dirRelPath}) {
    final eName = e.name;
    if (eName == null) {
      return null;
    }
    return BFEntity(BFScopedPath(e.uri.toString()), eName,
        e.isDirectory ?? false, e.size ?? 0, e.lastModified, false,
        dirRelPath: dirRelPath);
  }
}

class BFSafOutStream extends BFOutStream {
  final String _session;
  final SafStream _plugin;
  final BFPath _path;
  final String _fileName;

  bool _closed = false;

  BFSafOutStream(this._session, this._plugin, this._path, this._fileName);

  @override
  BFPath getPath() {
    return _path;
  }

  @override
  String getFileName() {
    return _fileName;
  }

  @override
  Future<void> write(Uint8List data) async {
    await _plugin.writeChunk(_session, data);
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    await _plugin.endWriteStream(_session);
    _closed = true;
  }

  @override
  Future<void> flush() async {}
}
