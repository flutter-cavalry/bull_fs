import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import 'bf_env.dart';
import 'types.dart';

class BFNameFinder {
  Future<String> findFileName(
    BFEnv env,
    BFPath dir,
    String unsafeName,
    bool isDir, {
    Set<String>? pendingNames,
  }) async {
    // First attempt.
    if (await _checkNameAvailable(
      env,
      dir,
      unsafeName,
      pendingNames,
    )) {
      return unsafeName;
    }

    for (int i = 0; i < 100; i++) {
      final name = formatFileName(unsafeName, isDir, i + 1);
      if (await _checkNameAvailable(
        env,
        dir,
        name,
        pendingNames,
      )) {
        pendingNames?.add(name);
        return name;
      }
    }
    throw BFNoAvailableNameException();
  }

  @protected
  String formatFileName(String name, bool isDir, int attempt) {
    if (isDir) {
      return '$name ($attempt)';
    }
    final basename = p.basenameWithoutExtension(name);
    final ext = p.extension(name);
    return '$basename ($attempt)$ext';
  }

  static BFNameFinder get instance => _instance;
  static final BFNameFinder _instance = BFNameFinder();
}

class BFCustomNameFinder extends BFNameFinder {
  final String Function(String name, bool isDir, int count) _updateFn;

  BFCustomNameFinder(this._updateFn);

  @override
  String formatFileName(String name, bool isDir, int attempt) {
    return _updateFn(name, isDir, attempt);
  }
}

Future<bool> _checkNameAvailable(
  BFEnv env,
  BFPath dir,
  String fileName,
  Set<String>? pendingNames,
) async {
  if (pendingNames?.contains(fileName) == true) {
    // Already registered, so it is not available.
    return false;
  }
  final stat = await env.child(dir, [fileName].lock);
  return stat == null;
}
