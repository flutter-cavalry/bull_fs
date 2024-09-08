import '../bull_fs.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:saf_stream/saf_stream.dart';
import 'package:mg_shared_storage/shared_storage.dart' as saf;
import 'package:path/path.dart' as p;
import 'package:tmp_path/tmp_path.dart';

class BFEnvAndroidSAF extends BFEnv {
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
          .map((e) => _fromSAFEntity(e, dirRelPath: dirRelPath))
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
    // TODO: write a faster implementation instead of using listDir.
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

  Future<BFPath> _safMove(
      BFPath srcPath, BFPath srcDirPath, BFPath destDir) async {
    final res = await saf.moveEx(srcPath.scopedSafUri(),
        srcDirPath.scopedSafUri(), destDir.scopedSafUri());
    if (res == null) {
      throw Exception('Unexpected null result from moveEx');
    }
    return BFScopedPath(res.uri.toString());
  }

  @override
  Future<BFPath> moveToDir(
      BFPath root, IList<String> src, IList<String> destDir, bool isDir,
      {BFNameUpdaterFunc? nameUpdater}) async {
    final srcParentStat =
        await ZBFInternal.mustGetStat(this, root, src.parentDir());
    final destDirStat = await ZBFInternal.mustGetStat(this, root, destDir);
    if (!destDirStat.isDir) {
      throw Exception('$destDir is not a directory');
    }

    // Since SAF doesn't allow renaming a file while moving. We first rename src file to a random name.
    // Then move the file to dest and rename it back to the desired name.
    BFPath? srcTmpUri;
    final srcTmpName = tmpFileName() + (isDir ? '' : p.extension(src.last));
    try {
      srcTmpUri = await rename(root, src, srcTmpName, isDir);

      final unsafeDestName = src.last;
      final safeDestName = await ZBFInternal.nextAvailableFileName(
          this,
          destDirStat.path,
          unsafeDestName,
          isDir,
          nameUpdater ?? ZBFInternal.defaultFileNameUpdater);
      var destUri =
          await _safMove(srcTmpUri, srcParentStat.path, destDirStat.path);

      // Rename it back to desired name.
      destUri = await rename(
          root, [...destDir, srcTmpName].lock, safeDestName, isDir);
      return destUri;
    } catch (err) {
      // Try reverting changes if exception happened.
      if (srcTmpUri != null && await stat(srcTmpUri) != null) {
        try {
          await rename(
              root, [...src.parentDir(), srcTmpName].lock, src.last, isDir);
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
  Future<BFPath> ensureDirCore(BFPath dir, String name) async {
    // If `name` exists, Android SAF creates a `name (1)`. We will return the existing URI in that case.
    final st = await stat(dir, relPath: [name].lock);
    if (st != null) {
      return st.path;
    }
    final df = await saf.createDirectory(dir.scopedSafUri(), name);
    if (df == null) {
      throw Exception('mkdir failed at $dir');
    }
    return BFScopedPath(df.uri.toString());
  }

  @override
  Future<BFPath> ensureDirs(BFPath dir, IList<String> path) async {
    final stat = await saf.mkdirp(dir.scopedSafUri(), path.unlock);
    if (stat == null) {
      throw Exception('mkdirp of $dir + $path has failed');
    }
    return BFScopedPath(stat.uri.toString());
  }

  @override
  Future<BFPath> renameInternal(BFPath root, IList<String> src, String newName,
      bool isDir, BFEntity srcStat) async {
    final path = srcStat.path;
    final newDF = await saf.renameTo(path.scopedSafUri(), newName);
    if (newDF == null) {
      throw Exception('rename failed at $path');
    }
    return BFScopedPath(newDF.uri.toString());
  }

  @override
  bool hasStreamSupport() {
    return true;
  }

  @override
  Future<Stream<List<int>>> readFileStream(BFPath path) async {
    return _plugin.readFile(path.scopedSafUri());
  }

  @override
  Future<BFOutStream> writeFileStream(BFPath dir, String unsafeName,
      {BFNameUpdaterFunc? nameUpdater}) async {
    final safeName = await ZBFInternal.nextAvailableFileName(this, dir,
        unsafeName, false, nameUpdater ?? ZBFInternal.defaultFileNameUpdater);
    final res = await _plugin.startWriteStream(
        dir.scopedSafUri(), safeName, _getMime(safeName));
    return BFSafOutStream(
        res.session, _plugin, BFScopedPath(res.uri.toString()));
  }

  String _getMime(String fileName) {
    return lookupMimeType(fileName) ?? 'application/octet-stream';
  }

  @override
  Future<BFPath> pasteLocalFile(String localSrc, BFPath dir, String unsafeName,
      {BFNameUpdaterFunc? nameUpdater}) async {
    final safeName = await ZBFInternal.nextAvailableFileName(this, dir,
        unsafeName, false, nameUpdater ?? ZBFInternal.defaultFileNameUpdater);

    final res = await _plugin.writeFileFromLocal(
        localSrc, dir.scopedSafUri(), safeName, _getMime(safeName));
    return BFScopedPath(res.toString());
  }

  @override
  Future<void> copyToLocalFile(BFPath src, String dest) async {
    await _plugin.readFileToLocal(src.scopedSafUri(), dest);
  }

  BFEntity? _fromSAFEntity(saf.DocumentFile e,
      {required List<String>? dirRelPath}) {
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

  BFSafOutStream(this._session, this._plugin, this._path);

  @override
  BFPath getPath() {
    return _path;
  }

  @override
  Future<void> write(Uint8List data) async {
    await _plugin.writeChunk(_session, data);
  }

  @override
  Future<void> close() async {
    await _plugin.endWriteStream(_session);
  }

  @override
  Future<void> flush() async {}
}
