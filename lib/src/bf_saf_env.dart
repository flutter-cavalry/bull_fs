import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';
import 'package:saf_util/saf_util_platform_interface.dart';
import 'package:tmp_path/tmp_path.dart';

import '../bull_fs.dart';

/// A [BFEnv] implementation for Android Storage Access Framework (SAF).
class BFSafEnv extends BFEnv {
  static final BFSafEnv instance = BFSafEnv();

  final _streamPlugin = SafStream();
  final _utilPlugin = SafUtil();

  @override
  BFEnvType envType() {
    return BFEnvType.saf;
  }

  @override
  bool isScoped() {
    return true;
  }

  Future<void> _listDirectChildren(
    BFPath path,
    List<BFEntity> collector,
    List<String>? dirRelPath,
  ) async {
    final objs = await _utilPlugin.list(path.scopedUri());
    collector.addAll(
      objs
          .map((e) => _fromSAFEntity(e, dirRelPath: dirRelPath?.lock))
          .whereType<BFEntity>(),
    );
  }

  Future<void> _listRecursiveChildren(
    BFPath path,
    List<BFEntity> collector,
    List<String>? dirRelPath,
  ) async {
    final List<BFEntity> firstLevel = [];
    await _listDirectChildren(path, firstLevel, dirRelPath);

    collector.addAll(firstLevel);
    final subDirs = firstLevel.where((e) => e.isDir);
    await Future.wait(
      subDirs.map(
        (e) => _listRecursiveChildren(
          e.path,
          collector,
          dirRelPath == null ? null : [...dirRelPath, e.name],
        ),
      ),
    );
  }

  @override
  Future<List<BFEntity>> listDir(
    BFPath path, {
    bool? recursive,
    bool? relativePathInfo,
  }) async {
    final res = <BFEntity>[];
    if (recursive == true) {
      await _listRecursiveChildren(
        path,
        res,
        relativePathInfo == true ? [] : null,
      );
    } else {
      await _listDirectChildren(path, res, null);
    }
    return res;
  }

  @override
  Future<List<BFPathAndDirRelPath>> listDirContentFiles(BFPath path) async {
    final entities = await listDir(
      path,
      recursive: true,
      relativePathInfo: true,
    );
    return entities
        .where((e) => !e.isDir)
        .map((e) => BFPathAndDirRelPath(e.path, e.dirRelPath))
        .toList();
  }

  @override
  Future<void> delete(BFPath path, bool isDir) async {
    await _utilPlugin.delete(path.scopedUri(), isDir);
  }

  @override
  Future<BFEntity?> stat(BFPath path, bool? isDir) async {
    final df = await _utilPlugin.stat(path.scopedUri(), isDir);
    if (df == null) {
      return null;
    }
    return _fromSAFEntity(df, dirRelPath: null);
  }

  @override
  Future<BFEntity?> child(BFPath path, IList<String> names) async {
    final df = await _utilPlugin.child(path.scopedUri(), names.unlock);
    if (df == null) {
      return null;
    }
    return _fromSAFEntity(df, dirRelPath: null);
  }

  Future<UpdatedBFPath> _safMove(
    BFPath srcPath,
    bool isDir,
    BFPath srcDir,
    BFPath destDir,
  ) async {
    final df = await _utilPlugin.moveTo(
      srcPath.scopedUri(),
      isDir,
      srcDir.scopedUri(),
      destDir.scopedUri(),
    );
    return UpdatedBFPath(BFScopedPath(df.uri.toString()), df.name);
  }

  @override
  Future<UpdatedBFPath> moveToDirSafe(
    BFPath src,
    bool isDir,
    BFPath srcDir,
    BFPath destDir, {
    BFNameUpdater? nameUpdater,
  }) async {
    // Since SAF doesn't allow renaming a file while moving. We first rename src file to a random name.
    // Then move the file to dest and rename it back to the desired name.
    BFPath? srcTmpUri;
    final srcName = await findBasename(src, isDir);
    if (srcName == null) {
      throw Exception('Unexpected null basename from item stat');
    }
    final srcTmpName = tmpFileName() + (isDir ? '' : p.extension(srcName));
    try {
      srcTmpUri = await rename(src, isDir, srcDir, srcTmpName);

      final unsafeDestName = srcName;
      final safeDestName = await ZBFInternal.nextAvailableFileName(
        this,
        destDir,
        unsafeDestName,
        isDir,
        nameUpdater ?? bfDefaultNameUpdater,
      );

      final tmpDestInfo = await _safMove(srcTmpUri, isDir, srcDir, destDir);

      // Rename it back to desired name.
      final destUri = await rename(
        tmpDestInfo.path,
        isDir,
        destDir,
        safeDestName,
      );
      return UpdatedBFPath(destUri, safeDestName);
    } catch (err) {
      // Try reverting changes if exception happened.
      if (srcTmpUri != null && await child(srcDir, [srcTmpName].lock) != null) {
        try {
          await rename(srcTmpUri, isDir, srcDir, srcName);
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

  @override
  Future<BFPath> mkdirp(BFPath dir, IList<String> components) async {
    final uriInfo = await _utilPlugin.mkdirp(
      dir.scopedUri(),
      components.unlock,
    );
    return BFScopedPath(uriInfo.uri);
  }

  @override
  Future<BFPath> renameInternal(BFPath path, bool isDir, String newName) async {
    final uriInfo = await _utilPlugin.rename(path.scopedUri(), isDir, newName);
    return BFScopedPath(uriInfo.uri.toString());
  }

  @override
  Future<Stream<List<int>>> readFileStream(
    BFPath path, {
    int? bufferSize,
    int? start,
  }) async {
    return _streamPlugin.readFileStream(
      path.scopedUri(),
      bufferSize: bufferSize,
      start: start,
    );
  }

  @override
  Future<BFOutStream> writeFileStream(
    BFPath dir,
    String unsafeName, {
    BFNameUpdater? nameUpdater,
    bool? overwrite,
  }) async {
    final safeName = overwrite == true
        ? unsafeName
        : await ZBFInternal.nextAvailableFileName(
            this,
            dir,
            unsafeName,
            false,
            nameUpdater ?? bfDefaultNameUpdater,
          );
    final res = await _streamPlugin.startWriteStream(
      dir.scopedUri(),
      safeName,
      _getMime(safeName),
      overwrite: overwrite,
    );
    final newFileName = res.fileResult.fileName;
    if (newFileName == null || newFileName.isEmpty) {
      throw Exception('Unexpected null fileName from writeFileStream');
    }
    return BFSafOutStream(
      res.session,
      _streamPlugin,
      BFScopedPath(res.fileResult.uri.toString()),
      newFileName,
    );
  }

  @override
  Future<UpdatedBFPath> writeFileBytes(
    BFPath dir,
    String unsafeName,
    Uint8List bytes, {
    BFNameUpdater? nameUpdater,
    bool? overwrite,
  }) async {
    final safeName = overwrite == true
        ? unsafeName
        : await ZBFInternal.nextAvailableFileName(
            this,
            dir,
            unsafeName,
            false,
            nameUpdater ?? bfDefaultNameUpdater,
          );
    final res = await _streamPlugin.writeFileBytes(
      dir.scopedUri(),
      safeName,
      _getMime(safeName),
      bytes,
      overwrite: overwrite,
    );
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
    String localSrc,
    BFPath dir,
    String unsafeName, {
    BFNameUpdater? nameUpdater,
    bool? overwrite,
  }) async {
    final safeName = overwrite == true
        ? unsafeName
        : await ZBFInternal.nextAvailableFileName(
            this,
            dir,
            unsafeName,
            false,
            nameUpdater ?? bfDefaultNameUpdater,
          );
    final res = await _streamPlugin.pasteLocalFile(
      localSrc,
      dir.scopedUri(),
      safeName,
      _getMime(safeName),
      overwrite: overwrite,
    );
    final fileName = res.fileName;
    if (fileName == null || fileName.isEmpty) {
      throw Exception('Unexpected null fileName from writeFileFromLocal');
    }
    return UpdatedBFPath(BFScopedPath(res.uri.toString()), fileName);
  }

  @override
  Future<void> copyToLocalFile(BFPath src, String dest) async {
    await _streamPlugin.copyToLocalFile(src.scopedUri(), dest);
  }

  @override
  Future<Uint8List> readFileBytes(BFPath path, {int? start, int? count}) async {
    return _streamPlugin.readFileBytes(
      path.scopedUri(),
      start: start,
      count: count,
    );
  }

  @override
  Future<BFPath?> fileExists(BFPath path, IList<String>? extendedPath) async {
    return _itemExists(path, false, extendedPath);
  }

  @override
  Future<BFPath?> directoryExists(
    BFPath path,
    IList<String>? extendedPath,
  ) async {
    return _itemExists(path, true, extendedPath);
  }

  Future<BFPath?> _itemExists(
    BFPath path,
    bool isDir,
    IList<String>? extendedPath,
  ) async {
    if (extendedPath == null || extendedPath.isEmpty) {
      final res = await _utilPlugin.documentFileFromUri(
        path.scopedUri(),
        isDir,
      );
      if (res == null) {
        return null;
      }
      return BFScopedPath(res.uri.toString());
    }
    final st = await child(path, extendedPath);
    if (st == null) {
      return null;
    }
    if (st.isDir != isDir) {
      return null;
    }
    return st.path;
  }

  @override
  Future<String?> findBasename(BFPath path, bool isDir) async {
    final st = await stat(path, isDir);
    if (st == null) {
      return null;
    }
    return st.name;
  }

  BFEntity? _fromSAFEntity(
    SafDocumentFile e, {
    required IList<String>? dirRelPath,
  }) {
    final eName = e.name;
    return BFEntity(
      BFScopedPath(e.uri.toString()),
      eName,
      e.isDir,
      e.length,
      e.lastModified == 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(e.lastModified),
      false,
      dirRelPath: dirRelPath,
    );
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
