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

  /// Calls [AppleScopedResource.requestAccess].
  Future<void> requestAccess() async {
    await _res.requestAccess();
  }

  /// Calls [AppleScopedResource.release].
  Future<void> release() async {
    await _res.release();
  }

  /// Calls [AppleScopedResource.useAccess].
  Future<bool> useAccess(Future<void> Function() action) async {
    return _res.useAccess(action);
  }

  /// Calls [AppleScopedResource.tryAccess].
  Future<void> tryAccess(Future<void> Function(bool granted) action) async {
    await _res.tryAccess(action);
  }
}
