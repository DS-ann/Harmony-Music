import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/harness.dart';

/// The broadest check there is: the whole app boots and renders its home
/// screen with every external boundary faked.
///
/// Uses the shared harness rather than its own boot sequence — the pieces it
/// used to be missing (`AudioService.init`, dotenv, the first-run prompts) are
/// exactly what the harness exists to set up, and duplicating that here only
/// meant this file drifted out of sync with it.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app boots with mocked external service boundaries', (
    tester,
  ) async {
    await bootTestApp(tester);

    expect(find.text('Home'), findsWidgets);
    expect(find.textContaining('Fixture'), findsWidgets);
  });
}
