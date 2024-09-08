import 'dart:io';
import 'package:darwin_url/darwin_url.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

final DarwinUrl _darwinUrlPlugin = DarwinUrl();

class BFDuplicateItemExp implements Exception {}

class BFTooManyDuplicateFilenamesExp implements Exception {}

class BFNoPermissionExp implements Exception {}

abstract class BFPath {}

class BFLocalPath extends BFPath {
  final String path;

  BFLocalPath(this.path);

  @override
  String toString() {
    return path;
  }

  @override
  bool operator ==(Object other) {
    return other is BFLocalPath && path == other.path;
  }

  @override
  int get hashCode => path.hashCode;
}

class BFScopedPath extends BFPath {
  final String id;
  BFScopedPath(this.id);

  @override
  String toString() {
    return id.toString();
  }

  @override
  bool operator ==(Object other) {
    return other is BFScopedPath && id == other.id;
  }

  @override
  int get hashCode => id.hashCode;
}

const _pathHeadLocal = 'L';
const _pathHeadScoped = 'S';

BFPath decodeStringToBFPath(String s) {
  if (s.startsWith(_pathHeadLocal)) {
    return BFLocalPath(s.substring(1));
  }
  return BFScopedPath(s.substring(1));
}

extension BFPathExtension on BFPath {
  String localPath() {
    if (this is BFLocalPath) {
      return (this as BFLocalPath).path;
    }
    throw Exception('$this is not a local path');
  }

  String scopedID() {
    if (this is BFScopedPath) {
      return (this as BFScopedPath).id;
    }
    throw Exception('$this is not a scoped path');
  }

  Future<BFPath> iosJoinRelPath(IList<String> relPath, bool isDir) async {
    final url =
        await _darwinUrlPlugin.append(scopedID(), relPath.unlock, isDir: isDir);
    return BFScopedPath(url);
  }

  Uri scopedSafUri() {
    if (this is BFScopedPath) {
      return Uri.parse((this as BFScopedPath).id);
    }
    throw Exception('$this is not a scoped path');
  }

  BFPath localJoinRelPath(String relPath) {
    final path = p.join(localPath(), relPath);
    return BFLocalPath(path);
  }

  String encodeToString() {
    if (this is BFLocalPath) {
      return '$_pathHeadLocal${toString()}';
    }
    return '$_pathHeadScoped${toString()}';
  }
}

class BFPathAndDirRelPath {
  final BFPath path;
  final List<String> dirRelPath;

  BFPathAndDirRelPath(this.path, this.dirRelPath);

  @override
  String toString() {
    var res = path.toString();
    if (dirRelPath.isNotEmpty) {
      res += '|dir_rel: ${dirRelPath.join('/')}';
    }
    return res;
  }
}

class BFEntity {
  final BFPath path;
  final String name;
  final bool isDir;
  late final int length;
  final DateTime? lastMod;
  final bool notDownloaded;

  // Automatically set when recursively listing a directory.
  List<String> dirRelPath = [];

  BFEntity(this.path, this.name, this.isDir, int length, this.lastMod,
      this.notDownloaded,
      {List<String>? dirRelPath}) {
    if (isDir) {
      this.length = -1;
    } else {
      this.length = length;
    }
    if (dirRelPath != null) {
      this.dirRelPath = dirRelPath;
    }
  }

  @override
  String toString() {
    var res = isDir ? 'D' : 'F';
    res += '|$name';
    if (!isDir) {
      res += '|${length > 0 ? '+' : '0'}';
    }
    if (dirRelPath.isNotEmpty) {
      res += '|dir_rel: ${dirRelPath.join('/')}';
    }
    return res;
  }

  String toStringWithLength() {
    var res = isDir ? 'D' : 'F';
    res += '|$name';
    if (!isDir) {
      res += '|$length';
    }
    if (dirRelPath.isNotEmpty) {
      res += '|dir_rel: ${dirRelPath.join('/')}';
    }
    return '[$res]';
  }

  static Future<BFEntity> fromLocalEntity(FileSystemEntity entity,
      {required List<String>? dirRelPath}) async {
    int length;
    bool isDir;
    DateTime? lastMod;
    if (entity is File) {
      isDir = false;
      length = await entity.length();
      lastMod = await entity.lastModified();
    } else {
      isDir = true;
      length = 0;
    }
    return BFEntity(BFLocalPath(entity.path), p.basename(entity.path), isDir,
        length, lastMod, false,
        dirRelPath: dirRelPath);
  }

  static Future<BFEntity?> fromLocalEntityNE(FileSystemEntity entity,
      {required List<String>? dirRelPath}) async {
    try {
      return await fromLocalEntity(entity, dirRelPath: dirRelPath);
    } catch (_) {
      return null;
    }
  }
}

abstract class BFOutStream {
  BFPath getPath();
  String getFileName();
  Future<void> write(Uint8List data);
  Future<void> close();
  Future<void> flush();
}

class BFLocalOutStream extends BFOutStream {
  final IOSink _sink;
  final BFPath _path;

  BFLocalOutStream(this._sink, this._path);

  @override
  BFPath getPath() {
    return _path;
  }

  @override
  String getFileName() {
    return p.basename(_path.localPath());
  }

  @override
  Future<void> write(Uint8List data) async {
    _sink.add(data);
  }

  @override
  Future<void> close() async {
    await _sink.close();
  }

  @override
  Future<void> flush() async {
    await _sink.flush();
  }
}

class BFMemoryOutStream extends BFOutStream {
  // ignore: deprecated_export_use
  final _bb = BytesBuilder(copy: false);

  @override
  BFPath getPath() {
    throw Exception('`getPath` is not supported in `MemoryBFOutStream`');
  }

  @override
  String getFileName() {
    throw Exception('`getFileName` is not supported in `MemoryBFOutStream`');
  }

  @override
  Future<void> write(Uint8List data) async {
    _bb.add(data);
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> flush() async {}

  Uint8List toBytes() {
    return _bb.toBytes();
  }
}

class UpdatedBFPath {
  final BFPath path;
  final String newName;

  UpdatedBFPath(this.path, this.newName);

  @override
  String toString() {
    return '$path|$newName';
  }
}
