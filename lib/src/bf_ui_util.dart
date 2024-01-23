import 'package:flutter/material.dart';

import 'types.dart';

class BFUiUtil {
  static String? translateError(
    BuildContext context,
    Object err, {
    required String bfzSameFileOrFolderExist,
    required String bfzTooManyDuplicateFilenames,
    required String bfzPermissionDenied,
  }) {
    if (err is BFDuplicateItemExp) {
      return bfzSameFileOrFolderExist;
    } else if (err is BFTooManyDuplicateFilenamesExp) {
      return bfzTooManyDuplicateFilenames;
    } else if (err is BFNoPermissionExp) {
      return bfzPermissionDenied;
    }
    return null;
  }
}
