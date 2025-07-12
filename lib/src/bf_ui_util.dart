import 'package:flutter/material.dart';

import '../bull_fs.dart';

/// Utility class for UI.
class BFUiUtil {
  /// Translates the error thrown in [bull_fs] to a human-readable message.
  static String? translateError(
    BuildContext context,
    Object err, {
    required String bfzSameFileOrFolderExist,
    required String bfzTooManyDuplicateFilenames,
    required String bfzPermissionDenied,
  }) {
    if (err is BFDuplicateItemException) {
      return bfzSameFileOrFolderExist;
    } else if (err is BFNoAvailableNameException) {
      return bfzTooManyDuplicateFilenames;
    } else if (err is BFNoPermissionException) {
      return bfzPermissionDenied;
    }
    return null;
  }
}
