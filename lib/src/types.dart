import 'dart:io';
import 'package:darwin_url/darwin_url.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

final DarwinUrl _darwinUrlPlugin = DarwinUrl();

class BFDuplicateItemExp implements Exception {}

class BFTooManyDuplicateFilenamesExp implements Exception {}

class BFNoPermissionExp implements Exception {}

/// Abstract class for all file system paths.
abstract class BFPath {}

/// Local file system path.
class BFLocalPath extends BFPath {
  /// Local file system path string.
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

/// Scoped file system path. Used in [BFNsfcEnv] and [BFSfsEnv].
class BFScopedPath extends BFPath {
  /// Scoped ID.
  /// In [BFNsfcEnv], it is the Apple file system URL.
  /// In [BFSfsEnv], it is the Android file system URI.
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

/// Decodes a string to a [BFPath].
BFPath decodeStringToBFPath(String s) {
  if (s.startsWith(_pathHeadLocal)) {
    return BFLocalPath(s.substring(1));
  }
  return BFScopedPath(s.substring(1));
}

extension BFPathExtension on BFPath {
  /// Returns the local path if it is a [BFLocalPath]. Otherwise, throws an exception.
  String localPath() {
    if (this is BFLocalPath) {
      return (this as BFLocalPath).path;
    }
    throw Exception('$this is not a local path');
  }

  /// Returns the scoped ID if it is a [BFScopedPath]. Otherwise, throws an exception.
  String scopedID() {
    if (this is BFScopedPath) {
      return (this as BFScopedPath).id;
    }
    throw Exception('$this is not a scoped path');
  }

  /// Only for Apple platforms. Joins a relative path to the scoped path.
  Future<BFPath> iosJoinRelPath(IList<String> relPath, bool isDir) async {
    final url =
        await _darwinUrlPlugin.append(scopedID(), relPath.unlock, isDir: isDir);
    return BFScopedPath(url);
  }

  /// Only for local paths. Joins a relative path to the local path.
  BFPath localJoinRelPath(String relPath) {
    final path = p.join(localPath(), relPath);
    return BFLocalPath(path);
  }

  /// Encodes the path to a string.
  String encodeToString() {
    if (this is BFLocalPath) {
      return '$_pathHeadLocal${toString()}';
    }
    return '$_pathHeadScoped${toString()}';
  }
}

// Stores a path and its relative path in a directory.
class BFPathAndDirRelPath {
  /// The path.
  final BFPath path;

  /// The relative path in a directory.
  final IList<String> dirRelPath;

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

/// Represents a file or directory entity.
class BFEntity {
  /// The path of the entity.
  final BFPath path;

  /// The name of the entity.
  final String name;

  /// Whether the entity is a directory.
  final bool isDir;

  /// The length of the entity. If it is a directory, the length is -1.
  late final int length;

  /// The last modified time of the entity.
  final DateTime? lastMod;

  /// Whether the entity is not available locally. (For example, not downloaded from iCloud).
  final bool notDownloaded;

  /// The relative path in a directory.
  /// Automatically set when recursively listing a directory.
  IList<String> dirRelPath = <String>[].lock;

  BFEntity(this.path, this.name, this.isDir, int length, this.lastMod,
      this.notDownloaded,
      {IList<String>? dirRelPath}) {
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
      {required IList<String>? dirRelPath}) async {
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
      {required IList<String>? dirRelPath}) async {
    try {
      return await fromLocalEntity(entity, dirRelPath: dirRelPath);
    } catch (_) {
      return null;
    }
  }
}

/// Abstract class for file system out streams.
abstract class BFOutStream {
  /// Returns the [BFPath] of the stream.
  BFPath getPath();

  /// Returns the file name of the stream.
  String getFileName();

  /// Writes data to the stream.
  Future<void> write(Uint8List data);

  /// Closes the stream.
  Future<void> close();

  /// Flushes the stream.
  Future<void> flush();
}

/// Local file system out stream.
class BFLocalRafOutStream extends BFOutStream {
  final RandomAccessFile _raf;
  final BFPath _path;
  bool _closed = false;

  BFLocalRafOutStream(this._raf, this._path);

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
    await _raf.writeFrom(data);
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    await _raf.close();
    _closed = true;
  }

  @override
  Future<void> flush() async {
    await _raf.flush();
  }
}

/// In-memory out stream.
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

/// Represents a path that has been updated.
class UpdatedBFPath {
  /// The updated path.
  final BFPath path;

  /// The file name of the updated path.
  final String newName;

  UpdatedBFPath(this.path, this.newName);

  @override
  String toString() {
    return '$path|$newName';
  }
}
