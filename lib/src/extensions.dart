import 'dart:io';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'bf_env.dart';
import 'types.dart';
import 'package:path/path.dart' as p;

extension IListStringExtension on IList<String> {
  IList<String> parentDir() {
    if (length == 0) {
      throw Exception('Cannot get parent dir of a root dir');
    }
    if (length == 1) {
      return IList<String>();
    }
    return take(length - 1).toIList();
  }
}

extension BFEnvExtension on BFEnv {
  Future<BFPath?> statPath(BFPath path, {IList<String>? relPath}) async {
    final res = await stat(path, relPath: relPath);
    return res?.path;
  }

  Future<BFPath?> child(BFPath path, {IList<String>? relPath}) async {
    final st = await stat(path, relPath: relPath);
    if (st == null) {
      return null;
    }
    return st.path;
  }

  Future<void> deletePathIfExists(BFPath path, {IList<String>? relPath}) async {
    final st = await stat(path, relPath: relPath);
    if (st == null) {
      return;
    }
    await delete(st.path, st.isDir);
  }

  Future<BFPath> ensureDirsForFile(
      BFPath dir, IList<String> relFilePath) async {
    if (relFilePath.length == 1) {
      return dir;
    }
    return ensureDirsForFile(
        dir, relFilePath.take(relFilePath.length - 1).toIList());
  }

  Future<void> _listRecursiveFat(BFPath path, IList<String> dirRelPath,
      List<BFFatEntity> collector) async {
    final directChildren = await listDir(path);
    for (final child in directChildren) {
      if (child.isDir) {
        await _listRecursiveFat(
            child.path, [...dirRelPath, child.name].lock, collector);
      } else {
        collector.add(BFFatEntity(child, dirRelPath));
      }
    }
  }

  // Compared to `listDir`, it returns a list of `BFFatEntity` which contains
  // the dir rel path.
  Future<List<BFFatEntity>> listDirFat(BFPath path, IList<String>? dirRelPath) {
    final List<BFFatEntity> result = [];
    return _listRecursiveFat(path, dirRelPath ?? <String>[].lock, result)
        .then((_) => result);
  }

  Future<BFEntity?> fileExists(BFPath path, {IList<String>? relPath}) async {
    final st = await stat(path, relPath: relPath);
    if (st == null) {
      return null;
    }
    if (st.isDir) {
      return null;
    }
    return st;
  }

  Future<BFEntity?> directoryExists(BFPath path,
      {IList<String>? relPath}) async {
    final st = await stat(path, relPath: relPath);
    if (st == null) {
      return null;
    }
    if (!st.isDir) {
      return null;
    }
    return st;
  }

  Future<Uint8List> internalReadFileBytes(BFPath file) async {
    if (hasStreamSupport()) {
      final List<int> result = [];
      final stream = await readFileStream(file);
      await for (var chunk in stream) {
        result.addAll(chunk);
      }
      return Uint8List.fromList(result);
    }
    final tmp = await _tmpFile();
    await copyToLocalFile(file, tmp);
    return File(tmp).readAsBytes();
  }

  Future<Map<String, dynamic>> directoryToMap(BFPath dir,
      {bool Function(String name, BFEntity entity)? filter,
      bool? hideFileContents}) async {
    final Map<String, dynamic> map = <String, dynamic>{};
    await _directoryToMapInternal(map, dir, hideFileContents ?? false, filter);
    return map;
  }

  Future<void> _directoryToMapInternal(
      Map<String, dynamic> map,
      BFPath dir,
      bool hideFileContents,
      bool Function(String name, BFEntity entity)? filter) async {
    final entities = await listDir(dir);
    await Future.wait(entities
        .map((e) => _entityToMapInternal(map, e, hideFileContents, filter)));
  }

  Future<void> _entityToMapInternal(
      Map<String, dynamic> map,
      BFEntity ent,
      bool hideFileContents,
      bool Function(String name, BFEntity entity)? filter) async {
    final name = ent.name;
    if (filter != null && !filter(name, ent)) {
      return;
    }
    if (ent.isDir) {
      map[name] = await directoryToMap(ent.path,
          filter: filter, hideFileContents: hideFileContents);
    } else {
      if (hideFileContents) {
        map[name] = null;
      } else {
        final bytes = await internalReadFileBytes(ent.path);
        map[name] = hex.encode(bytes);
      }
    }
  }

  Future<String> _tmpFile() async {
    final dir = await Directory.systemTemp.createTemp('bf_');
    return p.join(dir.path, DateTime.now().millisecondsSinceEpoch.toString());
  }
}
