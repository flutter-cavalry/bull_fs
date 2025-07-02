import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:bull_fs/bull_fs.dart';
import 'package:example/ntr/ntr_suite.dart';
import 'package:fast_file_picker/fast_file_picker.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:fc_quick_dialog/fc_quick_dialog.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:tmp_path/tmp_path.dart';

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
  List<NTRTime> _durations = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text('BullFS tests'),
        ),
        body: Padding(
            padding: const EdgeInsets.all(10),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  OutlinedButton(
                      onPressed: _startLocal,
                      child: const Text('Run local env')),
                  if (!Platform.isWindows) ...[
                    const SizedBox(
                      height: 10,
                    ),
                    OutlinedButton(
                        onPressed: _startNative,
                        child: const Text('Run platform env'))
                  ],
                  const SizedBox(
                    height: 10,
                  ),
                  Text('Env: $_env'),
                  const SizedBox(
                    height: 10,
                  ),
                  SelectableText(_output),
                  const SizedBox(
                    height: 10,
                  ),
                  for (final d in _durations)
                    Text('${d.name}: ${d.duration.inMilliseconds} ms')
                ],
              ),
            )));
  }

  Future<void> _startLocal() async {
    final t = tmpPath();
    await Directory(t).create(recursive: true);
    await _runTests(BFLocalEnv(), BFLocalPath(t));
  }

  Future<void> _startNative() async {
    final pickerResult = await FastFilePicker.pickFolder(writePermission: true);
    if (pickerResult == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    final bfInit = await BFEnvUtil.envFromDirectory(
        path: pickerResult.path, uri: pickerResult.uri, macosIcloud: true);
    final env = bfInit.env;

    if (_env is BFNsfcEnv) {
      final resScope = BFAppleScopedRes(bfInit.path.toString());

      await resScope.tryAccess((bool granted) async {
        if (!granted) {
          throw Exception('Failed to get iOS folder access');
        }
        await _runTests(env, bfInit.path);
      });
    } else {
      await _runTests(env, bfInit.path);
    }
  }

  Future<void> _runTests(BFEnv env, BFPath root) async {
    final isEmpty = (await env.listDir(root)).isEmpty;
    if (!isEmpty) {
      throw Exception('Folder must be empty');
    }

    setState(() {
      _output = 'Running...';
      _durations = [];
    });

    BFPath? cleanUpPath;
    final isLocal = env.envType() == BFEnvType.local;
    final suite = NTRSuite(suiteName: isLocal ? 'Local' : 'Native');
    try {
      if (isLocal) {
        final localDir = tmpPath();
        await Directory(localDir).create(recursive: true);
        cleanUpPath = BFLocalPath(localDir);
        setState(() {
          _env = env.envType().toString();
        });
        await _runEnvTests(
          suite,
          env,
          cleanUpPath,
        );
      } else {
        cleanUpPath = await env.mkdirp(root, ['native'].lock);
        setState(() {
          _env = env.envType().toString();
        });
        await _runEnvTests(suite, env, cleanUpPath);
      }

      setState(() {
        _output = '✅ Done';
      });
    } catch (e) {
      setState(() {
        _output = 'Failed: See debug console for details';
      });
    } finally {
      setState(() {
        _durations = suite.reportDurations();
      });
      // Clean up.
      if (cleanUpPath != null) {
        await env.deletePathIfExists(
          root,
          null,
          true,
        );
      }
    }
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

  Future<void> _runEnvTests(NTRSuite ns, BFEnv env, BFPath globalRoot) async {
    int testCount = 0;
    ns.onLog = (s) => setState(() {
          _output = s;
        });
    ns.beforeEach = () async {
      testCount++;
      // Create a new folder for each test.
      final dirUri = await env.mkdirp(globalRoot, ['test_$testCount'].lock);
      return dirUri;
    };

    ns.add('ensureDir', (h) async {
      final r = h.data as BFPath;
      await env.mkdirp(r, ['space 一 二 三'].lock);

      // Do it twice and there should be no error.
      final newDir = await env.mkdirp(r, ['space 一 二 三'].lock);

      // Test return value.
      final st = await env.stat(newDir, true);
      h.notNull(st);
      h.equals(st!.isDir, true);
      h.equals(st.name, 'space 一 二 三');

      h.mapEquals(await env.directoryToMap(r), {"space 一 二 三": {}});
    });

    ns.add('ensureDir (failed)', (h) async {
      final r = h.data as BFPath;
      try {
        await env.writeFileBytes(r, 'space 一 二 三', Uint8List.fromList([1]));
        await env.mkdirp(r, ['space 一 二 三'].lock);
        throw Error();
      } on Exception catch (_) {
        h.mapEquals(await env.directoryToMap(r), {"space 一 二 三": "01"});
      }
    });

    ns.add('ensureDirs', (h) async {
      final r = h.data as BFPath;
      var newDir = await env.mkdirp(r, ['space 一 二 三', '22'].lock);
      // Test return value.
      var st = await env.stat(newDir, true);
      h.notNull(st);
      h.equals(st!.isDir, true);
      h.equals(st.name, '22');

      // Do it again with a new subdir.
      newDir = await env.mkdirp(r, ['space 一 二 三', '22', '3 33'].lock);
      st = await env.stat(newDir, true);
      h.equals(st!.isDir, true);
      h.equals(st.name, '3 33');

      // Do it again.
      newDir = await env.mkdirp(r, ['space 一 二 三', '22', '3 33'].lock);
      st = await env.stat(newDir, true);
      h.equals(st!.isDir, true);
      h.equals(st.name, '3 33');

      h.mapEquals(await env.directoryToMap(r), {
        "space 一 二 三": {
          "22": {"3 33": {}}
        }
      });
    });

    ns.add('ensureDirs (failed)', (h) async {
      final r = h.data as BFPath;
      try {
        await env.mkdirp(r, ['space 一 二 三', '22', '3 33'].lock);
        await env.writeFileBytes(
            (await env.directoryExists(r, ['space 一 二 三', '22'].lock))!,
            'file',
            Uint8List.fromList([1]));
        await env.mkdirp(r, ['space 一 二 三', '22', 'file', 'another'].lock);
        throw Error();
      } on Exception catch (_) {
        h.mapEquals(await env.directoryToMap(r), {
          "space 一 二 三": {
            "22": {"file": "01", "3 33": {}}
          }
        });
      }
    });

    ns.add('exists and findBasename (dir)', (h) async {
      final r = h.data as BFPath;
      await env.mkdirp(r, ['一', '22', '3 3', '4'].lock);
      // Test return value.
      final path = await env.directoryExists(
          await _getPath(env, r, '一/22'), ['3 3', '4'].lock);
      final st = await env.stat(path!, true);
      h.notNull(st);
      h.equals(st!.isDir, true);
      h.equals(st.name, '4');

      final basename = await env.findBasename(path, true);
      h.equals(basename, '4');

      final conflictType = await env.fileExists(
          await _getPath(env, r, '一/22'), ['3 3', '4'].lock);
      h.isNull(conflictType);

      final notFound = await env.directoryExists(
          await _getPath(env, r, '一/22'), ['3 3', '5'].lock);
      h.isNull(notFound);
    });

    ns.add('exists and findBasename (file)', (h) async {
      final r = h.data as BFPath;
      final dir = await env.mkdirp(r, ['一', '22'].lock);
      await env.writeFileBytes(dir, '3 3', Uint8List.fromList([1]));

      // Test return value.
      final path =
          await env.fileExists(await _getPath(env, r, '一'), ['22', '3 3'].lock);
      final st = await env.stat(path!, false);
      h.notNull(st);
      h.equals(st!.isDir, false);
      h.equals(st.name, '3 3');

      final basename = await env.findBasename(path, false);
      h.equals(basename, '3 3');

      final conflictType = await env.directoryExists(
          await _getPath(env, r, '一'), ['22', '3 3'].lock);
      h.isNull(conflictType);

      final notFound =
          await env.fileExists(await _getPath(env, r, '一'), ['22', '3 4'].lock);
      h.isNull(notFound);
    });

    ns.add('createDir', (h) async {
      final r = h.data as BFPath;
      final newDir = await env.createDir(r, 'space 一 二 三');

      // Test return value.
      final st = await env.stat(newDir.path, true);
      h.notNull(st);
      h.equals(st!.isDir, true);
      h.equals(st.name, 'space 一 二 三');
      h.equals(newDir.newName, st.name);

      h.mapEquals(await env.directoryToMap(r), {"space 一 二 三": {}});
    });

    ns.add('createDir (with conflict)', (h) async {
      final r = h.data as BFPath;
      await env.writeFileBytes(r, 'space 一 二 三', Uint8List.fromList([1]));

      final newDir = await env.createDir(r, 'space 一 二 三');

      // Test return value.
      final st = await env.stat(newDir.path, true);
      h.notNull(st);
      h.equals(st!.isDir, true);
      h.equals(st.name, 'space 一 二 三 (1)');
      h.equals(newDir.newName, st.name);

      h.mapEquals(await env.directoryToMap(r),
          {"space 一 二 三 (1)": {}, "space 一 二 三": "01"});
    });

    void testWriteFileStream(String fileName, bool multiple, bool overwrite,
        Map<String, dynamic> fs) {
      ns.add(
          'writeFileStream $fileName multiple: $multiple, overwrite: $overwrite',
          (h) async {
        final r = h.data as BFPath;
        var outStream =
            await env.writeFileStream(r, fileName, overwrite: overwrite);
        await outStream.write(utf8.encode('abc1'));
        await outStream.write(_defStringContentsBytes);
        await outStream.close();

        // Test `getPath`.
        var destUri = outStream.getPath();
        var destUriStat = await env.stat(destUri, false);
        h.notNull(destUriStat);
        h.equals(destUriStat!.isDir, false);
        h.equals(destUriStat.name, fileName);
        h.equals(destUriStat.length, 19);

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
          h.notNull(destUriStat);
          h.equals(destUriStat!.isDir, false);
          h.equals(
              destUriStat.name, overwrite ? fileName : _dupSuffix(fileName, 2));
          h.equals(destUriStat.length, 19);

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
          h.notNull(destUriStat);
          h.equals(destUriStat!.isDir, false);
          h.equals(
              destUriStat.name, overwrite ? fileName : _dupSuffix(fileName, 3));
          h.equals(destUriStat.length, 4);
        }

        h.mapEquals(await env.directoryToMap(r), fs);
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
    testWriteFileStream(
        'test 三.elephant.xyz', true, true, {"test 三.elephant.xyz": "41424341"});
    // No extension.
    testWriteFileStream('test 三', false, false,
        {"test 三": "6162633161626364656620f09f8d89f09f8c8f"});
    testWriteFileStream('test 三', true, false, {
      "test 三": "6162633161626364656620f09f8d89f09f8c8f",
      _dupSuffix('test 三', 2): "6162633261626364656620f09f8d89f09f8c8f",
      _dupSuffix('test 三', 3): "41424341"
    });
    testWriteFileStream('test 三', true, true, {"test 三": "41424341"});

    ns.add('writeFileStream (name updater)', (h) async {
      final r = h.data as BFPath;

      // Add first.
      var out = await env.writeFileStream(r, '一 二.txt.png',
          nameUpdater: _testNameUpdater);
      await out.write(_defStringContentsBytes);
      await out.close();
      // Add second which triggers the name updater.
      out = await env.writeFileStream(r, '一 二.txt.png',
          nameUpdater: _testNameUpdater);
      await out.write(_defStringContentsBytes);
      await out.close();
      var st = await env.stat(out.getPath(), false);
      h.equals(st!.name, 'NU-一 二.txt.png-false-1');
      h.equals(st.name, out.getFileName());
    });

    ns.add('writeFileStream (concurrent writes)', (h) async {
      final r = h.data as BFPath;

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

    ns.add('readFileStream (with offset)', (h) async {
      final r = h.data as BFPath;
      final tmpFile = tmpPath();
      await File(tmpFile).writeAsString(_defStringContents);
      final pasteRes = await env.pasteLocalFile(tmpFile, r, 'test.txt');

      final stream = await env.readFileStream(pasteRes.path, start: 3);
      final bytes = await stream.fold<List<int>>([], (prev, element) {
        prev.addAll(element);
        return prev;
      });
      h.equals(utf8.decode(bytes), _defStringContents.substring(3));

      h.mapEquals(await env.directoryToMap(r),
          {"test.txt": "61626364656620f09f8d89f09f8c8f"});
    });

    ns.add('readFileBytes', (h) async {
      final r = h.data as BFPath;
      final tmpFile = tmpPath();
      await File(tmpFile).writeAsString(_defStringContents);
      final pasteRes = await env.pasteLocalFile(tmpFile, r, 'test.txt');

      final bytes = await env.readFileBytes(pasteRes.path);
      h.equals(utf8.decode(bytes), _defStringContents);
    });

    ns.add('readFileBytes (start)', (h) async {
      final r = h.data as BFPath;
      final tmpFile = tmpPath();
      await File(tmpFile).writeAsString(_defStringContents);
      final pasteRes = await env.pasteLocalFile(tmpFile, r, 'test.txt');

      final bytes = await env.readFileBytes(pasteRes.path, start: 3);
      h.equals(utf8.decode(bytes), _defStringContents.substring(3));
    });

    ns.add('readFileBytes (count)', (h) async {
      final r = h.data as BFPath;
      final tmpFile = tmpPath();
      await File(tmpFile).writeAsString(_defStringContents);
      final pasteRes = await env.pasteLocalFile(tmpFile, r, 'test.txt');

      final bytes = await env.readFileBytes(pasteRes.path, count: 2);
      h.equals(utf8.decode(bytes), 'ab');
    });

    ns.add('readFileBytes (count larger than length)', (h) async {
      final r = h.data as BFPath;
      final tmpFile = tmpPath();
      await File(tmpFile).writeAsString(_defStringContents);
      final pasteRes = await env.pasteLocalFile(tmpFile, r, 'test.txt');

      final bytes = await env.readFileBytes(pasteRes.path, count: 100);
      h.equals(utf8.decode(bytes), _defStringContents);
    });

    ns.add('readFileBytes (start and count)', (h) async {
      final r = h.data as BFPath;
      final tmpFile = tmpPath();
      await File(tmpFile).writeAsString(_defStringContents);
      final pasteRes = await env.pasteLocalFile(tmpFile, r, 'test.txt');

      final bytes = await env.readFileBytes(pasteRes.path, start: 3, count: 2);
      h.equals(utf8.decode(bytes), 'de');
    });

    void testPasteToLocalFile(String fileName, bool multiple, bool overwrite,
        Map<String, dynamic> fs) {
      ns.add(
          'pasteLocalFile  $fileName multiple: $multiple, overwrite: $overwrite',
          (h) async {
        final r = h.data as BFPath;
        final tmpFile = tmpPath();
        await File(tmpFile).writeAsString('$_defStringContents 1');
        // Add first test.txt
        var pasteRes = await env.pasteLocalFile(tmpFile, r, fileName,
            overwrite: overwrite);
        var st = await env.stat(pasteRes.path, false);
        h.equals(st!.name, fileName);
        h.equals(st.name, pasteRes.newName);
        h.equals(st.length, 17);

        if (multiple) {
          // Add second test.txt
          await File(tmpFile).writeAsString('$_defStringContents 2');
          pasteRes = await env.pasteLocalFile(tmpFile, r, fileName,
              overwrite: overwrite);
          st = await env.stat(pasteRes.path, false);
          h.equals(st!.name, overwrite ? fileName : _dupSuffix(fileName, 2));
          h.equals(st.name, pasteRes.newName);
          h.equals(st.length, 17);

          // Add third test.txt
          await File(tmpFile).writeAsString('$_defStringContents 3');
          pasteRes = await env.pasteLocalFile(tmpFile, r, fileName,
              overwrite: overwrite);
          st = await env.stat(pasteRes.path, false);
          h.equals(st!.name, overwrite ? fileName : _dupSuffix(fileName, 3));
          h.equals(st.name, pasteRes.newName);
          h.equals(st.length, 17);
        }

        h.mapEquals(await env.directoryToMap(r), fs);
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
      _dupSuffix('test 三.elephant.xyz', 3): "61626364656620f09f8d89f09f8c8f2033"
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
    testPasteToLocalFile(
        'test 三', true, true, {"test 三": "61626364656620f09f8d89f09f8c8f2033"});

    ns.add('pasteLocalFile (name updater)', (h) async {
      final r = h.data as BFPath;
      final tmpFile = tmpPath();
      await File(tmpFile).writeAsString('$_defStringContents 1');

      // Add first.
      await env.pasteLocalFile(tmpFile, r, '一 二.txt.png',
          nameUpdater: _testNameUpdater);
      // Add second which triggers the name updater.
      var pasteRes = await env.pasteLocalFile(tmpFile, r, '一 二.txt.png',
          nameUpdater: _testNameUpdater);
      var st = await env.stat(pasteRes.path, false);
      h.equals(st!.name, 'NU-一 二.txt.png-false-1');
      h.equals(st.name, pasteRes.newName);
    });

    ns.add('readFileSync', (h) async {
      final r = h.data as BFPath;
      final tmpFile = tmpPath();
      await File(tmpFile).writeAsString(_defStringContents);
      final pasteRes = await env.pasteLocalFile(tmpFile, r, 'test.txt');

      final bytes = await env.readFileBytes(pasteRes.path);
      h.equals(utf8.decode(bytes), _defStringContents);
    });

    void testwriteFileBytes(String fileName, bool multiple, bool overwrite,
        Map<String, dynamic> fs) {
      ns.add(
          'writeFileSync  $fileName multiple: $multiple, overwrite: $overwrite',
          (h) async {
        final r = h.data as BFPath;
        // Add first test.txt
        var pasteRes = await env.writeFileBytes(
            r, fileName, utf8.encode('$_defStringContents 1'),
            overwrite: overwrite);
        var st = await env.stat(pasteRes.path, false);
        h.equals(st!.name, fileName);
        h.equals(st.name, pasteRes.newName);
        h.equals(st.length, 17);

        if (multiple) {
          // Add second test.txt
          pasteRes = await env.writeFileBytes(
              r, fileName, utf8.encode('$_defStringContents 2'),
              overwrite: overwrite);
          st = await env.stat(pasteRes.path, false);
          h.equals(st!.name, overwrite ? fileName : _dupSuffix(fileName, 2));
          h.equals(st.name, pasteRes.newName);
          h.equals(st.length, 17);

          // Add third test.txt
          // Write a smaller string to test that the file is truncated.
          pasteRes = await env.writeFileBytes(r, fileName, utf8.encode('ABCD'),
              overwrite: overwrite);
          st = await env.stat(pasteRes.path, false);
          h.equals(st!.name, overwrite ? fileName : _dupSuffix(fileName, 3));
          h.equals(st.name, pasteRes.newName);
          h.equals(st.length, 4);
        }

        h.mapEquals(await env.directoryToMap(r), fs);
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
    testwriteFileBytes(
        'test 三.elephant.xyz', true, true, {"test 三.elephant.xyz": "41424344"});
    // No extension.
    testwriteFileBytes('test 三', false, false,
        {"test 三": "61626364656620f09f8d89f09f8c8f2031"});
    testwriteFileBytes('test 三', true, false, {
      "test 三": "61626364656620f09f8d89f09f8c8f2031",
      _dupSuffix('test 三', 2): "61626364656620f09f8d89f09f8c8f2032",
      _dupSuffix('test 三', 3): "41424344"
    });
    testwriteFileBytes('test 三', true, true, {"test 三": "41424344"});

    ns.add('writeFileSync (name updater)', (h) async {
      final r = h.data as BFPath;

      // Add first.
      await env.writeFileBytes(r, '一 二.txt.png', _defStringContentsBytes,
          nameUpdater: _testNameUpdater);
      // Add second which triggers the name updater.
      var writeRes = await env.writeFileBytes(
          r, '一 二.txt.png', _defStringContentsBytes,
          nameUpdater: _testNameUpdater);
      var st = await env.stat(writeRes.path, false);
      h.equals(st!.name, 'NU-一 二.txt.png-false-1');
      h.equals(st.name, writeRes.newName);
    });

    ns.add('stat and child (folder)', (h) async {
      final r = h.data as BFPath;
      final newDir = await env.mkdirp(r, ['a', '一 二'].lock);
      final st = await env.stat(newDir, true);

      h.notNull(st);
      h.equals(st!.isDir, true);
      h.equals(st.name, '一 二');
      h.equals(st.length, -1);

      final stAuto = await env.stat(newDir, null);
      h.equals(stAuto!.isDir, true);
      h.equals(stAuto.name, '一 二');
      h.equals(stAuto.length, -1);

      final st2 = await env.child(r, ['a', '一 二'].lock);
      _statEquals(st, st2!);

      final subPath = await env.directoryExists(r, ['a'].lock);
      final st3 = await env.child(subPath!, ['一 二'].lock);
      _statEquals(st, st3!);
    });

    ns.add('stat and child (file)', (h) async {
      final r = h.data as BFPath;
      final newDir = await env.mkdirp(r, ['a', '一 二'].lock);
      final fileUri = (await env.writeFileBytes(
              newDir, 'test 仨.txt', _defStringContentsBytes))
          .path;
      final st = await env.stat(fileUri, false);

      h.notNull(st);
      h.equals(st!.isDir, false);
      h.equals(st.name, 'test 仨.txt');
      h.equals(st.length, 15);

      final stAuto = await env.stat(fileUri, null);
      h.equals(stAuto!.isDir, false);
      h.equals(stAuto.name, 'test 仨.txt');
      h.equals(stAuto.length, 15);

      final st2 = await env.child(r, ['a', '一 二', 'test 仨.txt'].lock);
      _statEquals(st, st2!);

      final subPath = await env.directoryExists(r, ['a', '一 二'].lock);
      final st3 = await env.child(subPath!, ['test 仨.txt'].lock);
      _statEquals(st, st3!);
    });

    ns.add('null stat for items that don\'t exist', (h) async {
      final r = h.data as BFPath;
      final newDir = await env.mkdirp(r, ['a', '一 二'].lock);
      final fileUri = (await env.writeFileBytes(
              newDir, 'test 仨.txt', _defStringContentsBytes))
          .path;
      // Delete the created file to test null stat.
      await env.delete(fileUri, false);
      final st = await env.stat(fileUri, false);

      h.isNull(st);
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
      h.equals(await _formatPathInfoFileList(env, contents),
          '一 二/a.txt | 一 二/b.txt | 一 二/deep/c.txt | root.txt | root2.txt');
    });

    ns.add('rename (folder)', (h) async {
      final r = h.data as BFPath;
      await env.mkdirp(r, ['a', '一 二'].lock);
      final newPath = await env.rename(await _getPath(env, r, 'a/一 二'), true,
          await _getPath(env, r, 'a'), 'test 仨 2.txt');
      final st = await env.stat(newPath, true);
      h.equals(st!.name, 'test 仨 2.txt');

      h.mapEquals(await env.directoryToMap(r), {
        "a": {"test 仨 2.txt": {}}
      });
    });

    ns.add('rename (folder) (failed)', (h) async {
      final r = h.data as BFPath;
      try {
        await env.mkdirp(r, ['一 二'].lock);
        await env.writeFileBytes(r, 'test 仨.txt', _defStringContentsBytes);

        await env.rename(await _getPath(env, r, '一 二'), true, r, 'test 仨.txt');
        throw Error();
      } on Exception catch (_) {
        h.mapEquals(await env.directoryToMap(r),
            {"一 二": {}, "test 仨.txt": "61626364656620f09f8d89f09f8c8f"});
      }
    });

    ns.add('rename (file)', (h) async {
      final r = h.data as BFPath;
      final newDir = await env.mkdirp(r, ['a', '一 二'].lock);
      await env.writeFileBytes(newDir, 'test 仨.txt', _defStringContentsBytes);
      final newPath = await env.rename(
          await _getPath(env, r, 'a/一 二/test 仨.txt'),
          false,
          await _getPath(env, r, 'a/一 二'),
          'test 仨 2.txt');
      final st = await env.stat(newPath, false);
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
        await env.mkdirp(r, ['test 仨 2.txt'].lock);

        await env.writeFileBytes(r, 'test 仨.txt', _defStringContentsBytes);

        await env.rename(await _getPath(env, r, 'test 仨 2.txt/test 仨.txt'),
            false, await _getPath(env, r, 'test 仨 2.txt'), 'test 仨 2.txt');
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
      h.equals(st!.name, 'a');
      h.equals(st.name, newPath.newName);

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
      h.equals(st!.name, _dupSuffix('a', 2));
      h.equals(st.name, newPath.newName);

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
      h.equals(st!.name, 'a (1)');
      h.equals(st.name, newPath.newName);

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
      await e.mkdirp(r, ['move', 'b'].lock);
      await _createFile(e, await _getPath(e, r, 'move'), 'a', [100]);
      final destDir = await _getPath(e, r, 'move/b');

      // Create some files and dirs for each dir.
      await _createFile(e, destDir, 'file2', [2]);
      await _createFolderWithDefFile(e, destDir, 'b_sub');

      final newPath = await e.moveToDir(await _getPath(e, r, 'move/a'), false,
          await _getPath(e, r, 'move'), await _getPath(e, r, 'move/b'));
      final st = await e.stat(newPath.path, false);
      h.equals(st!.name, 'a');
      h.equals(st.name, newPath.newName);

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
      h.equals(st!.name, 'a (1)');
      h.equals(st.name, newPath.newName);

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
      h.equals(st!.name, 'a (1)');
      h.equals(st.name, newPath.newName);

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
      h.equals(st!.name, 'a');
      h.equals(st.name, newPath.newName);

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
      h.equals(st!.name, 'a');
      h.equals(st.name, newPath.newName);

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
      h.equals(st!.name, 'a');
      h.equals(st.name, newPath.newName);

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
      h.equals(st!.name, 'a');
      h.equals(st.name, newPath.newName);

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

    ns.add('nextAvailableFile', (h) async {
      final r = h.data as BFPath;
      await _createFile(env, r, 'a 二', [1]);
      var name = await ZBFInternal.nextAvailableFileName(
          env, r, 'a 二', false, bfDefaultNameUpdater);
      h.equals(name, 'a 二 (1)');

      name = await ZBFInternal.nextAvailableFileName(
          env, r, 'b', false, bfDefaultNameUpdater);
      h.equals(name, 'b');
      await _createFile(env, r, 'b', [2]);

      name = await ZBFInternal.nextAvailableFileName(
          env, r, 'b', false, bfDefaultNameUpdater);
      h.equals(name, 'b (1)');
    });

    ns.add('nextAvailableFile (extension)', (h) async {
      final r = h.data as BFPath;
      await _createFile(env, r, 'a 二.zz', [1]);
      var name = await ZBFInternal.nextAvailableFileName(
          env, r, 'a 二.zz', false, bfDefaultNameUpdater);
      h.equals(name, 'a 二 (1).zz');

      name = await ZBFInternal.nextAvailableFileName(
          env, r, 'b.zz', false, bfDefaultNameUpdater);
      h.equals(name, 'b.zz');
      await _createFile(env, r, 'b.zz', [2]);

      name = await ZBFInternal.nextAvailableFileName(
          env, r, 'b.zz', false, bfDefaultNameUpdater);
      h.equals(name, 'b (1).zz');
    });

    ns.add('nextAvailableFile (folder with extension)', (h) async {
      final r = h.data as BFPath;
      await env.mkdirp(r, ['a 二.zz'].lock);
      var name = await ZBFInternal.nextAvailableFileName(
          env, r, 'a 二.zz', true, bfDefaultNameUpdater);
      h.equals(name, 'a 二.zz (1)');

      name = await ZBFInternal.nextAvailableFileName(
          env, r, 'b.zz', true, bfDefaultNameUpdater);
      h.equals(name, 'b.zz');
      await env.mkdirp(r, ['b.zz'].lock);

      name = await ZBFInternal.nextAvailableFileName(
          env, r, 'b.zz', true, bfDefaultNameUpdater);
      h.equals(name, 'b.zz (1)');
    });

    ns.add('nextAvailableFile (custom name updater)', (h) async {
      // ignore: prefer_function_declarations_over_variables
      final nameUpdater = BFNameUpdater(
          (String name, bool isDir, int count) => '$name -> $count');
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

    ns.add('nextAvailableFile (registry)', (h) async {
      final r = h.data as BFPath;
      await _createFile(env, r, 'a 二', [1]);
      var name = await ZBFInternal.nextAvailableFileName(
        env,
        r,
        'a 二',
        false,
        BFNameUpdater(bfDefaultFileNameUpdaterFn,
            nameRegistry: {'a 二', 'a 二 (1)'}),
      );
      h.equals(name, 'a 二 (2)');
    });

    final failedNames = await ns.run();
    if (failedNames.isNotEmpty) {
      throw Exception('Failed tests: $failedNames');
    }
  }

  void _statEquals(BFEntity st, BFEntity st2) {
    assert(st.isDir == st2.isDir);
    assert(st.name == st2.name);
    assert(st.length == st2.length);
    assert(st.path == st2.path);
    assert(st.lastMod == st2.lastMod);
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

  Future<void> showErrorAlert(BuildContext context, Object err) async {
    await FcQuickDialog.error(context,
        error: err, title: 'Error', okText: 'OK');
  }
}

final _testNameUpdater = BFNameUpdater(_testNameUpdaterFn);

String _testNameUpdaterFn(String fileName, bool isDir, int attempt) {
  return 'NU-$fileName-$isDir-$attempt';
}

extension BFOutStreamExtension on BFOutStream {
  Future<void> writeManyChunks(String prefix) async {
    final random = Random();
    for (var i = 0; i < 50; i++) {
      await write(Uint8List.fromList('$prefix $i'.codeUnits));
      await Future.delayed(Duration(milliseconds: random.nextInt(100)));
    }
    await close();
  }
}
