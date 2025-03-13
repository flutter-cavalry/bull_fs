import 'package:accessing_security_scoped_resource/accessing_security_scoped_resource.dart';

/// A wrapper around [AppleScopedResource].
class BFAppleScopedRes {
  final String url;
  final bool isFilePath;

  bool get granted => _res.granted;

  late AppleScopedResource _res;

  BFAppleScopedRes(this.url, {this.isFilePath = false}) {
    _res = AppleScopedResource(url, isFilePath: isFilePath);
  }

  /// Request access to the security scoped resource.
  @Deprecated('Use [useAccess] instead.')
  Future<void> requestAccess() async {
    await _res.requestAccess();
  }

  /// Release the access to the security scoped resource.
  @Deprecated('Use [useAccess] instead.')
  Future<void> release() async {
    await _res.release();
  }

  /// Request access to the security scoped resource and run the action. This also releases the access after the action is done.
  Future<bool> useAccess(Future<void> Function() action) async {
    return _res.useAccess(action);
  }
}
