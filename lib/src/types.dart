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

/// Used in move functions.
class BFPathAndName {
  final BFPath path;
  final String name;
  BFPathAndName(this.path, this.name);
}

class BFEntity {
  final BFPath path;
  final String name;
  final bool isDir;
  late final int length;
  final DateTime? lastMod;
  final bool notDownloaded;

  BFEntity(this.path, this.name, this.isDir, int length, this.lastMod,
      this.notDownloaded) {
    if (isDir) {
      this.length = -1;
    } else {
      this.length = length;
    }
  }

  @override
  String toString() {
    var res = isDir ? 'D' : 'F';
    res += '|$name';
    if (!isDir) {
      res += '|${length > 0 ? '+' : '0'}';
    }
    return res;
  }

  // Used by BF tests.
  String toString2() {
    var res = isDir ? 'D' : 'F';
    res += '|$name';
    if (!isDir) {
      res += '|$length';
    }
    return '[$res]';
  }

  static Future<BFEntity> fromLocalEntity(FileSystemEntity entity) async {
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
        length, lastMod, false);
  }

  static Future<BFEntity?> fromLocalEntityNE(FileSystemEntity entity) async {
    try {
      return await fromLocalEntity(entity);
    } catch (_) {
      return null;
    }
  }
}

// BFEntity + dir rel path.
class BFFatEntity {
  final IList<String> dirRelPath;
  final BFEntity entity;

  BFFatEntity(this.entity, this.dirRelPath);

  @override
  String toString() {
    var res = entity.isDir ? 'D' : 'F';
    res += '|${p.posix.joinAll([...dirRelPath, entity.name])}';
    if (!entity.isDir) {
      res += '|${entity.length > 0 ? '+' : '0'}';
    }
    return res;
  }

  // Used to BF tests.
  String toString2() {
    var res = entity.isDir ? 'D' : 'F';
    res += '|${p.posix.joinAll([...dirRelPath, entity.name])}';
    if (!entity.isDir) {
      res += '|${entity.length}';
    }
    return '[$res]';
  }
}

abstract class BFOutStream {
  BFPath getPath();
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
  final _bb = BytesBuilder(copy: false);

  @override
  BFPath getPath() {
    throw Exception('`getPath` is not supported in `MemoryBFOutStream`');
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
