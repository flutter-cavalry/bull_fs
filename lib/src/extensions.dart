import 'package:convert/convert.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'bf_env.dart';
import 'types.dart';

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
      final dirStat = await stat(dir);
      if (dirStat == null) {
        throw Exception('Parent dir does not exist: $dir');
      }
      return dir;
    }
    return mkdirp(dir, relFilePath.take(relFilePath.length - 1).toIList());
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
        final bytes = await readFileSync(ent.path);
        map[name] = hex.encode(bytes);
      }
    }
  }
}
