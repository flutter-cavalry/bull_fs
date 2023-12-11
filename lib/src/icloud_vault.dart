import 'dart:io';

import 'package:accessing_security_scoped_resource/accessing_security_scoped_resource.dart';
import 'package:bull_fs/bull_fs.dart';

final _plugin = AccessingSecurityScopedResource();

// Makes sure icloud resources are correctly released.
class IcloudVault {
  BFPath? _path;
  bool _granted = false;

  BFPath? get path => _path;

  IcloudVault._();

  static IcloudVault? create({required bool macOSScoped}) {
    if (Platform.isIOS || (Platform.isMacOS && macOSScoped)) {
      return IcloudVault._();
    }
    return null;
  }

  Future<void> requestAccess(BFPath path) async {
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
    // Release previous one if needed.
    if (_granted && _path != null) {
      await _plugin
          .stopAccessingSecurityScopedResourceWithURL(_path!.toString());

      _granted = false;
      _path = null;
    }
  }
}
