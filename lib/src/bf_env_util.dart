import 'bf_env.dart';
import 'bf_saf_env.dart';
import 'bf_nsfc_env.dart';
import 'bf_local_env.dart';

/// Utility class for [BFEnv].
class BFEnvUtil {
  /// Creates a [BFEnv] instance based on the given [BFEnvType].
  static BFEnv typeToEnv(BFEnvType type) {
    switch (type) {
      case BFEnvType.local:
        return BFLocalEnv();
      case BFEnvType.icloud:
        return BFNsfcEnv();
      case BFEnvType.saf:
        return BFSafEnv();
    }
  }
}
