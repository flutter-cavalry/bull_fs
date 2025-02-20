import 'package:accessing_security_scoped_resource/accessing_security_scoped_resource.dart';
import '../bull_fs.dart';

final _plugin = AccessingSecurityScopedResource();

/// This class is used to manage the access to the security scoped resource.
/// This class only has effect on [BFNsfcEnv].
class BFResScope {
  bool _granted = false;

  final BFEnv env;
  final BFPath path;

  bool get granted => _granted;

  BFResScope(this.env, this.path);

  /// Request access to the security scoped resource.
  /// Throws [BFNoPermissionExp] if the access is denied.
  Future<void> requestAccess() async {
    if (env is! BFNsfcEnv) {
      return;
    }
    if (path is BFLocalPath) {
      throw Exception('Local path not supported.');
    }
    // No need to request access if already granted.
    if (_granted) {
      return;
    }
    _granted = await _plugin
        .startAccessingSecurityScopedResourceWithURL(path.toString());
    if (!_granted) {
      throw BFNoPermissionExp();
    }
  }

  /// Release the access to the security scoped resource.
  Future<void> release() async {
    if (env is! BFNsfcEnv) {
      return;
    }
    // Release previous one if needed.
    if (_granted) {
      await _plugin.stopAccessingSecurityScopedResourceWithURL(path.toString());
      _granted = false;
    }
  }

  /// Request access to the security scoped resource and run the action.
  Future<void> requestAccessWithAction(Future<void> Function() action) async {
    await requestAccess();
    try {
      await action();
    } finally {
      await release();
    }
  }
}
