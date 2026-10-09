import 'dart:io';
import 'dart:typed_data';

import 'package:bull_fs/bull_fs.dart';
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

  test('Fixture disposal releases access without deleting the selected parent',
      () async {
    final selected = await Directory.systemTemp.createTemp('bull_fs_selected_');
    addTearDown(() => selected.delete(recursive: true));
    final scratch = await Directory.systemTemp.createTemp('bull_fs_scratch_');
    addTearDown(() async {
      if (await scratch.exists()) {
        await scratch.delete(recursive: true);
      }
    });
    var releaseCount = 0;
    final fixture = BFTestEnvironment(
        BFLocalEnv(), BFLocalPath(selected.path), scratch, () async {
      releaseCount++;
    });
    await fixture.env.writeFileBytes(
        BFLocalPath(selected.path), 'keep.txt', Uint8List.fromList([1]));
    final root = await fixture.createTestRoot();
    final scratchFile = fixture.temporaryFilePath();
    await File(scratchFile).writeAsString('temporary');

    await fixture.deleteTestRoot(root);
    await fixture.dispose();

    expect(await fixture.env.directoryToMap(BFLocalPath(selected.path)),
        {'keep.txt': '01'});
    expect(await scratch.exists(), isFalse);
    expect(await File(scratchFile).exists(), isFalse);
    expect(releaseCount, 1);
  });

  test('Fixture releases access even when scratch cleanup fails', () async {
    final selected = await Directory.systemTemp.createTemp('bull_fs_selected_');
    addTearDown(() => selected.delete(recursive: true));
    final scratch = await Directory.systemTemp.createTemp('bull_fs_scratch_');
    var released = false;
    final fixture = BFTestEnvironment(
        BFLocalEnv(), BFLocalPath(selected.path), scratch, () async {
      released = true;
    });
    await scratch.delete();

    await expectLater(fixture.dispose(), throwsA(isA<FileSystemException>()));

    expect(released, isTrue);
    expect(await selected.exists(), isTrue);
  });
}
