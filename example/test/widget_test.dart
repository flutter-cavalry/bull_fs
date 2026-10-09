import 'dart:io';

import 'package:example/main.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/bf_test_environment.dart';

void main() {
  testWidgets('Example opens the folder browser entry point', (tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.text('BullFS Example'), findsOneWidget);
    expect(find.text('Examples (Pick a folder first)'), findsOneWidget);
    expect(find.text('Tests'), findsNothing);
  });

  test('Fixture cleanup preserves its parent and neighboring files', () async {
    final fixture = await const BFLocalTestTarget().open();
    addTearDown(fixture.dispose);
    final firstRoot = await fixture.createTestRoot();
    final secondRoot = await fixture.createTestRoot();
    expect(firstRoot, isNot(secondRoot));
    final filePath = fixture.temporaryFilePath();
    await File(filePath).writeAsString('keep');

    await fixture.deleteTestRoot(firstRoot);

    expect(await fixture.env.stat(firstRoot, true), isNull);
    expect(await fixture.env.directoryExists(secondRoot, <String>[].lock),
        isNotNull);
    expect(await File(filePath).readAsString(), 'keep');
    await fixture.deleteTestRoot(secondRoot);
  });
}
