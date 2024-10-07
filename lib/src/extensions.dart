import 'package:convert/convert.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'bf_env.dart';
import 'types.dart';

extension BFEnvExtension on BFEnv {
  /// Deletes a path if it exists.
  Future<void> deletePathIfExists(
      BFPath path, bool isDir, IList<String>? extendedPath) async {
    final finalPath = isDir
        ? await directoryExists(path, extendedPath)
        : await fileExists(path, extendedPath);
    if (finalPath == null) {
      return;
    }
    await delete(finalPath, isDir);
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
