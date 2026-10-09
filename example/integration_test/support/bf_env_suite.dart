import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bull_fs/bull_fs.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'bf_test_environment.dart';

const _defFolderContentFile = 'content.bin';
const _defStringContents = 'abcdef 🍉🌏';
final _defStringContentsBytes = utf8.encode(_defStringContents);

class _FailingMoveLocalEnv extends BFLocalEnv {
  @override
  Future<BFPathAndName> moveToDirSafe(
    BFPath src,
    bool isDir,
    BFPath srcDir,
    BFPath destDir, {
    BFNameFinder? nameFinder,
    Set<String>? pendingNames,
  }) async {
    throw Exception('Injected move failure');
  }
}

class BFEnvSuite {
  final BFTestTarget target;
  BFTestEnvironment? _environment;
  Future<BFTestEnvironment>? _opening;

  BFEnvSuite(this.target);

  BFEnv get env => _environment!.env;

  String _temporaryFilePath() => _environment!.temporaryFilePath();

  void _test(String name, Future<void> Function(BFPath root) body) {
    testWidgets(name, (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await tester.runAsync(() async {
        final environment = _environment ??= await (_opening ??= target.open());
        final root = await environment.createTestRoot();
        try {
          await body(root);
        } finally {
          await environment.deleteTestRoot(root);
        }
      });
    }, timeout: const Timeout(Duration(minutes: 5)));
  }

  String _dupSuffix(String fileName, int c) {
    final ext = p.extension(fileName);
    final name = p.basenameWithoutExtension(fileName);
    return '$name (${c - 1})$ext';
  }

  Future<void> _createNestedDir(BFEnv env, BFPath r) async {
    final subDir1 = await env.mkdirp(r, ['一 二'].lock);
    await env.writeFileBytes(subDir1, 'a.txt', Uint8List.fromList([1]));
    await env.writeFileBytes(subDir1, 'b.txt', Uint8List.fromList([2]));

    // b is empty.
    await env.mkdirp(r, ['b'].lock);

    final subDir11 = await env.mkdirp(subDir1, ['deep'].lock);
    await env.writeFileBytes(subDir11, 'c.txt', Uint8List.fromList([3]));

    await env.writeFileBytes(r, 'root.txt', Uint8List.fromList([4]));
    await env.writeFileBytes(r, 'root2.txt', Uint8List.fromList([5]));
  }

  String _formatEntityList(List<BFEntity> list) {
    list.sort((a, b) => a.name.compareTo(b.name));
    return list.map((e) => e.toStringWithLength()).join('|');
  }

  Future<String> _formatPathInfoFileList(
      BFEnv env, List<BFPathAndDirRelPath> list) async {
    final entities = await Future.wait(list.map((e) async {
      final st = await env.stat(e.path, false);
      if (st == null) {
        throw Exception('Stat failed: ${e.path}');
      }
      return (e, st);
    }));
    entities.sort((a, b) => a.$2.name.compareTo(b.$2.name));
    return entities
        .map((e) =>
            '${e.$1.dirRelPath.isEmpty ? '' : '${e.$1.dirRelPath.join('/')}/'}${e.$2.name}')
        .toList()
        .join(' | ');
  }

  void register({bool skip = false}) {
    group(target.name, () {
      tearDownAll(() async {
        await _environment?.dispose();
      });
      _test('ensureDir', (root) async {
        final r = root;
        await env.mkdirp(r, ['space 一 二 三'].lock);

        // Do it twice and there should be no error.
        final newDir = await env.mkdirp(r, ['space 一 二 三'].lock);

        // Test return value.
        final st = await env.stat(newDir, true);
        expect(st, isNotNull);
        expect(st!.isDir, true);
        expect(st.name, 'space 一 二 三');

        expect(await env.directoryToMap(r), {"space 一 二 三": {}});
      });

      _test('ensureDir (failed)', (root) async {
        await env.writeFileBytes(root, 'space 一 二 三', Uint8List.fromList([1]));
        await expectLater(
          env.mkdirp(root, ['space 一 二 三'].lock),
          throwsException,
        );
        expect(await env.directoryToMap(root), {"space 一 二 三": "01"});
      });

      _test('ensureDirs', (root) async {
        final r = root;
        var newDir = await env.mkdirp(r, ['space 一 二 三', '22'].lock);
        // Test return value.
        var st = await env.stat(newDir, true);
        expect(st, isNotNull);
        expect(st!.isDir, true);
        expect(st.name, '22');

        // Do it again with a new subdir.
        newDir = await env.mkdirp(r, ['space 一 二 三', '22', '3 33'].lock);
        st = await env.stat(newDir, true);
        expect(st!.isDir, true);
        expect(st.name, '3 33');

        // Do it again.
        newDir = await env.mkdirp(r, ['space 一 二 三', '22', '3 33'].lock);
        st = await env.stat(newDir, true);
        expect(st!.isDir, true);
        expect(st.name, '3 33');

        expect(await env.directoryToMap(r), {
          "space 一 二 三": {
            "22": {"3 33": {}}
          }
        });
      });

      _test('ensureDirs (failed)', (root) async {
        await env.mkdirp(root, ['space 一 二 三', '22', '3 33'].lock);
        final parent =
            await env.directoryExists(root, ['space 一 二 三', '22'].lock);
        await env.writeFileBytes(parent!, 'file', Uint8List.fromList([1]));
        await expectLater(
          env.mkdirp(root, ['space 一 二 三', '22', 'file', 'another'].lock),
          throwsException,
        );
        expect(await env.directoryToMap(root), {
          "space 一 二 三": {
            "22": {"file": "01", "3 33": {}}
          }
        });
      });

      _test('exists and findBasename (dir)', (root) async {
        final r = root;
        await env.mkdirp(r, ['一', '22', '3 3', '4'].lock);
        // Test return value.
        final path = await env.directoryExists(
            await _getPath(env, r, '一/22'), ['3 3', '4'].lock);
        final st = await env.stat(path!, true);
        expect(st, isNotNull);
        expect(st!.isDir, true);
        expect(st.name, '4');

        final basename = await env.findBasename(path, true);
        expect(basename, '4');

        final conflictType = await env.fileExists(
            await _getPath(env, r, '一/22'), ['3 3', '4'].lock);
        expect(conflictType, isNull);

        final notFound = await env.directoryExists(
            await _getPath(env, r, '一/22'), ['3 3', '5'].lock);
        expect(notFound, isNull);
      });

      _test('exists and findBasename (file)', (root) async {
        final r = root;
        final dir = await env.mkdirp(r, ['一', '22'].lock);
        await env.writeFileBytes(dir, '3 3', Uint8List.fromList([1]));

        // Test return value.
        final path = await env.fileExists(
            await _getPath(env, r, '一'), ['22', '3 3'].lock);
        final st = await env.stat(path!, false);
        expect(st, isNotNull);
        expect(st!.isDir, false);
        expect(st.name, '3 3');

        final basename = await env.findBasename(path, false);
        expect(basename, '3 3');

        final conflictType = await env.directoryExists(
            await _getPath(env, r, '一'), ['22', '3 3'].lock);
        expect(conflictType, isNull);

        final notFound = await env.fileExists(
            await _getPath(env, r, '一'), ['22', '3 4'].lock);
        expect(notFound, isNull);
      });

      _test('createDir', (root) async {
        final r = root;
        final newDir = await env.createDir(r, 'space 一 二 三');

        // Test return value.
        final st = await env.stat(newDir.path, true);
        expect(st, isNotNull);
        expect(st!.isDir, true);
        expect(st.name, 'space 一 二 三');
        expect(newDir.fileName, st.name);

        expect(await env.directoryToMap(r), {"space 一 二 三": {}});
      });

      _test('createDir (with conflict)', (root) async {
        final r = root;
        await env.writeFileBytes(r, 'space 一 二 三', Uint8List.fromList([1]));

        final newDir = await env.createDir(r, 'space 一 二 三');

        // Test return value.
        final st = await env.stat(newDir.path, true);
        expect(st, isNotNull);
        expect(st!.isDir, true);
        expect(st.name, 'space 一 二 三 (1)');
        expect(newDir.fileName, st.name);

        expect(await env.directoryToMap(r),
            {"space 一 二 三 (1)": {}, "space 一 二 三": "01"});
      });

      void testWriteFileStream(String fileName, bool multiple, bool overwrite,
          Map<String, dynamic> fs) {
        _test(
            'writeFileStream $fileName multiple: $multiple, overwrite: $overwrite',
            (root) async {
          final r = root;
          var outStream =
              await env.writeFileStream(r, fileName, overwrite: overwrite);
          await outStream.write(utf8.encode('abc1'));
          await outStream.write(_defStringContentsBytes);
          await outStream.close();

          // Test `getPath`.
          var destUri = outStream.getPath();
          var destUriStat = await env.stat(destUri, false);
          expect(destUriStat, isNotNull);
          expect(destUriStat!.isDir, false);
          expect(destUriStat.name, fileName);
          expect(destUriStat.length, 19);

          if (multiple) {
            // Write to the same file again.
            outStream =
                await env.writeFileStream(r, fileName, overwrite: overwrite);
            await outStream.write(utf8.encode('abc2'));
            await outStream.write(_defStringContentsBytes);
            await outStream.close();

            // Test `getPath`.
            destUri = outStream.getPath();
            destUriStat = await env.stat(destUri, false);
            expect(destUriStat, isNotNull);
            expect(destUriStat!.isDir, false);
            expect(destUriStat.name,
                overwrite ? fileName : _dupSuffix(fileName, 2));
            expect(destUriStat.length, 19);

            // Write to the same file again.
            outStream =
                await env.writeFileStream(r, fileName, overwrite: overwrite);

            // Write a smaller string to test that the file is truncated.
            await outStream.write(utf8.encode('A'));
            await outStream.write(utf8.encode('B'));
            await outStream.write(utf8.encode('C'));
            await outStream.flush();
            await outStream.write(utf8.encode('A'));
            await outStream.flush();
            await outStream.close();

            // Test `outStream.close` can be called multiple times.
            await outStream.close();
            await outStream.close();

            // Test `getPath`.
            destUri = outStream.getPath();
            destUriStat = await env.stat(destUri, false);
            expect(destUriStat, isNotNull);
            expect(destUriStat!.isDir, false);
            expect(destUriStat.name,
                overwrite ? fileName : _dupSuffix(fileName, 3));
            expect(destUriStat.length, 4);
          }

          expect(await env.directoryToMap(r), fs);
        });
      }

      // Known extension.
      testWriteFileStream('test 三.txt', false, false,
          {"test 三.txt": "6162633161626364656620f09f8d89f09f8c8f"});
      testWriteFileStream('test 三.txt', true, false, {
        _dupSuffix('test 三.txt', 2): "6162633261626364656620f09f8d89f09f8c8f",
        "test 三.txt": "6162633161626364656620f09f8d89f09f8c8f",
        _dupSuffix('test 三.txt', 3): "41424341"
      });
      testWriteFileStream('test 三.txt', true, true, {"test 三.txt": "41424341"});
      // Unknown extension.
      testWriteFileStream('test 三.elephant', false, false,
          {"test 三.elephant": "6162633161626364656620f09f8d89f09f8c8f"});
      testWriteFileStream('test 三.elephant', true, false, {
        _dupSuffix('test 三.elephant', 2):
            "6162633261626364656620f09f8d89f09f8c8f",
        "test 三.elephant": "6162633161626364656620f09f8d89f09f8c8f",
        _dupSuffix('test 三.elephant', 3): "41424341"
      });
      testWriteFileStream(
          'test 三.elephant', true, true, {"test 三.elephant": "41424341"});
      // Multiple extensions.
      testWriteFileStream('test 三.elephant.xyz', false, false,
          {"test 三.elephant.xyz": "6162633161626364656620f09f8d89f09f8c8f"});
      testWriteFileStream('test 三.elephant.xyz', true, false, {
        _dupSuffix('test 三.elephant.xyz', 2):
            "6162633261626364656620f09f8d89f09f8c8f",
        "test 三.elephant.xyz": "6162633161626364656620f09f8d89f09f8c8f",
        _dupSuffix('test 三.elephant.xyz', 3): "41424341"
      });
      testWriteFileStream('test 三.elephant.xyz', true, true,
          {"test 三.elephant.xyz": "41424341"});
      // No extension.
      testWriteFileStream('test 三', false, false,
          {"test 三": "6162633161626364656620f09f8d89f09f8c8f"});
      testWriteFileStream('test 三', true, false, {
        "test 三": "6162633161626364656620f09f8d89f09f8c8f",
        _dupSuffix('test 三', 2): "6162633261626364656620f09f8d89f09f8c8f",
        _dupSuffix('test 三', 3): "41424341"
      });
      testWriteFileStream('test 三', true, true, {"test 三": "41424341"});

      _test('writeFileStream (name updater)', (root) async {
        final r = root;

        // Add first.
        var out = await env.writeFileStream(r, '一 二.txt.png',
            nameFinder: _testNameFinder);
        await out.write(_defStringContentsBytes);
        await out.close();
        // Add second which triggers the name updater.
        out = await env.writeFileStream(r, '一 二.txt.png',
            nameFinder: _testNameFinder);
        await out.write(_defStringContentsBytes);
        await out.close();
        var st = await env.stat(out.getPath(), false);
        expect(st!.name, 'NU-一 二.txt.png-false-1');
        expect(st.name, out.getFileName());
      });

      _test('writeFileStream (concurrent writes)', (root) async {
        final r = root;

        Future<void> testWrite(int i) async {
          final out = await env.writeFileStream(r, 't_$i.txt');
          await out.writeManyChunks(i.toString());
        }

        Future<void> verifyResult(int i) async {
          final path = await _getPath(env, r, 't_$i.txt');
          await _checkManyChunks(env, path, i.toString());
        }

        await Future.wait([for (var i = 0; i < 10; i++) testWrite(i)]);
        await Future.wait([for (var i = 0; i < 10; i++) verifyResult(i)]);
      });

      _test('readFileStream', (root) async {
        final r = root;
        final tmpFile = _temporaryFilePath();
        await File(tmpFile).writeAsString(_defStringContents);
        final pasteRes = await env.pasteLocalFile(tmpFile, r, 'test.txt');

        final stream = await env.readFileStream(pasteRes.path);
        final bytes = await stream.fold<List<int>>([], (prev, element) {
          prev.addAll(element);
          return prev;
        });
        expect(utf8.decode(bytes), _defStringContents);

        expect(await env.directoryToMap(r),
            {"test.txt": "61626364656620f09f8d89f09f8c8f"});
      });

      _test('readFileStream (with offset)', (root) async {
        final r = root;
        final tmpFile = _temporaryFilePath();
        await File(tmpFile).writeAsString(_defStringContents);
        final pasteRes = await env.pasteLocalFile(tmpFile, r, 'test.txt');

        final stream = await env.readFileStream(pasteRes.path, start: 3);
        final bytes = await stream.fold<List<int>>([], (prev, element) {
          prev.addAll(element);
          return prev;
        });
        expect(utf8.decode(bytes), _defStringContents.substring(3));

        expect(await env.directoryToMap(r),
            {"test.txt": "61626364656620f09f8d89f09f8c8f"});
      });

      _test('readFileBytes', (root) async {
        final r = root;
        final tmpFile = _temporaryFilePath();
        await File(tmpFile).writeAsString(_defStringContents);
        final pasteRes = await env.pasteLocalFile(tmpFile, r, 'test.txt');

        final bytes = await env.readFileBytes(pasteRes.path);
        expect(utf8.decode(bytes), _defStringContents);
      });

      _test('readFileBytes (start)', (root) async {
        final r = root;
        final tmpFile = _temporaryFilePath();
        await File(tmpFile).writeAsString(_defStringContents);
        final pasteRes = await env.pasteLocalFile(tmpFile, r, 'test.txt');

        final bytes = await env.readFileBytes(pasteRes.path, start: 3);
        expect(utf8.decode(bytes), _defStringContents.substring(3));
      });

      _test('readFileBytes (count)', (root) async {
        final r = root;
        final tmpFile = _temporaryFilePath();
        await File(tmpFile).writeAsString(_defStringContents);
        final pasteRes = await env.pasteLocalFile(tmpFile, r, 'test.txt');

        final bytes = await env.readFileBytes(pasteRes.path, count: 2);
        expect(utf8.decode(bytes), 'ab');
      });

      _test('readFileBytes (count larger than length)', (root) async {
        final r = root;
        final tmpFile = _temporaryFilePath();
        await File(tmpFile).writeAsString(_defStringContents);
        final pasteRes = await env.pasteLocalFile(tmpFile, r, 'test.txt');

        final bytes = await env.readFileBytes(pasteRes.path, count: 100);
        expect(utf8.decode(bytes), _defStringContents);
      });

      _test('readFileBytes (start and count)', (root) async {
        final r = root;
        final tmpFile = _temporaryFilePath();
        await File(tmpFile).writeAsString(_defStringContents);
        final pasteRes = await env.pasteLocalFile(tmpFile, r, 'test.txt');

        final bytes =
            await env.readFileBytes(pasteRes.path, start: 3, count: 2);
        expect(utf8.decode(bytes), 'de');
      });

      void testPasteToLocalFile(String fileName, bool multiple, bool overwrite,
          Map<String, dynamic> fs) {
        _test(
            'pasteLocalFile  $fileName multiple: $multiple, overwrite: $overwrite',
            (root) async {
          final r = root;
          final tmpFile = _temporaryFilePath();
          await File(tmpFile).writeAsString('$_defStringContents 1');
          // Add first test.txt
          var pasteRes = await env.pasteLocalFile(tmpFile, r, fileName,
              overwrite: overwrite);
          var st = await env.stat(pasteRes.path, false);
          expect(st!.name, fileName);
          expect(st.name, pasteRes.fileName);
          expect(st.length, 17);

          if (multiple) {
            // Add second test.txt
            await File(tmpFile).writeAsString('$_defStringContents 2');
            pasteRes = await env.pasteLocalFile(tmpFile, r, fileName,
                overwrite: overwrite);
            st = await env.stat(pasteRes.path, false);
            expect(st!.name, overwrite ? fileName : _dupSuffix(fileName, 2));
            expect(st.name, pasteRes.fileName);
            expect(st.length, 17);

            // Add third test.txt
            await File(tmpFile).writeAsString('$_defStringContents 3');
            pasteRes = await env.pasteLocalFile(tmpFile, r, fileName,
                overwrite: overwrite);
            st = await env.stat(pasteRes.path, false);
            expect(st!.name, overwrite ? fileName : _dupSuffix(fileName, 3));
            expect(st.name, pasteRes.fileName);
            expect(st.length, 17);
          }

          expect(await env.directoryToMap(r), fs);
        });
      }

      // Known extension.
      testPasteToLocalFile('test 三.txt', false, false,
          {"test 三.txt": "61626364656620f09f8d89f09f8c8f2031"});
      testPasteToLocalFile('test 三.txt', true, false, {
        _dupSuffix('test 三.txt', 2): "61626364656620f09f8d89f09f8c8f2032",
        _dupSuffix('test 三.txt', 3): "61626364656620f09f8d89f09f8c8f2033",
        "test 三.txt": "61626364656620f09f8d89f09f8c8f2031"
      });
      testPasteToLocalFile('test 三.txt', true, true,
          {"test 三.txt": "61626364656620f09f8d89f09f8c8f2033"});
      // Unknown extension.
      testPasteToLocalFile('test 三.elephant', false, false,
          {"test 三.elephant": "61626364656620f09f8d89f09f8c8f2031"});
      testPasteToLocalFile('test 三.elephant', true, false, {
        _dupSuffix('test 三.elephant', 2): "61626364656620f09f8d89f09f8c8f2032",
        "test 三.elephant": "61626364656620f09f8d89f09f8c8f2031",
        _dupSuffix('test 三.elephant', 3): "61626364656620f09f8d89f09f8c8f2033"
      });
      testPasteToLocalFile('test 三.elephant', true, true,
          {"test 三.elephant": "61626364656620f09f8d89f09f8c8f2033"});
      // Multiple extensions.
      testPasteToLocalFile('test 三.elephant.xyz', false, false,
          {"test 三.elephant.xyz": "61626364656620f09f8d89f09f8c8f2031"});
      testPasteToLocalFile('test 三.elephant.xyz', true, false, {
        _dupSuffix('test 三.elephant.xyz', 2):
            "61626364656620f09f8d89f09f8c8f2032",
        "test 三.elephant.xyz": "61626364656620f09f8d89f09f8c8f2031",
        _dupSuffix('test 三.elephant.xyz', 3):
            "61626364656620f09f8d89f09f8c8f2033"
      });
      testPasteToLocalFile('test 三.elephant.xyz', true, true,
          {"test 三.elephant.xyz": "61626364656620f09f8d89f09f8c8f2033"});
      // No extension.
      testPasteToLocalFile('test 三', false, false,
          {"test 三": "61626364656620f09f8d89f09f8c8f2031"});
      testPasteToLocalFile('test 三', true, false, {
        "test 三": "61626364656620f09f8d89f09f8c8f2031",
        _dupSuffix('test 三', 2): "61626364656620f09f8d89f09f8c8f2032",
        _dupSuffix('test 三', 3): "61626364656620f09f8d89f09f8c8f2033"
      });
      testPasteToLocalFile('test 三', true, true,
          {"test 三": "61626364656620f09f8d89f09f8c8f2033"});

      _test('pasteLocalFile (name updater)', (root) async {
        final r = root;
        final tmpFile = _temporaryFilePath();
        await File(tmpFile).writeAsString('$_defStringContents 1');

        // Add first.
        await env.pasteLocalFile(tmpFile, r, '一 二.txt.png',
            nameFinder: _testNameFinder);
        // Add second which triggers the name updater.
        var pasteRes = await env.pasteLocalFile(tmpFile, r, '一 二.txt.png',
            nameFinder: _testNameFinder);
        var st = await env.stat(pasteRes.path, false);
        expect(st!.name, 'NU-一 二.txt.png-false-1');
        expect(st.name, pasteRes.fileName);
      });

      _test('binary bytes and stream round trip', (root) async {
        final contents = Uint8List.fromList(
          List.generate(4096, (index) => index % 256),
        );
        final file = await env.writeFileBytes(root, 'binary.bin', contents);
        expect(await env.readFileBytes(file.path), contents);
        final stream =
            await env.readFileStream(file.path, bufferSize: 7, start: 253);
        expect(await stream.expand((chunk) => chunk).toList(),
            contents.sublist(253));
        expect(await env.readFileBytes(file.path, start: 253, count: 7),
            contents.sublist(253, 260));
      });

      _test('copyToLocalFile preserves bytes and source', (root) async {
        final contents = Uint8List.fromList([0, 255, 128, 1, 10, 13]);
        final source = await env.writeFileBytes(root, 'source.bin', contents);
        final destination = _temporaryFilePath();
        await env.copyToLocalFile(source.path, destination);
        expect(await File(destination).readAsBytes(), contents);
        expect(await env.readFileBytes(source.path), contents);
        expect((await env.listDir(root)).map((entity) => entity.name),
            ['source.bin']);
      });

      _test('empty bytes truncate an existing file', (root) async {
        await env.writeFileBytes(
            root, 'empty.bin', Uint8List.fromList([1, 2, 3]));
        final file = await env.writeFileBytes(root, 'empty.bin', Uint8List(0),
            overwrite: true);
        expect((await env.stat(file.path, false))!.length, 0);
        expect(await env.readFileBytes(file.path), isEmpty);
        final stream = await env.readFileStream(file.path);
        expect(await stream.expand((chunk) => chunk).toList(), isEmpty);
        expect(await env.directoryToMap(root), {'empty.bin': ''});
      });

      _test('empty stream creates a readable file', (root) async {
        final output = await env.writeFileStream(root, 'empty.bin');
        await output.close();
        await output.close();
        expect(output.getFileName(), 'empty.bin');
        expect((await env.stat(output.getPath(), false))!.length, 0);
        expect(await env.readFileBytes(output.getPath()), isEmpty);
      });

      _test('readFileBytes zero count and end of file', (root) async {
        final file = await env.writeFileBytes(
            root, 'range.bin', Uint8List.fromList([0, 128, 255]));
        expect(await env.readFileBytes(file.path, count: 0), isEmpty);
        expect(await env.readFileBytes(file.path, start: 2, count: 0), isEmpty);
        expect(await env.readFileBytes(file.path, start: 3), isEmpty);
        expect(await env.readFileBytes(file.path, start: 2, count: 10), [255]);
        await env.delete(file.path, false);
        await expectLater(
            env.readFileBytes(file.path, count: 0), throwsException);
      });

      _test('delete removes only the requested subtree', (root) async {
        final subtree = await env.mkdirp(root, ['delete', 'nested'].lock);
        await env.writeFileBytes(subtree, 'child.bin', Uint8List.fromList([1]));
        await env.writeFileBytes(root, 'keep.bin', Uint8List.fromList([2]));
        final directory = await env.directoryExists(root, ['delete'].lock);
        await env.delete(directory!, true);
        expect(await env.child(root, ['delete'].lock), isNull);
        expect(await env.directoryToMap(root), {'keep.bin': '02'});
        final file = await env.fileExists(root, ['keep.bin'].lock);
        await env.delete(file!, false);
        expect(await env.stat(file, false), isNull);
        expect(await env.listDir(root), isEmpty);
        expect(await env.listDirContentFiles(root), isEmpty);
      });

      _test('deletePathIfExists is repeatable and respects item type',
          (root) async {
        final directory = await env.mkdirp(root, ['folder'].lock);
        final file =
            await env.writeFileBytes(root, 'file.bin', Uint8List.fromList([1]));
        expect(await env.fileExists(directory, null), isNull);
        expect(await env.directoryExists(file.path, <String>[].lock), isNull);
        expect(await env.fileExists(file.path, <String>[].lock), file.path);
        expect(await env.directoryExists(directory, null), directory);
        await env.deletePathIfExists(root, ['folder'].lock, false);
        await env.deletePathIfExists(root, ['file.bin'].lock, true);
        expect(
            await env.directoryToMap(root), {'folder': {}, 'file.bin': '01'});
        await env.deletePathIfExists(file.path, null, false);
        await env.deletePathIfExists(file.path, null, false);
        expect(await env.fileExists(file.path, null), isNull);
        await env.deletePathIfExists(directory, null, true);
        await env.deletePathIfExists(directory, null, true);
        expect(await env.directoryExists(directory, <String>[].lock), isNull);
        expect(await env.directoryToMap(root), isEmpty);
      });

      _test('directoryToMap filters recursively and hides contents',
          (root) async {
        await _createNestedDir(env, root);
        expect(
            await env.directoryToMap(
              root,
              hideFileContents: true,
              filter: (name, entity) => name != 'b' && name != 'b.txt',
            ),
            {
              '一 二': {
                'a.txt': null,
                'deep': {'c.txt': null}
              },
              'root.txt': null,
              'root2.txt': null,
            });
      });

      _test('concurrent writes reserve distinct pending names', (root) async {
        final pendingNames = <String>{};
        final files = await Future.wait([
          for (var index = 0; index < 5; index++)
            env.writeFileBytes(
                root, 'reserved.bin', Uint8List.fromList([index]),
                pendingNames: pendingNames),
        ]);
        expect(files.map((file) => file.fileName).toSet().length, 5);
        expect((await env.listDir(root)).length, 5);
        for (var index = 0; index < files.length; index++) {
          expect(await env.readFileBytes(files[index].path), [index]);
        }
      });

      void testwriteFileBytes(String fileName, bool multiple, bool overwrite,
          Map<String, dynamic> fs) {
        _test(
            'writeFileBytes  $fileName multiple: $multiple, overwrite: $overwrite',
            (root) async {
          final r = root;
          // Add first test.txt
          var pasteRes = await env.writeFileBytes(
              r, fileName, utf8.encode('$_defStringContents 1'),
              overwrite: overwrite);
          var st = await env.stat(pasteRes.path, false);
          expect(st!.name, fileName);
          expect(st.name, pasteRes.fileName);
          expect(st.length, 17);

          if (multiple) {
            // Add second test.txt
            pasteRes = await env.writeFileBytes(
                r, fileName, utf8.encode('$_defStringContents 2'),
                overwrite: overwrite);
            st = await env.stat(pasteRes.path, false);
            expect(st!.name, overwrite ? fileName : _dupSuffix(fileName, 2));
            expect(st.name, pasteRes.fileName);
            expect(st.length, 17);

            // Add third test.txt
            // Write a smaller string to test that the file is truncated.
            pasteRes = await env.writeFileBytes(
                r, fileName, utf8.encode('ABCD'),
                overwrite: overwrite);
            st = await env.stat(pasteRes.path, false);
            expect(st!.name, overwrite ? fileName : _dupSuffix(fileName, 3));
            expect(st.name, pasteRes.fileName);
            expect(st.length, 4);
          }

          expect(await env.directoryToMap(r), fs);
        });
      }

      // Known extension.
      testwriteFileBytes('test 三.txt', false, false,
          {"test 三.txt": "61626364656620f09f8d89f09f8c8f2031"});
      testwriteFileBytes('test 三.txt', true, false, {
        _dupSuffix('test 三.txt', 2): "61626364656620f09f8d89f09f8c8f2032",
        _dupSuffix('test 三.txt', 3): "41424344",
        "test 三.txt": "61626364656620f09f8d89f09f8c8f2031"
      });
      testwriteFileBytes('test 三.txt', true, true, {"test 三.txt": "41424344"});
      // Unknown extension.
      testwriteFileBytes('test 三.elephant', false, false,
          {"test 三.elephant": "61626364656620f09f8d89f09f8c8f2031"});
      testwriteFileBytes('test 三.elephant', true, false, {
        _dupSuffix('test 三.elephant', 2): "61626364656620f09f8d89f09f8c8f2032",
        "test 三.elephant": "61626364656620f09f8d89f09f8c8f2031",
        _dupSuffix('test 三.elephant', 3): "41424344"
      });
      testwriteFileBytes(
          'test 三.elephant', true, true, {"test 三.elephant": "41424344"});
      // Multiple extensions.
      testwriteFileBytes('test 三.elephant.xyz', false, false,
          {"test 三.elephant.xyz": "61626364656620f09f8d89f09f8c8f2031"});
      testwriteFileBytes('test 三.elephant.xyz', true, false, {
        _dupSuffix('test 三.elephant.xyz', 2):
            "61626364656620f09f8d89f09f8c8f2032",
        "test 三.elephant.xyz": "61626364656620f09f8d89f09f8c8f2031",
        _dupSuffix('test 三.elephant.xyz', 3): "41424344"
      });
      testwriteFileBytes('test 三.elephant.xyz', true, true,
          {"test 三.elephant.xyz": "41424344"});
      // No extension.
      testwriteFileBytes('test 三', false, false,
          {"test 三": "61626364656620f09f8d89f09f8c8f2031"});
      testwriteFileBytes('test 三', true, false, {
        "test 三": "61626364656620f09f8d89f09f8c8f2031",
        _dupSuffix('test 三', 2): "61626364656620f09f8d89f09f8c8f2032",
        _dupSuffix('test 三', 3): "41424344"
      });
      testwriteFileBytes('test 三', true, true, {"test 三": "41424344"});

      _test('writeFileBytes (name updater)', (root) async {
        final r = root;

        // Add first.
        await env.writeFileBytes(r, '一 二.txt.png', _defStringContentsBytes,
            nameFinder: _testNameFinder);
        // Add second which triggers the name updater.
        var writeRes = await env.writeFileBytes(
            r, '一 二.txt.png', _defStringContentsBytes,
            nameFinder: _testNameFinder);
        var st = await env.stat(writeRes.path, false);
        expect(st!.name, 'NU-一 二.txt.png-false-1');
        expect(st.name, writeRes.fileName);
      });

      _test('stat and child (folder)', (root) async {
        final r = root;
        final newDir = await env.mkdirp(r, ['a', '一 二'].lock);
        final st = await env.stat(newDir, true);

        expect(st, isNotNull);
        expect(st!.isDir, true);
        expect(st.name, '一 二');
        expect(st.length, -1);

        final stAuto = await env.stat(newDir, null);
        expect(stAuto!.isDir, true);
        expect(stAuto.name, '一 二');
        expect(stAuto.length, -1);

        // `.child` with empty path should return the same stat.
        final stAudo2 = await env.child(newDir, <String>[].lock);
        _statEquals(st, stAudo2!);

        final st2 = await env.child(r, ['a', '一 二'].lock);
        _statEquals(st, st2!);

        final subPath = await env.directoryExists(r, ['a'].lock);
        final st3 = await env.child(subPath!, ['一 二'].lock);
        _statEquals(st, st3!);
      });

      _test('stat and child (file)', (root) async {
        final r = root;
        final newDir = await env.mkdirp(r, ['a', '一 二'].lock);
        final fileUri = (await env.writeFileBytes(
                newDir, 'test 仨.txt', _defStringContentsBytes))
            .path;
        final st = await env.stat(fileUri, false);

        expect(st, isNotNull);
        expect(st!.isDir, false);
        expect(st.name, 'test 仨.txt');
        expect(st.length, 15);

        final stAuto = await env.stat(fileUri, null);
        expect(stAuto!.isDir, false);
        expect(stAuto.name, 'test 仨.txt');
        expect(stAuto.length, 15);

        // `.child` with empty path should return the same stat.
        final stAudo2 = await env.child(fileUri, <String>[].lock);
        _statEquals(st, stAudo2!);

        final st2 = await env.child(r, ['a', '一 二', 'test 仨.txt'].lock);
        _statEquals(st, st2!);

        final subPath = await env.directoryExists(r, ['a', '一 二'].lock);
        final st3 = await env.child(subPath!, ['test 仨.txt'].lock);
        _statEquals(st, st3!);
      });

      _test('null stat for items that don\'t exist', (root) async {
        final r = root;
        final newDir = await env.mkdirp(r, ['a', '一 二'].lock);
        final fileUri = (await env.writeFileBytes(
                newDir, 'test 仨.txt', _defStringContentsBytes))
            .path;
        // Delete the created file to test null stat.
        await env.delete(fileUri, false);
        final st = await env.stat(fileUri, false);

        expect(st, isNull);
      });

      _test('stat, throws', (root) async {
        final r = root;
        final newDir = await env.mkdirp(r, ['a', '一 二'].lock);
        final fileUri = (await env.writeFileBytes(
                newDir, 'test 仨.txt', _defStringContentsBytes))
            .path;
        // Delete the created file to test null stat.
        await env.delete(fileUri, false);

        await expectLater(
            env.stat(fileUri, false, throws: true), throwsException);
      });

      _test('listDir', (root) async {
        final r = root;
        await _createNestedDir(env, r);

        final contents = await env.listDir(r);
        expect(_formatEntityList(contents),
            '[D|b]|[F|root.txt|1]|[F|root2.txt|1]|[D|一 二]');
      });

      _test('listDir recursively', (root) async {
        final r = root;
        await _createNestedDir(env, r);

        final contents = await env.listDir(r, recursive: true);
        expect(_formatEntityList(contents),
            '[F|a.txt|1]|[D|b]|[F|b.txt|1]|[F|c.txt|1]|[D|deep]|[F|root.txt|1]|[F|root2.txt|1]|[D|一 二]');
      });

      _test('listDir recursively with dirRelPath', (root) async {
        final r = root;
        await _createNestedDir(env, r);

        final contents =
            await env.listDir(r, recursive: true, relativePathInfo: true);
        expect(_formatEntityList(contents),
            '[F|a.txt|1|dir_rel: 一 二]|[D|b]|[F|b.txt|1|dir_rel: 一 二]|[F|c.txt|1|dir_rel: 一 二/deep]|[D|deep|dir_rel: 一 二]|[F|root.txt|1]|[F|root2.txt|1]|[D|一 二]');
      });

      _test('listDirContentFiles', (root) async {
        final r = root;
        await _createNestedDir(env, r);

        final contents = await env.listDirContentFiles(r);
        expect(await _formatPathInfoFileList(env, contents),
            '一 二/a.txt | 一 二/b.txt | 一 二/deep/c.txt | root.txt | root2.txt');
      });

      _test('rename (folder)', (root) async {
        final r = root;
        await env.mkdirp(r, ['a', '一 二'].lock);
        final newPath = await env.rename(await _getPath(env, r, 'a/一 二'), true,
            await _getPath(env, r, 'a'), 'test 仨 2.txt');
        final st = await env.stat(newPath, true);
        expect(st!.name, 'test 仨 2.txt');

        expect(await env.directoryToMap(r), {
          "a": {"test 仨 2.txt": {}}
        });
      });

      _test('rename (folder) (failed)', (root) async {
        final source = await env.mkdirp(root, ['一 二'].lock);
        await env.writeFileBytes(root, 'test 仨.txt', _defStringContentsBytes);
        await expectLater(
          env.rename(source, true, root, 'test 仨.txt'),
          throwsException,
        );
        expect(await env.directoryToMap(root),
            {"一 二": {}, "test 仨.txt": "61626364656620f09f8d89f09f8c8f"});
      });

      _test('rename (file)', (root) async {
        final r = root;
        final newDir = await env.mkdirp(r, ['a', '一 二'].lock);
        await env.writeFileBytes(newDir, 'test 仨.txt', _defStringContentsBytes);
        final newPath = await env.rename(
            await _getPath(env, r, 'a/一 二/test 仨.txt'),
            false,
            await _getPath(env, r, 'a/一 二'),
            'test 仨 2.txt');
        final st = await env.stat(newPath, false);
        expect(st!.name, 'test 仨 2.txt');

        expect(await env.directoryToMap(r), {
          "a": {
            "一 二": {"test 仨 2.txt": "61626364656620f09f8d89f09f8c8f"}
          }
        });
      });

      _test('rename (file) (failed)', (root) async {
        await env.mkdirp(root, ['test 仨 2.txt'].lock);
        final source = await env.writeFileBytes(
            root, 'test 仨.txt', _defStringContentsBytes);
        await expectLater(
          env.rename(source.path, false, root, 'test 仨 2.txt'),
          throwsException,
        );
        expect(await env.directoryToMap(root), {
          "test 仨.txt": "61626364656620f09f8d89f09f8c8f",
          "test 仨 2.txt": {}
        });
      });

      _test('Move folder', (root) async {
        final e = env;
        final r = root;

        // Move move/a to move/b
        await e.mkdirp(r, ['move', 'a'].lock);
        await e.mkdirp(r, ['move', 'b'].lock);
        final srcDir = await _getPath(e, r, 'move/a');
        final destDir = await _getPath(e, r, 'move/b');

        // Create some files and dirs for each dir.
        await _createFile(e, srcDir, 'file1', [1]);
        await _createFile(e, destDir, 'file2', [2]);
        await _createFolderWithDefFile(e, srcDir, 'a_sub');
        await _createFolderWithDefFile(e, destDir, 'b_sub');

        final newPath = await e.moveToDir(await _getPath(e, r, 'move/a'), true,
            await _getPath(e, r, 'move'), await _getPath(e, r, 'move/b'));
        final st = await e.stat(newPath.path, true);
        expect(st!.name, 'a');
        expect(st.name, newPath.fileName);

        expect(await e.directoryToMap(r), {
          "move": {
            "b": {
              "file2": "02",
              "b_sub": {"content.bin": "61626364656620f09f8d89f09f8c8f"},
              "a": {
                "file1": "01",
                "a_sub": {"content.bin": "61626364656620f09f8d89f09f8c8f"}
              }
            }
          }
        });
      });

      _test('Move folder (file conflict)', (root) async {
        final e = env;
        final r = root;

        // Move move/a to move/b
        await e.mkdirp(r, ['move', 'a'].lock);
        await e.mkdirp(r, ['move', 'b'].lock);
        final srcDir = await _getPath(e, r, 'move/a');
        final destDir = await _getPath(e, r, 'move/b');

        // Create some files and dirs for each dir.
        await _createFile(e, srcDir, 'file1', [1]);
        await _createFile(e, destDir, 'file2', [2]);
        await _createFolderWithDefFile(e, srcDir, 'a_sub');
        await _createFolderWithDefFile(e, destDir, 'b_sub');

        // Create a conflict.
        await _createFile(e, destDir, 'a', [1, 2, 3]);

        final newPath = await e.moveToDir(await _getPath(e, r, 'move/a'), true,
            await _getPath(e, r, 'move'), await _getPath(e, r, 'move/b'));
        final st = await e.stat(newPath.path, false);
        expect(st!.name, _dupSuffix('a', 2));
        expect(st.name, newPath.fileName);

        expect(await e.directoryToMap(r), {
          "move": {
            "b": {
              "a": "010203",
              "file2": "02",
              "b_sub": {"content.bin": "61626364656620f09f8d89f09f8c8f"},
              "a (1)": {
                "file1": "01",
                "a_sub": {"content.bin": "61626364656620f09f8d89f09f8c8f"}
              }
            }
          }
        });
      });

      _test('Move folder (folder conflict)', (root) async {
        final e = env;
        final r = root;

        // Move move/a to move/b
        await e.mkdirp(r, ['move', 'a'].lock);
        await e.mkdirp(r, ['move', 'b'].lock);
        final srcDir = await _getPath(e, r, 'move/a');
        final destDir = await _getPath(e, r, 'move/b');

        // Create some files and dirs for each dir.
        await _createFile(e, srcDir, 'file1', [1]);
        await _createFile(e, destDir, 'file2', [2]);
        await _createFolderWithDefFile(e, srcDir, 'a_sub');
        await _createFolderWithDefFile(e, destDir, 'b_sub');

        // Create a conflict.
        await e.mkdirp(r, ['move', 'b', 'a'].lock);
        await _createFile(e, await _getPath(e, r, 'move/b/a'), 'z', [4, 5]);

        final newPath = await e.moveToDir(await _getPath(e, r, 'move/a'), true,
            await _getPath(e, r, 'move'), await _getPath(e, r, 'move/b'));
        final st = await e.stat(newPath.path, true);
        expect(st!.name, 'a (1)');
        expect(st.name, newPath.fileName);

        expect(await e.directoryToMap(r), {
          "move": {
            "b": {
              "file2": "02",
              "a": {"z": "0405"},
              "b_sub": {"content.bin": "61626364656620f09f8d89f09f8c8f"},
              "a (1)": {
                "file1": "01",
                "a_sub": {"content.bin": "61626364656620f09f8d89f09f8c8f"}
              }
            }
          }
        });
      });

      _test('Move file', (root) async {
        final e = env;
        final r = root;

        // Move move/a to move/b
        await e.mkdirp(r, ['move', 'b'].lock);
        await _createFile(e, await _getPath(e, r, 'move'), 'a', [100]);
        final destDir = await _getPath(e, r, 'move/b');

        // Create some files and dirs for each dir.
        await _createFile(e, destDir, 'file2', [2]);
        await _createFolderWithDefFile(e, destDir, 'b_sub');

        final newPath = await e.moveToDir(await _getPath(e, r, 'move/a'), false,
            await _getPath(e, r, 'move'), await _getPath(e, r, 'move/b'));
        final st = await e.stat(newPath.path, false);
        expect(st!.name, 'a');
        expect(st.name, newPath.fileName);

        expect(await e.directoryToMap(r), {
          "move": {
            "b": {
              "a": "64",
              "file2": "02",
              "b_sub": {"content.bin": "61626364656620f09f8d89f09f8c8f"}
            }
          }
        });
      });

      _test('Move file (folder conflict)', (root) async {
        final e = env;
        final r = root;

        // Move move/a to move/b
        await e.mkdirp(r, ['move', 'b'].lock);
        await _createFile(e, await _getPath(e, r, 'move'), 'a', [65]);
        final destDir = await _getPath(e, r, 'move/b');

        // Create some files and dirs for each dir.
        await _createFile(e, destDir, 'file2', [2]);
        await _createFolderWithDefFile(e, destDir, 'b_sub');

        // Create a conflict.
        await e.mkdirp(r, ['move', 'b', 'a'].lock);
        await _createFile(e, await _getPath(e, r, 'move/b/a'), 'z', [4, 5]);

        final newPath = await e.moveToDir(await _getPath(e, r, 'move/a'), false,
            await _getPath(e, r, 'move'), await _getPath(e, r, 'move/b'));
        final st = await e.stat(newPath.path, false);
        expect(st!.name, 'a (1)');
        expect(st.name, newPath.fileName);

        expect(await e.directoryToMap(r), {
          "move": {
            "b": {
              "file2": "02",
              "a (1)": "41",
              "a": {"z": "0405"},
              "b_sub": {"content.bin": "61626364656620f09f8d89f09f8c8f"}
            }
          }
        });
      });

      _test('Move file (file conflict)', (root) async {
        final e = env;
        final r = root;

        // Move move/a to move/b
        await e.mkdirp(r, ['move', 'b'].lock);
        await _createFile(e, await _getPath(e, r, 'move'), 'a', [65]);
        final destDir = await _getPath(e, r, 'move/b');

        // Create some files and dirs for each dir.
        await _createFile(e, destDir, 'file2', [2]);
        await _createFolderWithDefFile(e, destDir, 'b_sub');

        // Create a conflict.
        await _createFile(e, destDir, 'a', [4, 5, 6]);

        final newPath = await e.moveToDir(await _getPath(e, r, 'move/a'), false,
            await _getPath(e, r, 'move'), await _getPath(e, r, 'move/b'));
        final st = await e.stat(newPath.path, false);
        expect(st!.name, 'a (1)');
        expect(st.name, newPath.fileName);

        expect(await e.directoryToMap(r), {
          "move": {
            "b": {
              "a": "040506",
              "a (1)": "41",
              "file2": "02",
              "b_sub": {"content.bin": "61626364656620f09f8d89f09f8c8f"}
            }
          }
        });
      });

      _test('Move and replace file (no conflict)', (root) async {
        final e = env;
        final r = root;

        // Move move/a to move/b
        await e.mkdirp(r, ['move', 'b'].lock);
        await _createFile(e, await _getPath(e, r, 'move'), 'a', [65]);
        final destDir = await _getPath(e, r, 'move/b');

        // Create some files and dirs for each dir.
        await _createFile(e, destDir, 'file2', [2]);
        await _createFolderWithDefFile(e, destDir, 'b_sub');

        final newPath = await e.moveToDir(await _getPath(e, r, 'move/a'), false,
            await _getPath(e, r, 'move'), await _getPath(e, r, 'move/b'),
            overwrite: true);
        final st = await e.stat(newPath.path, false);
        expect(st!.name, 'a');
        expect(st.name, newPath.fileName);

        expect(await e.directoryToMap(r), {
          "move": {
            "b": {
              "a": "41",
              "file2": "02",
              "b_sub": {"content.bin": "61626364656620f09f8d89f09f8c8f"}
            }
          }
        });
      });

      _test('Move and replace file (with conflict)', (root) async {
        final e = env;
        final r = root;

        // Move move/a to move/b
        await e.mkdirp(r, ['move', 'b'].lock);
        await _createFile(e, await _getPath(e, r, 'move'), 'a', [65]);
        final destDir = await _getPath(e, r, 'move/b');

        // Create some files and dirs for each dir.
        await _createFile(e, destDir, 'file2', [2]);
        await _createFolderWithDefFile(e, destDir, 'b_sub');

        // Create a conflict.
        await _createFile(e, destDir, 'a', [1, 2, 3]);

        final newPath = await e.moveToDir(await _getPath(e, r, 'move/a'), false,
            await _getPath(e, r, 'move'), await _getPath(e, r, 'move/b'),
            overwrite: true);
        final st = await e.stat(newPath.path, false);
        expect(st!.name, 'a');
        expect(st.name, newPath.fileName);

        expect(await e.directoryToMap(r), {
          "move": {
            "b": {
              "a": "41",
              "file2": "02",
              "b_sub": {"content.bin": "61626364656620f09f8d89f09f8c8f"}
            }
          }
        });
      });

      if (target.supportsInjectedMoveFailure) {
        _test('Move and replace restores destination after failure',
            (root) async {
          final r = root;
          final failingEnv = _FailingMoveLocalEnv();
          final srcDir = await failingEnv.mkdirp(r, ['source'].lock);
          final destDir = await failingEnv.mkdirp(r, ['dest'].lock);
          await failingEnv.writeFileBytes(
            srcDir,
            'same.txt',
            Uint8List.fromList([1]),
          );
          await failingEnv.writeFileBytes(
            destDir,
            'same.txt',
            Uint8List.fromList([2]),
          );

          final source = await failingEnv.child(srcDir, ['same.txt'].lock);
          await expectLater(
            failingEnv.moveToDir(source!.path, false, srcDir, destDir,
                overwrite: true),
            throwsA(isA<Exception>().having(
              (error) => error.toString(),
              'message',
              contains('Injected move failure'),
            )),
          );
          expect(await failingEnv.directoryToMap(r), {
            'source': {'same.txt': '01'},
            'dest': {'same.txt': '02'},
          });
        });
      }

      for (final (sourceIsDir, destinationIsDir) in [
        (true, true),
        (true, false),
        (false, true)
      ]) {
        _test(
            'Move and replace ${sourceIsDir ? 'folder' : 'file'} over ${destinationIsDir ? 'folder' : 'file'}',
            (root) async {
          final sourceParent = await env.mkdirp(root, ['source'].lock);
          final destinationParent =
              await env.mkdirp(root, ['destination'].lock);
          final BFPath source;
          if (sourceIsDir) {
            source = await env.mkdirp(sourceParent, ['same'].lock);
            await env.writeFileBytes(
                source, 'new.bin', Uint8List.fromList([1]));
          } else {
            source = (await env.writeFileBytes(
                    sourceParent, 'same', Uint8List.fromList([1])))
                .path;
          }
          if (destinationIsDir) {
            final oldDirectory =
                await env.mkdirp(destinationParent, ['same', 'nested'].lock);
            await env.writeFileBytes(
                oldDirectory, 'old.bin', Uint8List.fromList([2]));
          } else {
            await env.writeFileBytes(
                destinationParent, 'same', Uint8List.fromList([2]));
          }
          await env.writeFileBytes(
              destinationParent, 'keep.bin', Uint8List.fromList([3]));
          final result = await env.moveToDir(
              source, sourceIsDir, sourceParent, destinationParent,
              overwrite: true);
          expect(result.fileName, 'same');
          final stat = await env.stat(result.path, sourceIsDir);
          expect(stat!.isDir, sourceIsDir);
          expect(await env.child(sourceParent, ['same'].lock), isNull);
          expect(await env.directoryToMap(root), {
            'source': {},
            'destination': {
              'same': sourceIsDir ? {'new.bin': '01'} : '01',
              'keep.bin': '03'
            },
          });
        });
      }

      _test('nextAvailableFile', (root) async {
        final r = root;
        await _createFile(env, r, 'a 二', [1]);
        var name = await BFNameFinder.instance.findFileName(
          env,
          r,
          'a 二',
          false,
        );
        expect(name, 'a 二 (1)');

        name = await BFNameFinder.instance.findFileName(
          env,
          r,
          'b',
          false,
        );
        expect(name, 'b');
        await _createFile(env, r, 'b', [2]);

        name = await BFNameFinder.instance.findFileName(
          env,
          r,
          'b',
          false,
        );
        expect(name, 'b (1)');
      });

      _test('nextAvailableFile (extension)', (root) async {
        final r = root;
        await _createFile(env, r, 'a 二.zz', [1]);
        var name = await BFNameFinder.instance.findFileName(
          env,
          r,
          'a 二.zz',
          false,
        );
        expect(name, 'a 二 (1).zz');

        name = await BFNameFinder.instance.findFileName(
          env,
          r,
          'b.zz',
          false,
        );
        expect(name, 'b.zz');
        await _createFile(env, r, 'b.zz', [2]);

        name = await BFNameFinder.instance.findFileName(
          env,
          r,
          'b.zz',
          false,
        );
        expect(name, 'b (1).zz');
      });

      _test('nextAvailableFile (folder with extension)', (root) async {
        final r = root;
        await env.mkdirp(r, ['a 二.zz'].lock);
        var name = await BFNameFinder.instance.findFileName(
          env,
          r,
          'a 二.zz',
          true,
        );
        expect(name, 'a 二.zz (1)');

        name = await BFNameFinder.instance.findFileName(
          env,
          r,
          'b.zz',
          true,
        );
        expect(name, 'b.zz');
        await env.mkdirp(r, ['b.zz'].lock);

        name = await BFNameFinder.instance.findFileName(
          env,
          r,
          'b.zz',
          true,
        );
        expect(name, 'b.zz (1)');
      });

      _test('nextAvailableFile (custom name updater)', (root) async {
        // ignore: prefer_function_declarations_over_variables
        final nameUpdater = BFCustomNameFinder(
            (String name, bool isDir, int count) => '$name -> $count');
        final r = root;
        await _createFile(env, r, 'a 二.zz.abc', [1]);
        var name = await nameUpdater.findFileName(env, r, 'a 二.zz.abc', false);
        expect(name, 'a 二.zz.abc -> 1');

        name = await nameUpdater.findFileName(env, r, 'b.zz.abc', false);
        expect(name, 'b.zz.abc');
        await _createFile(env, r, 'b.zz.abc', [2]);

        name = await nameUpdater.findFileName(env, r, 'b.zz.abc', false);
        expect(name, 'b.zz.abc -> 1');
      });

      _test('nextAvailableFile (registry)', (root) async {
        final r = root;
        await _createFile(env, r, 'a 二', [1]);
        final name = await BFNameFinder.instance.findFileName(
          env,
          r,
          'a 二',
          false,
          pendingNames: {'a 二', 'a 二 (1)'},
        );
        expect(name, 'a 二 (2)');

        final reservedNames = <String>{};
        final concurrentNames = await Future.wait([
          BFNameFinder.instance.findFileName(
            env,
            r,
            'reserved.txt',
            false,
            pendingNames: reservedNames,
          ),
          BFNameFinder.instance.findFileName(
            env,
            r,
            'reserved.txt',
            false,
            pendingNames: reservedNames,
          ),
        ]);
        expect(concurrentNames.toSet().length, 2);
        expect(
          concurrentNames.toSet().containsAll(
            {'reserved.txt', 'reserved (1).txt'},
          ),
          true,
        );
      });

      _test('BFSerialQueue', (root) async {
        final r = root;
        final queue = BFSerialQueue();
        for (var i = 0; i < 10; i++) {
          queue.queue((_) async {
            await _createFile(env, r, 'a.txt', [i]);
          });
        }
        await queue.drain();

        expect(await env.directoryToMap(r), {
          "a (1).txt": "01",
          "a (6).txt": "06",
          "a (7).txt": "07",
          "a (8).txt": "08",
          "a (4).txt": "04",
          "a (5).txt": "05",
          "a.txt": "00",
          "a (9).txt": "09",
          "a (2).txt": "02",
          "a (3).txt": "03"
        });
      });

      _test('BFSerialQueue with `queueAndWait`', (root) async {
        final r = root;
        final queue = BFSerialQueue();
        for (var i = 0; i < 10; i++) {
          await queue.queueAndWait((_) async {
            await _createFile(env, r, 'a.txt', [i]);
          });
        }

        // With `queueAndWait`, we don't need to call drain explicitly.
        // await queue.drain();

        expect(await env.directoryToMap(r), {
          "a (1).txt": "01",
          "a (6).txt": "06",
          "a (7).txt": "07",
          "a (8).txt": "08",
          "a (4).txt": "04",
          "a (5).txt": "05",
          "a.txt": "00",
          "a (9).txt": "09",
          "a (2).txt": "02",
          "a (3).txt": "03"
        });
      });

      _test('BFSerialQueue with error', (root) async {
        final r = root;
        final queue = BFSerialQueue();
        for (var i = 0; i < 10; i++) {
          queue.queue((_) async {
            if (i == 5) {
              throw Exception('Test error');
            }
            await _createFile(env, r, 'a.txt', [i]);
          });
        }
        await expectLater(
            queue.drain(),
            throwsA(isA<Exception>().having(
              (error) => error.toString(),
              'message',
              contains('Test error'),
            )));
        expect(await env.directoryToMap(r), {
          "a (1).txt": "01",
          "a (2).txt": "02",
          "a (3).txt": "03",
          "a.txt": "00",
          "a (4).txt": "04",
        });
      });
    }, skip: skip);
  }

  void _statEquals(BFEntity st, BFEntity st2) {
    expect(st.isDir, st2.isDir);
    expect(st.name, st2.name);
    expect(st.length, st2.length);
    expect(st.path, st2.path);
    expect(st.lastMod, st2.lastMod);
  }

  Future<void> _checkManyChunks(BFEnv e, BFPath path, String prefix) async {
    final bytes = await e.readFileBytes(path);
    final str = utf8.decode(bytes);
    final sb = StringBuffer();
    for (var i = 0; i < 50; i++) {
      sb.write('$prefix $i');
    }
    final expected = sb.toString();
    if (str != expected) {
      throw Exception('Unexpected content: $str');
    }
  }

  Future<BFEntity> _getStat(BFEnv e, BFPath root, String relPath) async {
    final stat = await e.child(root, _genRelPath(relPath));
    if (stat == null) {
      throw Exception('stat is null for "$relPath"');
    }
    return stat;
  }

  Future<BFPath> _getPath(BFEnv e, BFPath root, String relPath) async {
    final stat = await _getStat(e, root, relPath);
    return stat.path;
  }

  Future<BFPath> _createFile(
      BFEnv e, BFPath dir, String fileName, List<int> content) async {
    final res =
        await e.writeFileBytes(dir, fileName, Uint8List.fromList(content));
    return res.path;
  }

  Future<BFPath> _createFolderWithDefFile(
      BFEnv e, BFPath root, String folderName) async {
    final dirPath = await e.mkdirp(root, [folderName].lock);
    await _createFile(
        e, dirPath, _defFolderContentFile, _defStringContentsBytes);
    return dirPath;
  }

  IList<String> _genRelPath(String relPath) {
    return relPath.split('/').lock;
  }
}

final _testNameFinder =
    BFCustomNameFinder((String fileName, bool isDir, int attempt) {
  return 'NU-$fileName-$isDir-$attempt';
});

extension BFOutStreamExtension on BFOutStream {
  Future<void> writeManyChunks(String prefix) async {
    for (var i = 0; i < 50; i++) {
      await write(Uint8List.fromList('$prefix $i'.codeUnits));
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    await close();
  }
}
