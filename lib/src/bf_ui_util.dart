import 'dart:io';

import 'package:darwin_url/darwin_url.dart';
import 'package:flutter/material.dart';

import '../bull_fs.dart';

final DarwinUrl _darwinUrl = DarwinUrl();

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
    if (err is BFDuplicateItemExp) {
      return bfzSameFileOrFolderExist;
    } else if (err is BFTooManyDuplicateFilenamesExp) {
      return bfzTooManyDuplicateFilenames;
    } else if (err is BFNoPermissionExp) {
      return bfzPermissionDenied;
    }
    return null;
  }

  /// Returns a [BFInitResult] which determines the resolve [BFEnv] and [BFPath] based on the platform.
  /// [path] and [uri] cannot be both null.
  ///
  /// [path] is the local path of the directory.
  /// [uri] is the uri of the directory.
  static Future<BFInitResult> initFromUserDirectory(
      {required String? path, required String? uri, bool? macosIcloud}) async {
    if (path == null && uri == null) {
      throw Exception('Both path and uri are null');
    }

    var isIcloud = false;
    if (Platform.isAndroid) {
      if (uri == null) {
        throw Exception('Unexpected null androidUri from FilePickerXResult');
      }
      return BFInitResult(BFScopedPath(uri.toString()), BFSafEnv(), false);
    }
    if (Platform.isIOS) {
      if (uri == null) {
        throw Exception('Unexpected null iosUrl from FilePickerXResult');
      }
      isIcloud = await _darwinUrl.isUbiquitousUrlItem(uri);
      return BFInitResult(BFScopedPath(uri), BFNsfcEnv(), isIcloud);
    }
    if (Platform.isMacOS) {
      if (uri != null) {
        isIcloud = macosIcloud ?? await _darwinUrl.isUbiquitousUrlItem(uri);
      } else if (path != null) {
        isIcloud = macosIcloud ?? await _darwinUrl.isUbiquitousPathItem(path);
      } else {
        throw Exception('iosUrl and path are both null');
      }
      if (isIcloud) {
        return BFInitResult(BFScopedPath(uri!), BFNsfcEnv(), isIcloud);
      }
      return BFInitResult(BFLocalPath(path!), BFLocalEnv(), isIcloud);
    }
    if (path == null) {
      throw Exception('Unexpected null path from FilePickerXResult');
    }
    return BFInitResult(BFLocalPath(path), BFLocalEnv(), false);
  }
}

/// The result of [BFUiUtil.initFromUserDirectory].
class BFInitResult {
  final BFPath path;
  final BFEnv env;
  final bool isIcloud;

  BFInitResult(this.path, this.env, this.isIcloud);
}
