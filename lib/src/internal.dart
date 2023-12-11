import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:fc_path_util/fc_path_util.dart';
import 'package:next_available_name/next_available_name.dart';

import 'bf_env.dart';
import 'types.dart';

Future<String> zBFNonSAFNextAvailableFileName(
    BFEnv env, BFPath dir, String unsafeFileName, bool isDir) async {
  final nameAndExts = isDir
      ? FCPathNameAndExtensions(unsafeFileName, '')
      : FCPathUtil.basenameAndExtensions(unsafeFileName);
  final newNameWithoutExt = await nextAvailableName(
      nameAndExts.name,
      200,
      (nameWithoutExt) async =>
          await env.stat(dir,
              relPath: [nameWithoutExt + nameAndExts.extensions].lock) ==
          null);
  if (newNameWithoutExt == null) {
    throw BFTooManyDuplicateFilenamesExp();
  }
  return newNameWithoutExt + nameAndExts.extensions;
}
