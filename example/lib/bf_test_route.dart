import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:example/ntr/ntr_suite.dart';
import 'package:example/util/fc_file_picker_util_bf_ext.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:fc_file_picker_util/fc_file_picker_util.dart';
import 'package:bull_fs/bull_fs.dart';
import 'package:fc_material_alert/fc_material_alert.dart';
import 'package:flutter/material.dart';
import 'package:tmp_path/tmp_path.dart';
import 'package:path/path.dart' as p;

const _defFolderContentFile = 'content.bin';
const _defStringContents = 'abcdef 🍉🌏';
final _defStringContentsBytes = utf8.encode(_defStringContents);

class BFTestRoute extends StatefulWidget {
  const BFTestRoute({super.key});

  @override
  State<BFTestRoute> createState() => _BFTestRouteState();
}

class _BFTestRouteState extends State<BFTestRoute> {
  var _env = '';
  var _output = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text('BullFS tests'),
        ),
        body: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: <Widget>[
              OutlinedButton(
                  onPressed: _startLocal, child: const Text('Run local env')),
              if (!Platform.isWindows) ...[
                const SizedBox(
                  height: 10,
                ),
                OutlinedButton(
                    onPressed: _startNative,
                    child: const Text('Run native env'))
              ],
              const SizedBox(
                height: 10,
              ),
              Text(_env),
              const SizedBox(
                height: 10,
              ),
              SelectableText(_output),
              const SizedBox(
                height: 10,
              ),
            ],
          ),
        ));
  }

  Future<void> _startLocal() async {
    final t = tmpPath();
    await Directory(t).create(recursive: true);
    await _runTests(BFEnvLocal(), BFLocalPath(t));
  }

  Future<void> _startNative() async {
    FcFilePickerXResult? rootRaw = await FcFilePickerUtil.pickFolder();
    if (rootRaw == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    final bfRes = await rootRaw.resolveBFPath(macosIcloud: true);
    final env = bfRes.env;
    final appleResScope = AppleResScope(env);
    try {
      await appleResScope.requestAccess(bfRes.path);
      await _runTests(env, bfRes.path);
    } finally {
      await appleResScope.release();
    }
  }

  Future<void> _runTests(BFEnv env, BFPath root) async {
    final isEmpty = (await env.listDir(root)).isEmpty;
    if (!isEmpty) {
      throw Exception('Folder must be empty');
    }

    setState(() {
      _output = 'Running...';
    });

    UpdatedBFPath? cleanUpPath;
    try {
      // Local env.
      final localDir = tmpPath();
      await Directory(localDir).create(recursive: true);
      setState(() {
        _env = 'Local';
      });
      await _runEnvTests('Local', BFEnvLocal(), BFLocalPath(localDir));
      if (env.envType() != BFEnvType.local) {
        // Native env.
        cleanUpPath = await env.ensureDir(root, 'native');
        setState(() {
          _env = 'Native';
        });
        await _runEnvTests('Native', env, cleanUpPath.path);
      }

      setState(() {
        _output = 'Done';
      });
    } catch (e) {
      setState(() {
        _output = 'Failed: $e';
      });
    } finally {
      // Clean up.
      if (cleanUpPath != null) {
        await env.deletePathIfExists(root);
      }
    }
  }

  String _dupSuffix(String fileName, int c) {
    final ext = p.extension(fileName);
    final name = p.basenameWithoutExtension(fileName);
    return '$name (${c - 1})$ext';
  }

  Future<void> _createNestedDir(BFEnv env, BFPath r) async {
    final subDir1 = await env.ensureDir(r, '一 二');
    await env.slowWriteFileBytes(
        subDir1.path, 'a.txt', Uint8List.fromList([1]));
    await env.slowWriteFileBytes(
        subDir1.path, 'b.txt', Uint8List.fromList([2]));

    // b is empty.
    await env.ensureDir(r, 'b');

    final subDir11 = await env.ensureDir(subDir1.path, 'deep');
    await env.slowWriteFileBytes(
        subDir11.path, 'c.txt', Uint8List.fromList([3]));

    await env.slowWriteFileBytes(r, 'root.txt', Uint8List.fromList([4]));
    await env.slowWriteFileBytes(r, 'root2.txt', Uint8List.fromList([5]));
  }

  String _formatEntityList(List<BFEntity> list) {
    list.sort((a, b) => a.name.compareTo(b.name));
    return list.map((e) => e.toStringWithLength()).join('|');
  }

  Future<String> _formatPathInfoList(
      BFEnv env, List<BFPathAndDirRelPath> list) async {
    final entities = await Future.wait(list.map((e) async {
      final st = await env.stat(e.path);
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

  Future<void> _runEnvTests(String name, BFEnv env, BFPath root) async {
    final ns = NTRSuite(suiteName: name);

    int testCount = 0;
    ns.onLog = (s) => setState(() {
          _output = s;
        });
    ns.beforeAll = () async {
      testCount++;
      // Create a new folder for each test.
      final dirUri = await env.ensureDir(root, 'test_$testCount');
      return dirUri.path;
    };
    ns.afterAll = (h) async {
      final r = h.data as BFPath;
      await env.deletePathIfExists(r);
    };

    ns.add('ensureDir', (h) async {
      final r = h.data as BFPath;
      await env.ensureDir(r, 'space 一 二 三');

      // Do it twice and there should be no error.
      final newDir = await env.ensureDir(r, 'space 一 二 三');

      // Test return value.
      final st = await env.stat(newDir.path);
      h.notNull(st);
      h.equals(st!.isDir, true);
      h.equals(st.name, 'space 一 二 三');

      h.mapEquals(await env.directoryToMap(r), {"space 一 二 三": {}});
    });

    ns.add('ensureDir (failed)', (h) async {
      final r = h.data as BFPath;
      try {
        await env.slowWriteFileBytes(r, 'space 一 二 三', Uint8List.fromList([1]));
        await env.ensureDir(r, 'space 一 二 三');
        throw Error();
      } on Exception catch (_) {
        h.mapEquals(await env.directoryToMap(r), {"space 一 二 三": "01"});
      }
    });

    ns.add('ensureDirs', (h) async {
      final r = h.data as BFPath;
      final newDir = await env.ensureDirs(r, ['space 一 二 三', '22'].lock);
      // Test return value.
      var st = await env.stat(newDir.path);
      h.notNull(st);
      h.equals(st!.isDir, true);
      h.equals(st.name, '22');

      // Do it again with a new subdir.
      await env.ensureDirs(r, ['space 一 二 三', '22', '3 33'].lock);

      // Do it again.
      await env.ensureDirs(r, ['space 一 二 三', '22', '3 33'].lock);

      h.mapEquals(await env.directoryToMap(r), {
        "space 一 二 三": {
          "22": {"3 33": {}}
        }
      });
    });

    ns.add('ensureDirs (failed)', (h) async {
      final r = h.data as BFPath;
      try {
        await env.ensureDirs(r, ['space 一 二 三', '22', '3 33'].lock);
        await env.slowWriteFileBytes(
            (await env.statPath(r, relPath: ['space 一 二 三', '22'].lock))!,
            'file',
            Uint8List.fromList([1]));
        await env.ensureDirs(r, ['space 一 二 三', '22', 'file', 'another'].lock);
        throw Error();
      } on Exception catch (_) {
        h.mapEquals(await env.directoryToMap(r), {
          "space 一 二 三": {
            "22": {"file": "01", "3 33": {}}
          }
        });
      }
    });

    ns.add('ensureDirsForFile', (h) async {
      final r = h.data as BFPath;
      final newDir =
          await env.ensureDirsForFile(r, ['space 一 二 三', '22', 'a.txt'].lock);
      // Test return value.
      var st = await env.stat(newDir.path);
      h.notNull(st);
      h.equals(st!.isDir, true);
      h.equals(st.name, '22');

      h.mapEquals(await env.directoryToMap(r), {
        "space 一 二 三": {"22": {}}
      });
    });

    ns.add('ensureDirsForFile (just return)', (h) async {
      final r = h.data as BFPath;
      final dir1 = await env.ensureDirs(r, ['space 一 二 三', '22'].lock);
      final dir2 = await env.ensureDirsForFile(dir1.path, ['a.txt'].lock);

      // Test return value.
      var st = await env.stat(dir2.path);
      h.notNull(st);
      h.equals(st!.isDir, true);
      h.equals(st.name, '22');

      h.mapEquals(await env.directoryToMap(r), {
        "space 一 二 三": {"22": {}}
      });
    });

    if (env.hasStreamSupport()) {
      void testWriteFileStream(
          String fileName, bool multiple, Map<String, dynamic> fs) {
        ns.add('writeFileStream $fileName multiple: $multiple', (h) async {
          final r = h.data as BFPath;
          var outStream = await env.writeFileStream(r, fileName);
          await outStream.write(Uint8List.fromList(utf8.encode('abc1')));
          await outStream.write(_defStringContentsBytes);
          await outStream.flush();
          await outStream.close();

          // Test `getPath`.
          var destUri = outStream.getPath();
          var destUriStat = await env.stat(destUri);
          h.notNull(destUriStat);
          h.equals(destUriStat!.isDir, false);
          h.equals(destUriStat.name, fileName);
          if (multiple) {
            // Write to the same file again.
            outStream = await env.writeFileStream(r, fileName);
            await outStream.write(Uint8List.fromList(utf8.encode('abc2')));
            await outStream.write(_defStringContentsBytes);
            await outStream.flush();
            await outStream.close();

            // Test `getPath`.
            destUri = outStream.getPath();
            destUriStat = await env.stat(destUri);
            h.notNull(destUriStat);
            h.equals(destUriStat!.isDir, false);
            h.equals(destUriStat.name, _dupSuffix(fileName, 2));

            // Write to the same file again.
            outStream = await env.writeFileStream(r, fileName);
            await outStream.write(Uint8List.fromList(utf8.encode('abc3')));
            await outStream.write(_defStringContentsBytes);
            await outStream.flush();
            await outStream.close();

            // Test `getPath`.
            destUri = outStream.getPath();
            destUriStat = await env.stat(destUri);
            h.notNull(destUriStat);
            h.equals(destUriStat!.isDir, false);
          }

          h.mapEquals(await env.directoryToMap(r), fs);
        });
      }

      // Known extension.
      testWriteFileStream('test 三.txt', false,
          {"test 三.txt": "6162633161626364656620f09f8d89f09f8c8f"});
      testWriteFileStream('test 三.txt', true, {
        _dupSuffix('test 三.txt', 2): "6162633261626364656620f09f8d89f09f8c8f",
        "test 三.txt": "6162633161626364656620f09f8d89f09f8c8f",
        _dupSuffix('test 三.txt', 3): "6162633361626364656620f09f8d89f09f8c8f"
      });
      // Unknown extension.
      testWriteFileStream('test 三.elephant', false,
          {"test 三.elephant": "6162633161626364656620f09f8d89f09f8c8f"});
      testWriteFileStream('test 三.elephant', true, {
        _dupSuffix('test 三.elephant', 2):
            "6162633261626364656620f09f8d89f09f8c8f",
        "test 三.elephant": "6162633161626364656620f09f8d89f09f8c8f",
        _dupSuffix('test 三.elephant', 3):
            "6162633361626364656620f09f8d89f09f8c8f"
      });
      // Multiple extensions.
      testWriteFileStream('test 三.elephant.xyz', false,
          {"test 三.elephant.xyz": "6162633161626364656620f09f8d89f09f8c8f"});
      testWriteFileStream('test 三.elephant.xyz', true, {
        _dupSuffix('test 三.elephant.xyz', 2):
            "6162633261626364656620f09f8d89f09f8c8f",
        "test 三.elephant.xyz": "6162633161626364656620f09f8d89f09f8c8f",
        _dupSuffix('test 三.elephant.xyz', 3):
            "6162633361626364656620f09f8d89f09f8c8f"
      });
      // No extension.
      testWriteFileStream('test 三', false,
          {"test 三": "6162633161626364656620f09f8d89f09f8c8f"});
      testWriteFileStream('test 三', true, {
        "test 三": "6162633161626364656620f09f8d89f09f8c8f",
        _dupSuffix('test 三', 2): "6162633261626364656620f09f8d89f09f8c8f",
        _dupSuffix('test 三', 3): "6162633361626364656620f09f8d89f09f8c8f"
      });

      ns.add('readFileStream', (h) async {
        final r = h.data as BFPath;
        final tmpFile = tmpPath();
        await File(tmpFile).writeAsString(_defStringContents);
        final pasteRes = await env.pasteLocalFile(tmpFile, r, 'test.txt');

        final stream = await env.readFileStream(pasteRes.path);
        final bytes = await stream.fold<List<int>>([], (prev, element) {
          prev.addAll(element);
          return prev;
        });
        h.equals(utf8.decode(bytes), _defStringContents);

        h.mapEquals(await env.directoryToMap(r),
            {"test.txt": "61626364656620f09f8d89f09f8c8f"});
      });
    }

    ns.add('copyToLocalFile', (h) async {
      final r = h.data as BFPath;
      final tmpFile = tmpPath();
      await File(tmpFile).writeAsString(_defStringContents);
      final pasteRes = await env.pasteLocalFile(tmpFile, r, 'test.txt');

      final tmpFile2 = tmpPath();
      await env.copyToLocalFile(pasteRes.path, tmpFile2);
      h.equals(await File(tmpFile2).readAsString(), _defStringContents);

      h.mapEquals(await env.directoryToMap(r),
          {"test.txt": "61626364656620f09f8d89f09f8c8f"});
    });

    void testPasteToLocalFile(
        String fileName, bool multiple, Map<String, dynamic> fs) {
      ns.add('pasteLocalFile  $fileName multiple: $multiple', (h) async {
        final r = h.data as BFPath;
        final tmpFile = tmpPath();
        await File(tmpFile).writeAsString('$_defStringContents 1');
        // Add first test.txt
        var pasteRes = await env.pasteLocalFile(tmpFile, r, fileName);
        var st = await env.stat(pasteRes.path);
        h.equals(st!.name, fileName);

        if (multiple) {
          // Add second test.txt
          await File(tmpFile).writeAsString('$_defStringContents 2');
          pasteRes = await env.pasteLocalFile(tmpFile, r, fileName);
          st = await env.stat(pasteRes.path);
          h.equals(st!.name, _dupSuffix(fileName, 2));

          // Add third test.txt
          await File(tmpFile).writeAsString('$_defStringContents 3');
          pasteRes = await env.pasteLocalFile(tmpFile, r, fileName);
          st = await env.stat(pasteRes.path);
          h.equals(st!.name, _dupSuffix(fileName, 3));
        }

        h.mapEquals(await env.directoryToMap(r), fs);
      });
    }

    // Known extension.
    testPasteToLocalFile('test 三.txt', false,
        {"test 三.txt": "61626364656620f09f8d89f09f8c8f2031"});
    testPasteToLocalFile('test 三.txt', true, {
      _dupSuffix('test 三.txt', 2): "61626364656620f09f8d89f09f8c8f2032",
      _dupSuffix('test 三.txt', 3): "61626364656620f09f8d89f09f8c8f2033",
      "test 三.txt": "61626364656620f09f8d89f09f8c8f2031"
    });
    // Unknown extension.
    testPasteToLocalFile('test 三.elephant', false,
        {"test 三.elephant": "61626364656620f09f8d89f09f8c8f2031"});
    testPasteToLocalFile('test 三.elephant', true, {
      _dupSuffix('test 三.elephant', 2): "61626364656620f09f8d89f09f8c8f2032",
      "test 三.elephant": "61626364656620f09f8d89f09f8c8f2031",
      _dupSuffix('test 三.elephant', 3): "61626364656620f09f8d89f09f8c8f2033"
    });
    // Multiple extensions.
    testPasteToLocalFile('test 三.elephant.xyz', false,
        {"test 三.elephant.xyz": "61626364656620f09f8d89f09f8c8f2031"});
    testPasteToLocalFile('test 三.elephant.xyz', true, {
      _dupSuffix('test 三.elephant.xyz', 2):
          "61626364656620f09f8d89f09f8c8f2032",
      "test 三.elephant.xyz": "61626364656620f09f8d89f09f8c8f2031",
      _dupSuffix('test 三.elephant.xyz', 3): "61626364656620f09f8d89f09f8c8f2033"
    });
    // No extension.
    testPasteToLocalFile(
        'test 三', false, {"test 三": "61626364656620f09f8d89f09f8c8f2031"});
    testPasteToLocalFile('test 三', true, {
      "test 三": "61626364656620f09f8d89f09f8c8f2031",
      _dupSuffix('test 三', 2): "61626364656620f09f8d89f09f8c8f2032",
      _dupSuffix('test 三', 3): "61626364656620f09f8d89f09f8c8f2033"
    });

    ns.add('stat (folder)', (h) async {
      final r = h.data as BFPath;
      final newDir = await env.ensureDirs(r, ['a', '一 二'].lock);
      final st = await env.stat(newDir.path);

      h.notNull(st);
      h.equals(st!.isDir, true);
      h.equals(st.name, '一 二');
      h.equals(st.length, -1);

      final st2 = await env.stat(r, relPath: ['a', '一 二'].lock);
      _statEquals(st, st2!);

      final subPath = await env.statPath(r, relPath: ['a'].lock);
      final st3 = await env.stat(subPath!, relPath: ['一 二'].lock);
      _statEquals(st, st3!);
    });

    ns.add('stat (file)', (h) async {
      final r = h.data as BFPath;
      final newDir = await env.ensureDirs(r, ['a', '一 二'].lock);
      final fileUri = await env.slowWriteFileBytes(
          newDir.path, 'test 仨.txt', _defStringContentsBytes);
      final st = await env.stat(fileUri);

      h.notNull(st);
      h.equals(st!.isDir, false);
      h.equals(st.name, 'test 仨.txt');
      h.equals(st.length, 15);

      final st2 = await env.stat(r, relPath: ['a', '一 二', 'test 仨.txt'].lock);
      _statEquals(st, st2!);

      final subPath = await env.statPath(r, relPath: ['a', '一 二'].lock);
      final st3 = await env.stat(subPath!, relPath: ['test 仨.txt'].lock);
      _statEquals(st, st3!);
    });

    ns.add('listDir', (h) async {
      final r = h.data as BFPath;
      await _createNestedDir(env, r);

      final contents = await env.listDir(r);
      h.equals(_formatEntityList(contents),
          '[D|b]|[F|root.txt|1]|[F|root2.txt|1]|[D|一 二]');
    });

    ns.add('listDir recursively', (h) async {
      final r = h.data as BFPath;
      await _createNestedDir(env, r);

      final contents = await env.listDir(r, recursive: true);
      h.equals(_formatEntityList(contents),
          '[F|a.txt|1]|[D|b]|[F|b.txt|1]|[F|c.txt|1]|[D|deep]|[F|root.txt|1]|[F|root2.txt|1]|[D|一 二]');
    });

    ns.add('listDir recursively with dirRelPath', (h) async {
      final r = h.data as BFPath;
      await _createNestedDir(env, r);

      final contents =
          await env.listDir(r, recursive: true, relativePathInfo: true);
      h.equals(_formatEntityList(contents),
          '[F|a.txt|1|dir_rel: 一 二]|[D|b]|[F|b.txt|1|dir_rel: 一 二]|[F|c.txt|1|dir_rel: 一 二/deep]|[D|deep|dir_rel: 一 二]|[F|root.txt|1]|[F|root2.txt|1]|[D|一 二]');
    });

    ns.add('listDirContentFiles', (h) async {
      final r = h.data as BFPath;
      await _createNestedDir(env, r);

      final contents = await env.listDirContentFiles(r);
      h.equals(await _formatPathInfoList(env, contents),
          '一 二/a.txt | 一 二/b.txt | 一 二/deep/c.txt | root.txt | root2.txt');
    });

    ns.add('rename (folder)', (h) async {
      final r = h.data as BFPath;
      await env.ensureDirs(r, ['a', '一 二'].lock);
      final newPath =
          await env.rename(r, _genRelPath('a/一 二'), 'test 仨 2.txt', true);
      final st = await env.stat(newPath.path);
      h.equals(st!.name, 'test 仨 2.txt');

      h.mapEquals(await env.directoryToMap(r), {
        "a": {"test 仨 2.txt": {}}
      });
    });

    ns.add('rename (folder) (failed)', (h) async {
      final r = h.data as BFPath;
      try {
        await env.ensureDirs(r, ['一 二'].lock);
        await env.slowWriteFileBytes(r, 'test 仨.txt', _defStringContentsBytes);

        await env.rename(r, _genRelPath('一 二'), 'test 仨.txt', true);
        throw Error();
      } on Exception catch (_) {
        h.mapEquals(await env.directoryToMap(r),
            {"一 二": {}, "test 仨.txt": "61626364656620f09f8d89f09f8c8f"});
      }
    });

    ns.add('rename (file)', (h) async {
      final r = h.data as BFPath;
      final newDir = await env.ensureDirs(r, ['a', '一 二'].lock);
      await env.slowWriteFileBytes(
          newDir.path, 'test 仨.txt', _defStringContentsBytes);
      final newPath = await env.rename(
          r, _genRelPath('a/一 二/test 仨.txt'), 'test 仨 2.txt', false);
      final st = await env.stat(newPath.path);
      h.equals(st!.name, 'test 仨 2.txt');

      h.mapEquals(await env.directoryToMap(r), {
        "a": {
          "一 二": {"test 仨 2.txt": "61626364656620f09f8d89f09f8c8f"}
        }
      });
    });

    ns.add('rename (file) (failed)', (h) async {
      final r = h.data as BFPath;
      try {
        await env.ensureDirs(r, ['test 仨 2.txt'].lock);

        await env.slowWriteFileBytes(r, 'test 仨.txt', _defStringContentsBytes);

        await env.rename(
            r, _genRelPath('test 仨 2.txt/test 仨.txt'), 'test 仨 2.txt', false);
        throw Error();
      } on Exception catch (_) {
        h.mapEquals(await env.directoryToMap(r), {
          "test 仨.txt": "61626364656620f09f8d89f09f8c8f",
          "test 仨 2.txt": {}
        });
      }
    });

    ns.add('Move folder', (h) async {
      final e = env;
      final r = h.data as BFPath;

      // Move move/a to move/b
      await e.ensureDirs(r, ['move', 'a'].lock);
      await e.ensureDirs(r, ['move', 'b'].lock);
      final srcDir = await _getPath(e, r, 'move/a');
      final destDir = await _getPath(e, r, 'move/b');

      // Create some files and dirs for each dir.
      await _createFile(e, srcDir, 'file1', [1]);
      await _createFile(e, destDir, 'file2', [2]);
      await _createFolderWithDefFile(e, srcDir, 'a_sub');
      await _createFolderWithDefFile(e, destDir, 'b_sub');

      final newPath = await e.moveToDir(
          r, _genRelPath('move/a'), _genRelPath('move/b'), true);
      final st = await e.stat(newPath.path);
      h.equals(st!.name, 'a');

      h.mapEquals(await e.directoryToMap(r), {
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

    ns.add('Move folder (file conflict)', (h) async {
      final e = env;
      final r = h.data as BFPath;

      // Move move/a to move/b
      await e.ensureDirs(r, ['move', 'a'].lock);
      await e.ensureDirs(r, ['move', 'b'].lock);
      final srcDir = await _getPath(e, r, 'move/a');
      final destDir = await _getPath(e, r, 'move/b');

      // Create some files and dirs for each dir.
      await _createFile(e, srcDir, 'file1', [1]);
      await _createFile(e, destDir, 'file2', [2]);
      await _createFolderWithDefFile(e, srcDir, 'a_sub');
      await _createFolderWithDefFile(e, destDir, 'b_sub');

      // Create a conflict.
      await _createFile(e, destDir, 'a', [1, 2, 3]);

      final newPath = await e.moveToDir(
          r, _genRelPath('move/a'), _genRelPath('move/b'), true);
      final st = await e.stat(newPath.path);
      h.equals(st!.name, _dupSuffix('a', 1));

      h.mapEquals(await e.directoryToMap(r), {
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

    ns.add('Move folder (folder conflict)', (h) async {
      final e = env;
      final r = h.data as BFPath;

      // Move move/a to move/b
      await e.ensureDirs(r, ['move', 'a'].lock);
      await e.ensureDirs(r, ['move', 'b'].lock);
      final srcDir = await _getPath(e, r, 'move/a');
      final destDir = await _getPath(e, r, 'move/b');

      // Create some files and dirs for each dir.
      await _createFile(e, srcDir, 'file1', [1]);
      await _createFile(e, destDir, 'file2', [2]);
      await _createFolderWithDefFile(e, srcDir, 'a_sub');
      await _createFolderWithDefFile(e, destDir, 'b_sub');

      // Create a conflict.
      await e.ensureDirs(r, ['move', 'b', 'a'].lock);
      await _createFile(e, await _getPath(e, r, 'move/b/a'), 'z', [4, 5]);

      final newPath = await e.moveToDir(
          r, _genRelPath('move/a'), _genRelPath('move/b'), true);
      final st = await e.stat(newPath.path);
      h.equals(st!.name, 'a (1)');

      h.mapEquals(await e.directoryToMap(r), {
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

    ns.add('Move file', (h) async {
      final e = env;
      final r = h.data as BFPath;

      // Move move/a to move/b
      await e.ensureDirs(r, ['move', 'b'].lock);
      await _createFile(e, await _getPath(e, r, 'move'), 'a', [100]);
      final destDir = await _getPath(e, r, 'move/b');

      // Create some files and dirs for each dir.
      await _createFile(e, destDir, 'file2', [2]);
      await _createFolderWithDefFile(e, destDir, 'b_sub');

      final newPath = await e.moveToDir(
          r, _genRelPath('move/a'), _genRelPath('move/b'), false);
      final st = await e.stat(newPath.path);
      h.equals(st!.name, 'a');

      h.mapEquals(await e.directoryToMap(r), {
        "move": {
          "b": {
            "a": "64",
            "file2": "02",
            "b_sub": {"content.bin": "61626364656620f09f8d89f09f8c8f"}
          }
        }
      });
    });

    ns.add('Move file (folder conflict)', (h) async {
      final e = env;
      final r = h.data as BFPath;

      // Move move/a to move/b
      await e.ensureDirs(r, ['move', 'b'].lock);
      await _createFile(e, await _getPath(e, r, 'move'), 'a', [65]);
      final destDir = await _getPath(e, r, 'move/b');

      // Create some files and dirs for each dir.
      await _createFile(e, destDir, 'file2', [2]);
      await _createFolderWithDefFile(e, destDir, 'b_sub');

      // Create a conflict.
      await e.ensureDirs(r, ['move', 'b', 'a'].lock);
      await _createFile(e, await _getPath(e, r, 'move/b/a'), 'z', [4, 5]);

      final newPath = await e.moveToDir(
          r, _genRelPath('move/a'), _genRelPath('move/b'), false);
      final st = await e.stat(newPath.path);
      h.equals(st!.name, 'a (1)');

      h.mapEquals(await e.directoryToMap(r), {
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

    ns.add('Move file (file conflict)', (h) async {
      final e = env;
      final r = h.data as BFPath;

      // Move move/a to move/b
      await e.ensureDirs(r, ['move', 'b'].lock);
      await _createFile(e, await _getPath(e, r, 'move'), 'a', [65]);
      final destDir = await _getPath(e, r, 'move/b');

      // Create some files and dirs for each dir.
      await _createFile(e, destDir, 'file2', [2]);
      await _createFolderWithDefFile(e, destDir, 'b_sub');

      // Create a conflict.
      await _createFile(e, destDir, 'a', [4, 5, 6]);

      final newPath = await e.moveToDir(
          r, _genRelPath('move/a'), _genRelPath('move/b'), false);
      final st = await e.stat(newPath.path);
      h.equals(st!.name, 'a (1)');

      h.mapEquals(await e.directoryToMap(r), {
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

    ns.add('Move and replace file (no conflict)', (h) async {
      final e = env;
      final r = h.data as BFPath;

      // Move move/a to move/b
      await e.ensureDirs(r, ['move', 'b'].lock);
      await _createFile(e, await _getPath(e, r, 'move'), 'a', [65]);
      final destDir = await _getPath(e, r, 'move/b');

      // Create some files and dirs for each dir.
      await _createFile(e, destDir, 'file2', [2]);
      await _createFolderWithDefFile(e, destDir, 'b_sub');

      final newPath = await e.forceMoveToDir(
          r, _genRelPath('move/a'), _genRelPath('move/b'), false);
      final st = await e.stat(newPath.path);
      h.equals(st!.name, 'a');

      h.mapEquals(await e.directoryToMap(r), {
        "move": {
          "b": {
            "a": "41",
            "file2": "02",
            "b_sub": {"content.bin": "61626364656620f09f8d89f09f8c8f"}
          }
        }
      });
    });

    ns.add('Move and replace file (with conflict)', (h) async {
      final e = env;
      final r = h.data as BFPath;

      // Move move/a to move/b
      await e.ensureDirs(r, ['move', 'b'].lock);
      await _createFile(e, await _getPath(e, r, 'move'), 'a', [65]);
      final destDir = await _getPath(e, r, 'move/b');

      // Create some files and dirs for each dir.
      await _createFile(e, destDir, 'file2', [2]);
      await _createFolderWithDefFile(e, destDir, 'b_sub');

      // Create a conflict.
      await _createFile(e, destDir, 'a', [1, 2, 3]);

      final newPath = await e.forceMoveToDir(
          r, _genRelPath('move/a'), _genRelPath('move/b'), false);
      final st = await e.stat(newPath.path);
      h.equals(st!.name, 'a');

      h.mapEquals(await e.directoryToMap(r), {
        "move": {
          "b": {
            "a": "41",
            "file2": "02",
            "b_sub": {"content.bin": "61626364656620f09f8d89f09f8c8f"}
          }
        }
      });
    });

    ns.add('Move and replace file (new name = default name) (no conflict)',
        (h) async {
      final e = env;
      final r = h.data as BFPath;

      // Move move/a to move/b
      await e.ensureDirs(r, ['move', 'b'].lock);
      await _createFile(e, await _getPath(e, r, 'move'), 'a', [65]);
      final destDir = await _getPath(e, r, 'move/b');

      // Create some files and dirs for each dir.
      await _createFile(e, destDir, 'file2', [2]);
      await _createFolderWithDefFile(e, destDir, 'b_sub');

      final newPath = await e.forceMoveToDir(
          r, _genRelPath('move/a'), _genRelPath('move/b'), false,
          unsafeNewName: 'a');
      final st = await e.stat(newPath.path);
      h.equals(st!.name, 'a');

      h.mapEquals(await e.directoryToMap(r), {
        "move": {
          "b": {
            "a": "41",
            "file2": "02",
            "b_sub": {"content.bin": "61626364656620f09f8d89f09f8c8f"}
          }
        }
      });
    });

    ns.add('Move and replace file (new name = default name) (with conflict)',
        (h) async {
      final e = env;
      final r = h.data as BFPath;

      // Move move/a to move/b
      await e.ensureDirs(r, ['move', 'b'].lock);
      await _createFile(e, await _getPath(e, r, 'move'), 'a', [65]);
      final destDir = await _getPath(e, r, 'move/b');

      // Create some files and dirs for each dir.
      await _createFile(e, destDir, 'file2', [2]);
      await _createFolderWithDefFile(e, destDir, 'b_sub');

      // Create a conflict.
      await _createFile(e, destDir, 'a', [1, 2, 3]);

      final newPath = await e.forceMoveToDir(
          r, _genRelPath('move/a'), _genRelPath('move/b'), false,
          unsafeNewName: 'a');
      final st = await e.stat(newPath.path);
      h.equals(st!.name, 'a');

      h.mapEquals(await e.directoryToMap(r), {
        "move": {
          "b": {
            "a": "41",
            "file2": "02",
            "b_sub": {"content.bin": "61626364656620f09f8d89f09f8c8f"}
          }
        }
      });
    });

    ns.add('Move and replace file (new name) (no conflict)', (h) async {
      final e = env;
      final r = h.data as BFPath;

      // Move move/a to move/b
      await e.ensureDirs(r, ['move', 'b'].lock);
      await _createFile(e, await _getPath(e, r, 'move'), 'a', [65]);
      final destDir = await _getPath(e, r, 'move/b');

      // Create some files and dirs for each dir.
      await _createFile(e, destDir, 'file2', [2]);
      await _createFolderWithDefFile(e, destDir, 'b_sub');

      final newPath = await e.forceMoveToDir(
          r, _genRelPath('move/a'), _genRelPath('move/b'), false,
          unsafeNewName: 'zzz');
      final st = await e.stat(newPath.path);
      h.equals(st!.name, 'zzz');

      h.mapEquals(await e.directoryToMap(r), {
        "move": {
          "b": {
            "zzz": "41",
            "file2": "02",
            "b_sub": {"content.bin": "61626364656620f09f8d89f09f8c8f"}
          }
        }
      });
    });

    ns.add('Move and replace file (new name) (no conflict after new name)',
        (h) async {
      final e = env;
      final r = h.data as BFPath;

      // Move move/a to move/b
      await e.ensureDirs(r, ['move', 'b'].lock);
      await _createFile(e, await _getPath(e, r, 'move'), 'a', [65]);
      final destDir = await _getPath(e, r, 'move/b');

      // Create some files and dirs for each dir.
      await _createFile(e, destDir, 'file2', [2]);
      await _createFolderWithDefFile(e, destDir, 'b_sub');

      // Create a conflict.
      await _createFile(e, destDir, 'a', [1, 2, 3]);

      // Now `a` will be moved and assigned a new name `zzz`, so both `a` and `zzz` are kept.
      final newPath = await e.forceMoveToDir(
          r, _genRelPath('move/a'), _genRelPath('move/b'), false,
          unsafeNewName: 'zzz');
      final st = await e.stat(newPath.path);
      h.equals(st!.name, 'zzz');

      h.mapEquals(await e.directoryToMap(r), {
        "move": {
          "b": {
            "a": "010203",
            "zzz": "41",
            "file2": "02",
            "b_sub": {"content.bin": "61626364656620f09f8d89f09f8c8f"}
          }
        }
      });
    });

    ns.add(
        'Move and replace file (new name = default name) (conflict after new name)',
        (h) async {
      final e = env;
      final r = h.data as BFPath;

      // Move move/a to move/b
      await e.ensureDirs(r, ['move', 'b'].lock);
      await _createFile(e, await _getPath(e, r, 'move'), 'zzz', [65]);
      final destDir = await _getPath(e, r, 'move/b');

      // Create some files and dirs for each dir.
      await _createFile(e, destDir, 'file2', [2]);
      await _createFolderWithDefFile(e, destDir, 'b_sub');

      // Create a conflict.
      await _createFile(e, destDir, 'a', [1, 2, 3]);

      final newPath = await e.forceMoveToDir(
          r, _genRelPath('move/zzz'), _genRelPath('move/b'), false,
          unsafeNewName: 'a');
      final st = await e.stat(newPath.path);
      h.equals(st!.name, 'a');

      h.mapEquals(await e.directoryToMap(r), {
        "move": {
          "b": {
            "a": "41",
            "file2": "02",
            "b_sub": {"content.bin": "61626364656620f09f8d89f09f8c8f"}
          }
        }
      });
    });

    ns.add(
        'Move and replace file (new name = default name) (conflicts before and after new name)',
        (h) async {
      final e = env;
      final r = h.data as BFPath;

      // Move move/zzz to move/b as a new name `a`. Both `zzz` and `a` exist on dest side.
      await e.ensureDirs(r, ['move', 'b'].lock);
      await _createFile(e, await _getPath(e, r, 'move'), 'zzz', [65]);
      final destDir = await _getPath(e, r, 'move/b');

      // Create some files and dirs for each dir.
      await _createFile(e, destDir, 'file2', [2]);
      await _createFolderWithDefFile(e, destDir, 'b_sub');

      // Create a conflict.
      await _createFile(e, destDir, 'zzz', [4, 5, 6]);
      await _createFile(e, destDir, 'a', [1, 2, 3]);

      final newPath = await e.forceMoveToDir(
          r, _genRelPath('move/zzz'), _genRelPath('move/b'), false,
          unsafeNewName: 'a');
      final st = await e.stat(newPath.path);
      h.equals(st!.name, 'a');

      h.mapEquals(await e.directoryToMap(r), {
        "move": {
          "b": {
            "a": "41",
            "file2": "02",
            "zzz": "040506",
            "b_sub": {"content.bin": "61626364656620f09f8d89f09f8c8f"}
          }
        }
      });
    });

    ns.add('nextAvailableFile', (h) async {
      final r = h.data as BFPath;
      await _createFile(env, r, 'a 二', [1]);
      var name = await ZBFInternal.nextAvailableFileName(
          env, r, 'a 二', false, ZBFInternal.defaultFileNameUpdater);
      h.equals(name, 'a 二 (1)');

      name = await ZBFInternal.nextAvailableFileName(
          env, r, 'b', false, ZBFInternal.defaultFileNameUpdater);
      h.equals(name, 'b');
      await _createFile(env, r, 'b', [2]);

      name = await ZBFInternal.nextAvailableFileName(
          env, r, 'b', false, ZBFInternal.defaultFileNameUpdater);
      h.equals(name, 'b (1)');
    });

    ns.add('nextAvailableFile (extension)', (h) async {
      final r = h.data as BFPath;
      await _createFile(env, r, 'a 二.zz', [1]);
      var name = await ZBFInternal.nextAvailableFileName(
          env, r, 'a 二.zz', false, ZBFInternal.defaultFileNameUpdater);
      h.equals(name, 'a 二 (1).zz');

      name = await ZBFInternal.nextAvailableFileName(
          env, r, 'b.zz', false, ZBFInternal.defaultFileNameUpdater);
      h.equals(name, 'b.zz');
      await _createFile(env, r, 'b.zz', [2]);

      name = await ZBFInternal.nextAvailableFileName(
          env, r, 'b.zz', false, ZBFInternal.defaultFileNameUpdater);
      h.equals(name, 'b (1).zz');
    });

    ns.add('nextAvailableFile (folder with extension)', (h) async {
      final r = h.data as BFPath;
      await env.ensureDir(r, 'a 二.zz');
      var name = await ZBFInternal.nextAvailableFileName(
          env, r, 'a 二.zz', true, ZBFInternal.defaultFileNameUpdater);
      h.equals(name, 'a 二.zz (1)');

      name = await ZBFInternal.nextAvailableFileName(
          env, r, 'b.zz', true, ZBFInternal.defaultFileNameUpdater);
      h.equals(name, 'b.zz');
      await env.ensureDir(r, 'b.zz');

      name = await ZBFInternal.nextAvailableFileName(
          env, r, 'b.zz', true, ZBFInternal.defaultFileNameUpdater);
      h.equals(name, 'b.zz (1)');
    });

    ns.add('nextAvailableFile (custom name updater)', (h) async {
      // ignore: prefer_function_declarations_over_variables
      final nameUpdater =
          (String name, bool isDir, int count) => '$name -> $count';
      final r = h.data as BFPath;
      await _createFile(env, r, 'a 二.zz.abc', [1]);
      var name = await ZBFInternal.nextAvailableFileName(
          env, r, 'a 二.zz.abc', false, nameUpdater);
      h.equals(name, 'a 二.zz.abc -> 1');

      name = await ZBFInternal.nextAvailableFileName(
          env, r, 'b.zz.abc', false, nameUpdater);
      h.equals(name, 'b.zz.abc');
      await _createFile(env, r, 'b.zz.abc', [2]);

      name = await ZBFInternal.nextAvailableFileName(
          env, r, 'b.zz.abc', false, nameUpdater);
      h.equals(name, 'b.zz.abc -> 1');
    });

    await ns.run();
  }

  void _statEquals(BFEntity st, BFEntity st2) {
    assert(st.isDir == st2.isDir);
    assert(st.name == st2.name);
    assert(st.length == st2.length);
    assert(st.path == st2.path);
    assert(st.lastMod == st2.lastMod);
  }

  Future<BFEntity> _getStat(BFEnv e, BFPath root, String relPath) async {
    final stat = await e.stat(root, relPath: _genRelPath(relPath));
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
    return await e.slowWriteFileBytes(
        dir, fileName, Uint8List.fromList(content));
  }

  Future<BFPath> _createFolderWithDefFile(
      BFEnv e, BFPath root, String folderName) async {
    final dirPath = await e.ensureDir(root, folderName);
    await _createFile(
        e, dirPath.path, _defFolderContentFile, _defStringContentsBytes);
    return dirPath.path;
  }

  IList<String> _genRelPath(String relPath) {
    return relPath.split('/').lock;
  }

  Future<void> showErrorAlert(BuildContext context, Object err) async {
    await FcMaterialAlert.error(context, err, title: 'Error', okText: 'OK');
  }
}

extension BFTestExtension on BFEnv {
  Future<BFEntity> mustGetStat(BFPath path, {IList<String>? relPath}) async {
    final st = await stat(path, relPath: relPath);
    if (st == null) {
      throw Exception('Item not found');
    }
    return st;
  }

  Future<BFPath> slowWriteFileBytes(
      BFPath dir, String unsafeName, Uint8List bytes) async {
    if (hasStreamSupport()) {
      final writer = await writeFileStream(dir, unsafeName);
      await writer.write(bytes);
      await writer.close();
      return writer.getPath();
    }
    final tmp = tmpPath();
    await File(tmp).writeAsBytes(bytes);
    final res = await pasteLocalFile(tmp, dir, unsafeName);
    return res.path;
  }
}
