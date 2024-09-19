import 'bf_env.dart';
import 'bf_saf_env.dart';
import 'bf_nsfc_env.dart';
import 'bf_local_env.dart';

class BFEnvUtil {
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
