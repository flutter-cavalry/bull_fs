import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'types.dart';

enum BFEnvType { local, saf, icloud }

abstract class BFEnv {
  BFEnvType envType();
  bool isScoped();

  Future<List<BFEntity>> listDir(BFPath path, {bool? recursive});

  Future<void> copyToLocalFile(BFPath src, String dest);
  Future<BFPath> pasteLocalFile(String localSrc, BFPath dir, String unsafeName);

  Future<void> delete(BFPath path, bool isDir);

  Future<BFEntity?> stat(BFPath path, {IList<String>? relPath});

  Future<BFPath> ensureDirCore(
    BFPath dir,
    String name,
  );
  Future<BFPath> ensureDirs(BFPath dir, IList<String> path);

  Future<BFPath> ensureDir(BFPath dir, String name) async {
    final st = await stat(dir, relPath: [name].lock);
    if (st != null) {
      if (st.isDir) {
        return st.path;
      } else {
        throw Exception('Path exists but is not a directory: ${st.path}');
      }
    }
    return ensureDirCore(dir, name);
  }

  Future<BFPath> renameCore(
      BFPath parent, BFPath item, String newName, bool isDir);

  Future<BFPath> rename(
      BFPath parent, BFPath item, String newName, bool isDir) async {
    final st = await stat(item);
    if (st == null) {
      throw Exception('Path does not exist: $item');
    }
    final newSt = await stat(parent, relPath: [newName].lock);
    if (newSt != null) {
      throw Exception('Path already exists: ${newSt.path}');
    }
    return renameCore(parent, item, newName, isDir);
  }

  Future<BFPath> moveToDir(
      BFPath root, IList<String> src, IList<String> destDir, bool isDir);

  bool hasStreamSupport();

  Future<Stream<List<int>>> readFileStream(BFPath path);
  Future<BFOutStream> writeFileStream(BFPath dir, String unsafeName);
}
