import 'package:darwin_url/darwin_url.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:path/path.dart' as p;

final DarwinUrl _darwinUrlPlugin = DarwinUrl();

class BFDuplicateItemException implements Exception {
  final String itemName;

  BFDuplicateItemException(this.itemName);

  @override
  String toString() {
    return 'BFDuplicateItemExp(itemName: $itemName)';
  }
}

class BFNoAvailableNameException implements Exception {}

class BFNoPermissionException implements Exception {}

/// Abstract class for all file system paths.
abstract class BFPath {
  bool get isUri;
}

/// Local file system path.
class BFLocalPath extends BFPath {
  /// Local file system path string.
  final String path;

  @override
  bool get isUri => false;

  BFLocalPath(this.path);

  @override
  String toString() {
    return path;
  }

  @override
  bool operator ==(Object other) {
    return other is BFLocalPath && path == other.path;
  }

  @override
  int get hashCode => path.hashCode;
}

/// Scoped file system path. Used in [BFNsfcEnv] and [BFSfsEnv].
class BFScopedPath extends BFPath {
  /// Scoped ID.
  /// In [BFNsfcEnv], it is the Apple file system URL.
  /// In [BFSfsEnv], it is the Android file system URI.
  final String id;

  @override
  bool get isUri => true;

  BFScopedPath(this.id);

  @override
  String toString() {
    return id.toString();
  }

  @override
  bool operator ==(Object other) {
    return other is BFScopedPath && id == other.id;
  }

  @override
  int get hashCode => id.hashCode;
}

const _pathHeadLocal = 'L';
const _pathHeadScoped = 'S';

/// Decodes a string to a [BFPath].
BFPath decodeStringToBFPath(String s) {
  if (s.startsWith(_pathHeadLocal)) {
    return BFLocalPath(s.substring(1));
  }
  return BFScopedPath(s.substring(1));
}

extension BFPathExtension on BFPath {
  /// Returns the local path if it is a [BFLocalPath]. Otherwise, throws an exception.
  String localPath() {
    if (this is BFLocalPath) {
      return (this as BFLocalPath).path;
    }
    throw Exception('$this is not a local path');
  }

  /// Returns the scoped ID if it is a [BFScopedPath]. Otherwise, throws an exception.
  String scopedUri() {
    if (this is BFScopedPath) {
      return (this as BFScopedPath).id;
    }
    throw Exception('$this is not a scoped path');
  }

  /// Only for Apple platforms. Joins a relative path to the scoped path.
  Future<BFPath> iosJoinRelPath(IList<String> relPath, bool isDir) async {
    final url = await _darwinUrlPlugin.append(
      scopedUri(),
      relPath.unlock,
      isDir: isDir,
    );
    return BFScopedPath(url);
  }

  /// Only for local paths. Joins a relative path to the local path.
  BFPath localJoinRelPath(String relPath) {
    final path = p.join(localPath(), relPath);
    return BFLocalPath(path);
  }

  /// Encodes the path to a string.
  String encodeToString() {
    if (this is BFLocalPath) {
      return '$_pathHeadLocal${toString()}';
    }
    return '$_pathHeadScoped${toString()}';
  }
}
