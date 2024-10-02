// v4: Update to BF 240923.
// v3: Update to latest `bull_fs`.
// v2: Migrate to new `FilePickerXResult`.

import 'dart:io';

import 'package:bull_fs/bull_fs.dart';
import 'package:darwin_url/darwin_url.dart';
import 'package:fc_file_picker_util/fc_file_picker_util.dart';

final DarwinUrl _darwinUrl = DarwinUrl();

class ResolveBFPathResult {
  final BFPath path;
  final BFEnv env;
  final bool isIcloud;

  ResolveBFPathResult(this.path, this.env, this.isIcloud);
}

extension FilePickerUtilExtension on FcFilePickerXResult {
  Future<ResolveBFPathResult> resolveBFPath({bool? macosIcloud}) async {
    var isIcloud = false;

    if (Platform.isAndroid) {
      if (androidUri == null) {
        throw Exception('Unexpected null androidUri from FilePickerXResult');
      }
      return ResolveBFPathResult(
          BFScopedPath(androidUri!.toString()), BFSafEnv(), false);
    }
    if (Platform.isIOS) {
      if (iosUrl == null) {
        throw Exception('Unexpected null iosUrl from FilePickerXResult');
      }
      isIcloud = await _darwinUrl.isUbiquitousUrlItem(iosUrl!);
      return ResolveBFPathResult(BFScopedPath(iosUrl!), BFNsfcEnv(), isIcloud);
    }
    if (Platform.isMacOS) {
      if (iosUrl != null) {
        isIcloud = macosIcloud ?? await _darwinUrl.isUbiquitousUrlItem(iosUrl!);
      } else if (path != null) {
        isIcloud = macosIcloud ?? await _darwinUrl.isUbiquitousPathItem(path!);
      } else {
        throw Exception('iosUrl and path are both null');
      }
      if (isIcloud) {
        return ResolveBFPathResult(
            BFScopedPath(iosUrl!), BFNsfcEnv(), isIcloud);
      }
      return ResolveBFPathResult(BFLocalPath(path!), BFLocalEnv(), isIcloud);
    }
    if (path == null) {
      throw Exception('Unexpected null path from FilePickerXResult');
    }
    return ResolveBFPathResult(BFLocalPath(path!), BFLocalEnv(), false);
  }
}
