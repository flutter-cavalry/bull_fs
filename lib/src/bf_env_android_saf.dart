import 'package:bull_fs/bull_fs.dart';
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

  Future<void> listDirectChildren(BFPath path, List<BFEntity> collector) async {
    final objs = await saf.listFiles2(path.scopedSafUri());
    if (objs != null) {
      collector
          .addAll(objs.map((e) => _fromSAFEntity(e)).whereType<BFEntity>());
    }
  }

  Future<void> listRecursiveChildren(
      BFPath path, List<BFEntity> collector) async {
    final List<BFEntity> firstLevel = [];
    await listDirectChildren(path, firstLevel);

    collector.addAll(firstLevel);
    final subDirs = firstLevel.where((e) => e.isDir);
    await Future.wait(
        subDirs.map((e) => listRecursiveChildren(e.path, collector)));
  }

  @override
  Future<List<BFEntity>> listDir(BFPath path, {bool? recursive}) async {
    final res = <BFEntity>[];
    if (recursive == true) {
      await listRecursiveChildren(path, res);
    } else {
      await listDirectChildren(path, res);
    }
    return res;
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
      BFPath root, IList<String> src, IList<String> destDir, bool isDir) async {
    final srcStat = await ZBFInternal.mustGetStat(this, root, src);
    final srcParentStat =
        await ZBFInternal.mustGetStat(this, root, src.parentDir());
    final destDirStat = await ZBFInternal.mustGetStat(this, root, destDir);
    if (!destDirStat.isDir) {
      throw Exception('$destDir is not a directory');
    }

    // TODO: SAF move not working.
    // Ideally, SAF move can handle conflicts automatically, but it doesn't work.
    // return _safMove(srcStat.path, srcParentStat.path, destDirStat.path);

    // Src and dest have different file names.
    // Since SAF doesn't allow renaming a file while moving. We first rename src file to a random name.
    // Then move the file to dest and rename it back to the desired name.
    BFPath? srcTmpUri;
    try {
      final srcTmpName = tmpFileName() + (isDir ? '' : p.extension(src.last));
      srcTmpUri = await rename(srcStat.path, srcTmpName, isDir);

      final unsafeDestName = src.last;
      final safeDestName = await ZBFInternal.nonSAFNextAvailableFileName(
          this, destDirStat.path, unsafeDestName, isDir);
      var destUri =
          await _safMove(srcTmpUri, srcParentStat.path, destDirStat.path);

      // Rename it back to desired name.
      destUri = await rename(destUri, safeDestName, isDir);
      return destUri;
    } catch (err) {
      // Try reverting changes if exception happened.
      if (srcTmpUri != null && await stat(srcTmpUri) != null) {
        try {
          await rename(srcTmpUri, src.last, isDir);
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
    return _fromSAFEntity(df);
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
  Future<BFPath> rename(BFPath path, String newName, bool isDir) async {
    final newDF = await saf.renameTo(path.scopedSafUri(), newName);
    if (newDF == null) {
      throw Exception('Renaming failed at $path');
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
  Future<BFOutStream> writeFileStream(BFPath dir, String unsafeName) async {
    final res = await _plugin.startWriteStream(
        dir.scopedSafUri(), unsafeName, _getMime(unsafeName));
    return BFSafOutStream(
        res.session, _plugin, BFScopedPath(res.uri.toString()));
  }

  String _getMime(String fileName) {
    return lookupMimeType(fileName) ?? 'application/octet-stream';
  }

  @override
  Future<BFPath> pasteLocalFile(
      String localSrc, BFPath dir, String unsafeName) async {
    final res = await _plugin.writeFileFromLocal(
        localSrc, dir.scopedSafUri(), unsafeName, _getMime(unsafeName));
    return BFScopedPath(res.toString());
  }

  @override
  Future<void> copyToLocalFile(BFPath src, String dest) async {
    await _plugin.readFileToLocal(src.scopedSafUri(), dest);
  }

  BFEntity? _fromSAFEntity(saf.DocumentFile e) {
    final eName = e.name;
    if (eName == null) {
      return null;
    }
    return BFEntity(BFScopedPath(e.uri.toString()), eName,
        e.isDirectory ?? false, e.size ?? 0, e.lastModified, false);
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
