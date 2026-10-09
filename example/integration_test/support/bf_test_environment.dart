import 'dart:io';

import 'package:bull_fs/bull_fs.dart';
import 'package:fast_file_picker/fast_file_picker.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:path/path.dart' as p;

abstract class BFTestTarget {
  const BFTestTarget();

  String get name;
  bool get supportsInjectedMoveFailure => false;
  Future<BFTestEnvironment> open();
}

class BFLocalTestTarget extends BFTestTarget {
  const BFLocalTestTarget();

  @override
  String get name => 'BFLocalEnv';

  @override
  bool get supportsInjectedMoveFailure => true;

  @override
  Future<BFTestEnvironment> open() async {
    final directory = await Directory.systemTemp.createTemp('bull_fs_tests_');
    return BFTestEnvironment(
      BFLocalEnv(),
      BFLocalPath(directory.path),
      directory,
      () async {},
    );
  }
}

class BFPlatformTestTarget extends BFTestTarget {
  const BFPlatformTestTarget();

  static bool get isSupported =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  @override
  String get name => Platform.isAndroid ? 'BFSafEnv' : 'BFNsfcEnv';

  @override
  Future<BFTestEnvironment> open() async {
    if (!isSupported) {
      throw UnsupportedError('Platform tests require Android, iOS, or macOS');
    }
    final selection = await FastFilePicker.pickFolder(writePermission: true);
    if (selection == null) {
      throw StateError('A writable folder must be selected for platform tests');
    }
    try {
      final directory = await BFEnvUtil.envFromDirectory(
        path: selection.path,
        uri: selection.uri,
        macosIcloud: true,
      );
      final scratch = await Directory.systemTemp.createTemp('bull_fs_scratch_');
      return BFTestEnvironment(
        directory.env,
        directory.path,
        scratch,
        selection.release,
      );
    } catch (_) {
      await selection.release();
      rethrow;
    }
  }
}

class BFTestEnvironment {
  final BFEnv env;
  final BFPath _parent;
  final Directory _scratch;
  final Future<void> Function() _release;
  final String _runId = DateTime.now().microsecondsSinceEpoch.toString();
  int _testCount = 0;
  int _fileCount = 0;

  BFTestEnvironment(this.env, this._parent, this._scratch, this._release);

  Future<BFPath> createTestRoot() =>
      env.mkdirp(_parent, ['bull_fs_test_${_runId}_${++_testCount}'].lock);

  String temporaryFilePath() => p.join(_scratch.path, 'file_${++_fileCount}');

  Future<void> deleteTestRoot(BFPath root) => env.delete(root, true);

  Future<void> dispose() async {
    try {
      await _scratch.delete(recursive: true);
    } finally {
      await _release();
    }
  }
}
