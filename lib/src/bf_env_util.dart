import 'bf_env.dart';
import 'bf_env_android_saf.dart';
import 'bf_env_apple_cloud.dart';
import 'bf_env_local.dart';

class BFEnvUtil {
  static BFEnv typeToEnv(BFEnvType type) {
    switch (type) {
      case BFEnvType.local:
        return BFEnvLocal();
      case BFEnvType.icloud:
        return BFEnvAppleCloud();
      case BFEnvType.saf:
        return BFEnvAndroidSAF();
    }
  }
}
