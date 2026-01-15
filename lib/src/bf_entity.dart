import 'dart:io';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:path/path.dart' as p;

import 'types.dart';

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

  BFEntity(
    this.path,
    this.name,
    this.isDir,
    int length,
    this.lastMod,
    this.notDownloaded, {
    IList<String>? dirRelPath,
  }) {
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

  static Future<BFEntity> fromLocalEntity(
    FileSystemEntity entity, {
    required IList<String>? dirRelPath,
    bool? skipLastMod,
  }) async {
    int length;
    bool isDir;
    DateTime? lastMod;
    if (entity is File) {
      isDir = false;
      length = await entity.length();
      if (!(skipLastMod ?? false)) {
        lastMod = await entity.lastModified();
      }
    } else {
      isDir = true;
      length = 0;
    }
    return BFEntity(
      BFLocalPath(entity.path),
      p.basename(entity.path),
      isDir,
      length,
      lastMod,
      false,
      dirRelPath: dirRelPath,
    );
  }

  static Future<BFEntity?> fromLocalEntityNE(
    FileSystemEntity entity, {
    required IList<String>? dirRelPath,
    bool? skipLastMod,
  }) async {
    try {
      return await fromLocalEntity(
        entity,
        dirRelPath: dirRelPath,
        skipLastMod: skipLastMod,
      );
    } catch (_) {
      return null;
    }
  }
}
