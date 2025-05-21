import 'dart:io';

import 'package:darwin_url/darwin_url.dart';

import 'bf_env.dart';
import 'bf_saf_env.dart';
import 'bf_nsfc_env.dart';
import 'bf_local_env.dart';
import 'types.dart';

final DarwinUrl _darwinUrl = DarwinUrl();

/// Utility class for [BFEnv].
class BFEnvUtil {
  /// Creates a [BFEnv] instance based on the given [BFEnvType].
  static BFEnv typeToEnv(BFEnvType type) {
    switch (type) {
      case BFEnvType.local:
        return BFLocalEnv();
      case BFEnvType.nsfc:
        return BFNsfcEnv();
      case BFEnvType.saf:
        return BFSafEnv();
    }
  }

  /// Returns a [BFInitResult] which determines the resolve [BFEnv] and [BFPath] based on the platform.
  /// [path] and [uri] cannot be both null.
  ///
  /// [path] is the local path of the directory.
  /// [uri] is the uri of the directory.
  static Future<BFDirInitResult> envFromDirectory({
    required String? path,
    required String? uri,
    bool? macosIcloud,
  }) async {
    if (path == null && uri == null) {
      throw Exception('Both path and uri are null');
    }

    var isIcloud = false;
    if (Platform.isAndroid) {
      if (uri == null) {
        throw Exception('Unexpected null Uri');
      }
      return BFDirInitResult(BFScopedPath(uri.toString()), BFSafEnv(), false);
    }
    if (Platform.isIOS) {
      if (uri == null) {
        throw Exception('Unexpected null Uri');
      }
      isIcloud = await _darwinUrl.isUbiquitousUrlItem(uri);
      return BFDirInitResult(BFScopedPath(uri), BFNsfcEnv(), isIcloud);
    }
    if (Platform.isMacOS) {
      if (uri != null) {
        isIcloud = macosIcloud ?? await _darwinUrl.isUbiquitousUrlItem(uri);
      } else if (path != null) {
        isIcloud = macosIcloud ?? await _darwinUrl.isUbiquitousPathItem(path);
      } else {
        throw Exception('Uri and path are both null');
      }
      if (isIcloud) {
        return BFDirInitResult(BFScopedPath(uri!), BFNsfcEnv(), isIcloud);
      }
      return BFDirInitResult(BFLocalPath(path!), BFLocalEnv(), isIcloud);
    }
    if (path == null) {
      throw Exception('Unexpected null path');
    }
    return BFDirInitResult(BFLocalPath(path), BFLocalEnv(), false);
  }
}

/// The result of [bfEnvFromDirectory].
class BFDirInitResult {
  // The [BFPath] of the directory.
  final BFPath path;
  // The [BFEnv] created.
  final BFEnv env;
  // Whether the directory is in iCloud.
  final bool isIcloud;

  BFDirInitResult(this.path, this.env, this.isIcloud);
}
