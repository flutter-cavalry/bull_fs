import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:path/path.dart' as p;

import 'bf_env.dart';
import 'types.dart';

const _maxNameAttempts = 200;

class ZBFInternal {
  static Future<String> nextAvailableFileName(
    BFEnv env,
    BFPath dir,
    String unsafeFileName,
    bool isDir,
    BFNameUpdaterFunc nameUpdater, {

    /// Optional registry to save generated file names.
    Set<String>? registry,
  }) async {
    // First attempt.
    if (await _checkNameAvailable(env, dir, unsafeFileName, registry)) {
      return unsafeFileName;
    }

    for (var i = 1; i <= _maxNameAttempts; i++) {
      final newName = nameUpdater(unsafeFileName, isDir, i);
      if (await _checkNameAvailable(env, dir, newName, registry)) {
        return newName;
      }
    }
    throw BFTooManyDuplicateFilenamesExp();
  }

  static Future<BFEntity> mustGetStat(
    BFEnv env,
    BFPath root,
    IList<String> relPath,
  ) async {
    final stat = await env.child(root, relPath);
    if (stat == null) {
      throw Exception('${relPath.join('/')} is not found in $root');
    }
    return stat;
  }

  static String defaultFileNameUpdater(
    String fileName,
    bool isDir,
    int attempt,
  ) {
    if (isDir) {
      return '$fileName ($attempt)';
    }
    final basename = p.basenameWithoutExtension(fileName);
    final ext = p.extension(fileName);
    return '$basename ($attempt)$ext';
  }
}

Future<bool> _checkNameAvailable(
  BFEnv env,
  BFPath dir,
  String fileName,
  Set<String>? registry,
) async {
  if (registry?.contains(fileName) == true) {
    // Already registered, so it is not available.
    return false;
  }
  final stat = await env.child(dir, [fileName].lock);
  return stat == null;
}
