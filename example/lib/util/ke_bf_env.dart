import 'dart:io';

import 'package:bull_fs/bull_fs.dart';

BFEnv newUnsafeKeBFEnv({required bool macOSScoped}) {
  if (Platform.isAndroid) {
    return BFEnvAndroidSAF();
  }
  if (Platform.isIOS) {
    return BFEnvAppleCloud();
  }
  if (Platform.isMacOS && macOSScoped) {
    return BFEnvAppleCloud();
  }
  return BFEnvLocal();
}
