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
import 'package:collection/collection.dart';

import '../../util/ke_bf_env.dart';

const bool appMacOSScoped = true;
const defFolderContentFile = 'content.bin';
const defStringContents = 'abcdef 🍉🌏';
final ignoredFiles = {'.DS_Store'};

extension BFEntityExtension on BFEntity {
  BFPathAndName toMini() {
    return BFPathAndName(path, name);
  }
}

class BFTestRoute extends StatefulWidget {
  const BFTestRoute({super.key});

  @override
  State<BFTestRoute> createState() => _BFTestRouteState();
}

class _BFTestRouteState extends State<BFTestRoute> {
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
              Text(_output),
              const SizedBox(
                height: 10,
              ),
              OutlinedButton(
                  onPressed: _start, child: const Text('Open a folder'))
            ],
          ),
        ));
  }

  Future<void> _start() async {
    final icloudVault = IcloudVault.create(macOSScoped: appMacOSScoped);
    try {
      final rootRaw = Platform.isWindows
          ? FcFilePickerXResult.fromStringOrUri(tmpPath(), null)
          : (await FcFilePickerUtil.pickFolder(macOSScoped: appMacOSScoped));
      if (rootRaw == null) {
        return;
      }
      if (!mounted) {
        return;
      }
      final root = rootRaw.toBFPath(macOSScoped: appMacOSScoped);
      await icloudVault?.requestAccess(root);
      setState(() {
        _output = 'Running...';
      });

      // Local env.
      final localDir = tmpPath();
      await Directory(localDir).create(recursive: true);
      await _runEnvTests('Local', BFEnvLocal(), BFLocalPath(localDir));
      final env = newUnsafeKeBFEnv(macOSScoped: appMacOSScoped);
      if (env.envType() != BFEnvType.local) {
        // Native env.
        await _runEnvTests('Native', env, await env.mkdir(root, 'native'));
        // Clean up.
        await env.deletePathIfExists(root);
      }

      setState(() {
        _output = 'Done';
      });
    } catch (err) {
      if (!mounted) {
        return;
      }
      await showErrorAlert(context, err);

      setState(() {
        _output = 'Failed';
      });
    } finally {
      await icloudVault?.release();
    }
  }

  String _appendCounterToFileName(BFEnv env, String fileName, int c) {
    final ext = p.extension(fileName);
    final name = p.basenameWithoutExtension(fileName);
    // Android starts with 1 instead of 2.
    if (Platform.isAndroid && env.envType() == BFEnvType.saf) {
      c--;
    }
    return '$name ($c)$ext';
  }

  Future<void> _createNestedDir(BFEnv env, BFPath r) async {
    final subDir1 = await env.mkdir(r, '一');
    await env.slowWriteFileBytes(subDir1, 'a.txt', Uint8List.fromList([1]));
    await env.slowWriteFileBytes(subDir1, 'b.txt', Uint8List.fromList([2]));

    // b is empty.
    await env.mkdir(r, 'b');

    final subDir11 = await env.mkdir(subDir1, 'deep');
    await env.slowWriteFileBytes(subDir11, 'c.txt', Uint8List.fromList([3]));

    await env.slowWriteFileBytes(r, 'root.txt', Uint8List.fromList([4]));
    await env.slowWriteFileBytes(r, 'root2.txt', Uint8List.fromList([5]));
  }

  String _formatEntityList(List<BFEntity> list) {
    list.sort((a, b) => a.name.compareTo(b.name));
    return list.map((e) => e.toString2()).join('|');
  }

  String _formatFatEntityList(List<BFFatEntity> list) {
    list.sort((a, b) => a.entity.name.compareTo(b.entity.name));
    return list.map((e) => e.toString2()).join('|');
  }

  Future<void> _runEnvTests(String name, BFEnv env, BFPath root) async {
    final ns = NTRSuite(name: name);

    int testCount = 0;
    ns.onLog = (s) => setState(() {
          _output = s;
        });
    ns.beforeAll = () async {
      testCount++;
      // Create a new folder for each test.
      final dirUri = await env.mkdir(root, 'test_$testCount');
      return dirUri;
    };
    ns.afterAll = (h) async {
      final r = h.data as BFPath;
      await env.deletePathIfExists(r);
    };

    ns.add('mkdir', (h) async {
      final r = h.data as BFPath;
      final newDir = await env.mkdir(r, 'space 一 二 三');
      final st = await env.stat(newDir);

      h.notNull(st);
      h.equals(st!.isDir, true);
      h.equals(st.name, 'space 一 二 三');
    });

    ns.add('mkdirp', (h) async {
      final r = h.data as BFPath;
      final newDir = await env.mkdirp(r, ['space 一 二 三', '22', '3 33'].lock);

      h.notNull(await env.directoryExists(r, relPath: ['space 一 二 三'].lock));
      h.notNull(
          await env.directoryExists(r, relPath: ['space 一 二 三', '22'].lock));
      h.notNull(await env.directoryExists(r,
          relPath: ['space 一 二 三', '22', '3 33'].lock));
      h.isNull(await env.directoryExists(r,
          relPath: ['space 一 二 三', '22', '3 33', '4 44'].lock));
      h.isNull(
          await env.directoryExists(r, relPath: ['space 一 二 三', '4 44'].lock));

      final st = await env.stat(newDir);
      h.notNull(st);
      h.equals(st!.isDir, true);
      h.equals(st.name, '3 33');
    });

    if (env.hasStreamSupport()) {
      void testWriteFileStream(String fileName, bool multiple) {
        ns.add('writeFileStream $fileName multiple: $multiple', (h) async {
          final r = h.data as BFPath;
          var outStream = await env.writeFileStream(r, fileName);
          await outStream.write(Uint8List.fromList(utf8.encode('abc1')));
          await outStream
              .write(Uint8List.fromList(utf8.encode(defStringContents)));
          await outStream.flush();
          await outStream.close();

          var destUri = outStream.getPath();
          final destUri1 = destUri;
          var destUriStat = await env.stat(destUri);
          h.notNull(destUriStat);
          h.equals(destUriStat!.isDir, false);
          h.equals(destUriStat.name, fileName);
          h.equals(utf8.decode(await env.slowReadFileBytes(destUri)),
              'abc1$defStringContents');

          if (multiple) {
            // Write to the same file again.
            outStream = await env.writeFileStream(r, fileName);
            await outStream.write(Uint8List.fromList(utf8.encode('abc2')));
            await outStream
                .write(Uint8List.fromList(utf8.encode(defStringContents)));
            await outStream.flush();
            await outStream.close();

            destUri = outStream.getPath();
            final destUri2 = destUri;
            destUriStat = await env.stat(destUri);
            h.notNull(destUriStat);
            h.equals(destUriStat!.isDir, false);
            h.equals(
                destUriStat.name, _appendCounterToFileName(env, fileName, 2));
            h.equals(utf8.decode(await env.slowReadFileBytes(destUri)),
                'abc2$defStringContents');

            // Write to the same file again.
            outStream = await env.writeFileStream(r, fileName);
            await outStream.write(Uint8List.fromList(utf8.encode('abc3')));
            await outStream
                .write(Uint8List.fromList(utf8.encode(defStringContents)));
            await outStream.flush();
            await outStream.close();

            destUri = outStream.getPath();
            destUriStat = await env.stat(destUri);
            h.notNull(destUriStat);
            h.equals(destUriStat!.isDir, false);
            h.equals(
                destUriStat.name, _appendCounterToFileName(env, fileName, 3));
            h.equals(utf8.decode(await env.slowReadFileBytes(destUri)),
                'abc3$defStringContents');

            // Check previous files were not overwritten.
            h.equals(utf8.decode(await env.slowReadFileBytes(destUri1)),
                'abc1$defStringContents');
            h.equals(utf8.decode(await env.slowReadFileBytes(destUri2)),
                'abc2$defStringContents');
          }
        });
      }

      testWriteFileStream('test 三.txt', false);
      testWriteFileStream('test 三.txt', true);
      testWriteFileStream('test 三.elephant', false);
      testWriteFileStream('test 三.elephant', true);
      testWriteFileStream('test 三', false);
      testWriteFileStream('test 三', true);

      ns.add('readFileStream', (h) async {
        final r = h.data as BFPath;
        final tmpFile = tmpPath();
        await File(tmpFile).writeAsString(defStringContents);
        final fileUri = await env.pasteLocalFile(tmpFile, r, 'test.txt');

        final stream = await env.readFileStream(fileUri);
        final bytes = await stream.fold<List<int>>([], (prev, element) {
          prev.addAll(element);
          return prev;
        });
        h.equals(utf8.decode(bytes), defStringContents);
      });
    }

    ns.add('copyToLocalFile', (h) async {
      final r = h.data as BFPath;
      final tmpFile = tmpPath();
      await File(tmpFile).writeAsString(defStringContents);
      final fileUri = await env.pasteLocalFile(tmpFile, r, 'test.txt');

      final tmpFile2 = tmpPath();
      await env.copyToLocalFile(fileUri, tmpFile2);
      h.equals(await File(tmpFile2).readAsString(), defStringContents);
    });

    void testPasteToLocalFile(String fileName, bool multiple) {
      ns.add('pasteLocalFile  $fileName multiple: $multiple', (h) async {
        final r = h.data as BFPath;
        final tmpFile = tmpPath();
        await File(tmpFile).writeAsString('$defStringContents 1');
        // Add first test.txt
        var fileUri = await env.pasteLocalFile(tmpFile, r, fileName);
        final fileUri1 = fileUri;

        var st = await env.stat(fileUri);
        h.notNull(st);
        h.equals(st!.isDir, false);
        h.equals(st.name, fileName);
        h.equals(utf8.decode(await env.slowReadFileBytes(fileUri)),
            '$defStringContents 1');

        if (multiple) {
          // Add second test.txt
          await File(tmpFile).writeAsString('$defStringContents 2');
          fileUri = await env.pasteLocalFile(tmpFile, r, fileName);
          final fileUri2 = fileUri;

          st = await env.stat(fileUri);
          h.notNull(st);
          h.equals(st!.isDir, false);
          h.equals(st.name, _appendCounterToFileName(env, fileName, 2));
          h.equals(utf8.decode(await env.slowReadFileBytes(fileUri)),
              '$defStringContents 2');

          // Add third test.txt
          await File(tmpFile).writeAsString('$defStringContents 3');
          fileUri = await env.pasteLocalFile(tmpFile, r, fileName);

          st = await env.stat(fileUri);
          h.notNull(st);
          h.equals(st!.isDir, false);
          h.equals(st.name, _appendCounterToFileName(env, fileName, 3));
          h.equals(utf8.decode(await env.slowReadFileBytes(fileUri)),
              '$defStringContents 3');

          // Test previous files were not overwritten.
          h.equals(utf8.decode(await env.slowReadFileBytes(fileUri1)),
              '$defStringContents 1');
          h.equals(utf8.decode(await env.slowReadFileBytes(fileUri2)),
              '$defStringContents 2');
        }
      });
    }

    testPasteToLocalFile('test 三.txt', false);
    testPasteToLocalFile('test 三.txt', true);
    testPasteToLocalFile('test 三.elephant', false);
    testPasteToLocalFile('test 三.elephant', true);
    testPasteToLocalFile('test 三', false);
    testPasteToLocalFile('test 三', true);

    ns.add('stat (folder)', (h) async {
      final r = h.data as BFPath;
      final newDir = await env.mkdirp(r, ['a', '一 二'].lock);
      final st = await env.stat(newDir);

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
      final newDir = await env.mkdirp(r, ['a', '一 二'].lock);
      final fileUri = await env.slowWriteFileBytes(newDir, 'test 仨.txt',
          Uint8List.fromList(utf8.encode(defStringContents)));
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
          '[D|b]|[F|root.txt|1]|[F|root2.txt|1]|[D|一]');
    });

    ns.add('listDir including children', (h) async {
      final r = h.data as BFPath;
      await _createNestedDir(env, r);

      final contents = await env.listDir(r, recursive: true);
      h.equals(_formatEntityList(contents),
          '[F|a.txt|1]|[D|b]|[F|b.txt|1]|[F|c.txt|1]|[D|deep]|[F|root.txt|1]|[F|root2.txt|1]|[D|一]');
    });

    ns.add('listDirFat', (h) async {
      final r = h.data as BFPath;
      await _createNestedDir(env, r);

      final contents = await env.listDirFat(r, null);
      h.equals(_formatFatEntityList(contents),
          '[F|一/a.txt|1]|[F|一/b.txt|1]|[F|一/deep/c.txt|1]|[F|root.txt|1]|[F|root2.txt|1]');
    });

    ns.add('rename (folder)', (h) async {
      final r = h.data as BFPath;
      final newDir = await env.mkdirp(r, ['a', '一 二'].lock);
      final st = await env.stat(newDir);

      h.notNull(st);
      h.equals(st!.isDir, true);
      h.equals(st.name, '一 二');
      h.equals(st.length, -1);

      final newDirUri = await env.rename(newDir, 'test 仨 2.txt', true);
      final st2 = await env.stat(newDirUri);

      h.notNull(st2);
      h.equals(st2!.isDir, true);
      h.equals(st2.name, 'test 仨 2.txt');
      h.equals(st2.length, -1);
    });

    ns.add('rename (file)', (h) async {
      final r = h.data as BFPath;
      final newDir = await env.mkdirp(r, ['a', '一 二'].lock);
      final fileUri = await env.slowWriteFileBytes(newDir, 'test 仨.txt',
          Uint8List.fromList(utf8.encode(defStringContents)));
      final st = await env.stat(fileUri);

      h.notNull(st);
      h.equals(st!.isDir, false);
      h.equals(st.name, 'test 仨.txt');
      h.equals(st.length, 15);

      final newFileUri = await env.rename(fileUri, 'test 仨 2.txt', false);
      final st2 = await env.stat(newFileUri);

      h.notNull(st2);
      h.equals(st2!.isDir, false);
      h.equals(st2.name, 'test 仨 2.txt');
      h.equals(st2.length, 15);
    });

    ns.add('Move and replace and delete', (h) async {
      final e = env;
      final r = h.data as BFPath;

      // --- move to ---
      await e.mkdirp(r, ['move', 'a'].lock);
      final srcDir = await _getPath(e, r, 'move/a');
      final destDir = await _getPath(e, r, 'move');
      await _createFile(e, srcDir, 'move.file1', 'FILE_1');
      await _createFile(e, srcDir, 'move.file2', 'FILE_2');
      await _createFolderWithDefFile(e, srcDir, 'move_dir1');
      await _createFolderWithDefFile(e, srcDir, 'move_dir2');

      // move file to local dir (unsafe).
      var entName = 'move.file1';
      var src = ['move', 'a', entName].lock;
      var dest = ['move', entName].lock;
      var movedPath = await e.move(r, src, dest, false);
      assert(movedPath == await _getPath(e, destDir, entName));
      _testEntity(await _getStat(e, movedPath, ''), entName, false);
      await _testFileContents(e, movedPath, 'FILE_1');

      // move dir to local dir (unsafe).
      entName = 'move_dir1';
      src = ['move', 'a', entName].lock;
      dest = ['move', entName].lock;
      movedPath = await e.move(r, src, dest, true);
      final expectedMovedPath = await _getPath(e, destDir, entName);
      assert(movedPath == expectedMovedPath);
      _testEntity(await _getStat(e, movedPath, ''), entName, true);
      await _testFolderWithDefFile(e, movedPath);

      // move file to root dir (unsafe).
      entName = 'move.file2';
      src = ['move', 'a', entName].lock;
      dest = [entName].lock;
      movedPath = await e.move(r, src, dest, false);
      assert(movedPath == await _getPath(e, r, entName));
      _testEntity(await _getStat(e, movedPath, ''), entName, false);
      await _testFileContents(e, movedPath, 'FILE_2');

      // move dir to root dir (unsafe).
      entName = 'move_dir2';
      src = ['move', 'a', entName].lock;
      dest = [entName].lock;
      movedPath = await e.move(r, src, dest, true);
      assert(movedPath == await _getPath(e, r, entName));
      _testEntity(await _getStat(e, movedPath, ''), entName, true);
      await _testFolderWithDefFile(e, movedPath);

      // move and replace (file)
      entName = 'same.file';
      src = ['move', 'a', entName].lock;
      dest = ['move', entName].lock;
      await _createFile(e, srcDir, entName, 'same_new');
      await _createFile(e, destDir, entName, 'same_old');
      movedPath = await e.moveAndReplace(r, src, dest, false);
      assert(movedPath == await _getPath(e, destDir, entName));
      _testEntity(await _getStat(e, movedPath, ''), entName, false);
      await _testFileContents(e, movedPath, 'same_new');

      // move and replace (dir)
      entName = 'same.dir';
      src = ['move', 'a', entName].lock;
      dest = ['move', entName].lock;
      await _createFolderWithDefFile(e, srcDir, entName);
      await _createFolderWithDefFile(e, destDir, entName);
      movedPath = await e.moveAndReplace(r, src, dest, true);
      assert(movedPath == await _getPath(e, destDir, entName));
      _testEntity(await _getStat(e, movedPath, ''), entName, true);
      await _testFolderWithDefFile(e, movedPath);

      // move and keep both (file)
      entName = 'both.file';
      src = ['move', 'a', entName].lock;
      dest = ['move', entName].lock;
      var newEntName = 'both (2).file';
      await _createFile(e, srcDir, entName, 'same_new');
      await _createFile(e, destDir, entName, 'same_old');
      var moveRes = await e.moveAndKeepBoth(r, src, dest, false);
      _testEntity(await _getStat(e, moveRes.path, ''), newEntName, false);
      assert(moveRes.name == newEntName);
      await _testFileContents(e, moveRes.path, 'same_new');
      // old entity is not deleted.
      await _testFileContents(
          e, await _getPath(e, destDir, entName), 'same_old');

      // move and keep both (dir)
      entName = 'both.dir';
      src = ['move', 'a', entName].lock;
      dest = ['move', entName].lock;
      newEntName = 'both.dir (2)';
      await _createFolderWithDefFile(e, srcDir, entName);
      await _createFolderWithDefFile(e, destDir, entName);
      moveRes = await e.moveAndKeepBoth(r, src, dest, true);
      assert(moveRes.name == newEntName);
      _testEntity(await _getStat(e, moveRes.path, ''), newEntName, true);
      await _testFolderWithDefFile(e, moveRes.path);
      // old entity is not deleted.
      await _testFolderWithDefFile(e, await _getPath(e, destDir, entName));

      // delete
      await e.delete((await e.child(r, relPath: _genRelPath('move')))!, true);
      await e.deletePathIfExists(r, relPath: _genRelPath('___.txt'));
      await e.deletePathIfExists(r, relPath: _genRelPath('move.file2'));
      await e.deletePathIfExists(r, relPath: _genRelPath('move_dir2'));
      await e.deletePathIfExists(r, relPath: _genRelPath('nextAvailableName'));
      final contents = _refineContents(await e.listDir(r));
      assert(contents.isEmpty);
    });

    await ns.run();
  }

  void _testEntity(BFEntity? ent, String name, bool isDir) {
    if (ent == null) {
      assert(false);
      return;
    }
    assert(ent.isDir == isDir);
    assert(ent.name == name);
    if (!isDir) {
      assert(ent.lastMod != null);
      assert(ent.length > 0);
    }
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
      throw Exception('stat is null');
    }
    return stat;
  }

  Future<BFPath> _getPath(BFEnv e, BFPath root, String relPath) async {
    final stat = await _getStat(e, root, relPath);
    return stat.path;
  }

  Future<BFPath> _createFile(
      BFEnv e, BFPath dir, String fileName, String content) async {
    final bytes = Uint8List.fromList(utf8.encode(content));
    return await e.slowWriteFileBytes(dir, fileName, bytes);
  }

  Future<BFPath> _createFolderWithDefFile(
      BFEnv e, BFPath root, String folderName) async {
    final dirPath = await e.mkdir(root, folderName);
    await _createFile(e, dirPath, defFolderContentFile, defStringContents);
    return dirPath;
  }

  Future<void> _testFileContents(BFEnv e, BFPath file, String expected) async {
    final actual = utf8.decode(await e.slowReadFileBytes(file));
    assert(actual == expected);
  }

  Future<void> _testFolderWithDefFile(BFEnv e, BFPath dirPath) async {
    final files = await e.listDir(dirPath);
    assert(files.length == 1);
    _testEntity(files[0], defFolderContentFile, false);
    await _testFileContents(e, files[0].path, defStringContents);
  }

  List<BFEntity> _refineContents(List<BFEntity> entities) {
    final filtered =
        entities.where((e) => !ignoredFiles.contains(e.name)).toList();
    return filtered.sorted((a, b) => a.name.compareTo(b.name));
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

  Future<Uint8List> slowReadFileBytes(BFPath file) async {
    if (hasStreamSupport()) {
      final List<int> result = [];
      final stream = await readFileStream(file);
      await for (var chunk in stream) {
        result.addAll(chunk);
      }
      return Uint8List.fromList(result);
    }
    final tmp = tmpPath();
    await copyToLocalFile(file, tmp);
    return File(tmp).readAsBytes();
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
    return pasteLocalFile(tmp, dir, unsafeName);
  }
}
