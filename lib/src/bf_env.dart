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

  Future<BFPath> ensureDir(
    BFPath dir,
    String name,
  );
  Future<BFPath> ensureDirs(BFPath dir, IList<String> path);

  Future<BFPath> rename(BFPath path, String newName, bool isDir);

  Future<BFPath> moveToDir(
      BFPath root, IList<String> src, IList<String> destDir, bool isDir);

  bool hasStreamSupport();

  Future<Stream<List<int>>> readFileStream(BFPath path);
  Future<BFOutStream> writeFileStream(BFPath dir, String unsafeName);
}
