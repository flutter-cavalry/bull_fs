import 'package:integration_test/integration_test.dart';

import 'support/bf_env_suite.dart';
import 'support/bf_test_environment.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  BFEnvSuite(const BFLocalTestTarget()).register();
}
