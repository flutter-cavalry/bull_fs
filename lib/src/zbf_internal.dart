import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:path/path.dart' as p;

import 'bf_env.dart';
import 'types.dart';

const _maxNameAttempts = 200;

final _defNameUpdaterNoReg = BFDefaultNameUpdater(null);

class BFDefaultNameUpdater extends BFNameUpdater {
  final BFNameUpdaterFunc? updateFn;

  BFDefaultNameUpdater(super.nameRegistry, {this.updateFn});

  @override
  String updateName(String fileName, bool isDir, int attempt) {
    if (updateFn != null) {
      return updateFn!(fileName, isDir, attempt);
    }
    if (isDir) {
      return '$fileName ($attempt)';
    }
    final basename = p.basenameWithoutExtension(fileName);
    final ext = p.extension(fileName);
    return '$basename ($attempt)$ext';
  }

  static BFDefaultNameUpdater get noRegistry => _defNameUpdaterNoReg;
}

class ZBFInternal {
  static Future<String> nextAvailableFileName(
    BFEnv env,
    BFPath dir,
    String unsafeFileName,
    bool isDir,
    BFNameUpdater nameUpdater,
  ) async {
    // First attempt.
    if (await _checkNameAvailable(
      env,
      dir,
      unsafeFileName,
      nameUpdater.nameRegistry,
    )) {
      return unsafeFileName;
    }

    for (var i = 1; i <= _maxNameAttempts; i++) {
      final newName = nameUpdater.updateName(unsafeFileName, isDir, i);
      if (await _checkNameAvailable(
        env,
        dir,
        newName,
        nameUpdater.nameRegistry,
      )) {
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
}

Future<bool> _checkNameAvailable(
  BFEnv env,
  BFPath dir,
  String fileName,
  Set<String>? nameRegistry,
) async {
  if (nameRegistry?.contains(fileName) == true) {
    // Already registered, so it is not available.
    return false;
  }
  final stat = await env.child(dir, [fileName].lock);
  return stat == null;
}
