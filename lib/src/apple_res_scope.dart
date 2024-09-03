import 'package:accessing_security_scoped_resource/accessing_security_scoped_resource.dart';
import '../bull_fs.dart';

final _plugin = AccessingSecurityScopedResource();

// Makes sure Apple resources are correctly released.
class AppleResScope {
  BFPath? _path;
  bool _granted = false;

  BFPath? get path => _path;
  final BFEnv env;

  AppleResScope(this.env);

  Future<void> requestAccess(BFPath path) async {
    if (env is! BFEnvAppleCloud) {
      return;
    }
    if (path is BFLocalPath) {
      throw Exception('Local path not supported.');
    }
    // This is important. No need release access when path is the same.
    if (_path != null && _path.toString() == path.toString()) {
      return;
    }
    await release();
    _path = path;
    _granted = await _plugin
        .startAccessingSecurityScopedResourceWithURL(path.toString());
    if (!_granted) {
      throw BFNoPermissionExp();
    }
  }

  Future<void> release() async {
    if (env is! BFEnvAppleCloud) {
      return;
    }
    // Release previous one if needed.
    if (_granted && _path != null) {
      await _plugin
          .stopAccessingSecurityScopedResourceWithURL(_path!.toString());

      _granted = false;
      _path = null;
    }
  }
}
