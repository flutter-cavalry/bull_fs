import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:path/path.dart' as p;

import 'bf_env.dart';
import 'types.dart';

const _maxNameAttempts = 200;

class ZBFInternal {
  static Future<String> nextAvailableFileName(BFEnv env, BFPath dir,
      String unsafeFileName, bool isDir, BFNameUpdaterFunc nameUpdater) async {
    // First attempt.
    if (await env.stat(dir, extendedPath: [unsafeFileName].lock) == null) {
      return unsafeFileName;
    }

    for (var i = 1; i <= _maxNameAttempts; i++) {
      final newName = nameUpdater(unsafeFileName, isDir, i);
      if (await env.stat(dir, extendedPath: [newName].lock) == null) {
        return newName;
      }
    }
    throw BFTooManyDuplicateFilenamesExp();
  }

  static Future<BFEntity> mustGetStat(
      BFEnv env, BFPath root, IList<String> relPath) async {
    final stat = await env.stat(root, extendedPath: relPath);
    if (stat == null) {
      throw Exception('${relPath.join('/')} is not found in $root');
    }
    return stat;
  }

  static String defaultFileNameUpdater(
      String fileName, bool isDir, int attempt) {
    if (isDir) {
      return '$fileName ($attempt)';
    }
    final basename = p.basenameWithoutExtension(fileName);
    final ext = p.extension(fileName);
    return '$basename ($attempt)$ext';
  }
}
