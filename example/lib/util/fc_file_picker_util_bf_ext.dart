// v2: Migrate to new `FilePickerXResult`.

import 'dart:io';

import 'package:bull_fs/bull_fs.dart';
import 'package:fc_file_picker_util/fc_file_picker_util.dart';

extension FilePickerUtilExtension on FcFilePickerXResult {
  BFPath toBFPath({required bool macOSScoped}) {
    var scoped = false;
    if (Platform.isMacOS) {
      scoped = macOSScoped;
    } else if (Platform.isAndroid || Platform.isIOS) {
      scoped = true;
    }
    if (!scoped) {
      if (path == null) {
        throw Exception('Unexpected null str from FilePickerXResult');
      }
      return BFLocalPath(path!);
    }
    if (path != null) {
      return BFScopedPath(path!);
    }
    if (uri != null) {
      return BFScopedPath(uri!.toString());
    }
    throw Exception('Unexpected null uri from FilePickerXResult');
  }
}
