import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../bull_fs.dart';

/// Represents a [BFPath] and a file name.
class BFPathAndName {
  final BFPath path;

  final String fileName;

  BFPathAndName(this.path, this.fileName);

  @override
  String toString() {
    return '$path|$fileName';
  }

  Map<String, dynamic> toJson() => {
    'path': path.encodeToString(),
    'fileName': fileName,
  };

  BFPathAndName.fromJson(Map<String, dynamic> json)
    : path = decodeStringToBFPath(json['path'] as String),
      fileName = json['fileName'] as String;
}

/// A bundle that contains a [BFEnv], a [BFPath], and a file name.
class BFPathBundle {
  final BFEnv env;
  final BFPath path;
  final String fileName;

  BFPathBundle(this.env, this.path, this.fileName);

  Map<String, dynamic> toJson() => {
    'env': env.envType(),
    'path': path.encodeToString(),
    'fileName': fileName,
  };

  BFPathBundle.fromJson(Map<String, dynamic> json)
    : env = BFEnvUtil.typeToEnv(json['env'] as BFEnvType),
      path = decodeStringToBFPath(json['path'] as String),
      fileName = json['fileName'] as String;
}

// Stores a path and its relative path in a directory.
class BFPathAndDirRelPath {
  /// The path.
  final BFPath path;

  /// The relative path in a directory.
  final IList<String> dirRelPath;

  BFPathAndDirRelPath(this.path, this.dirRelPath);

  @override
  String toString() {
    var res = path.toString();
    if (dirRelPath.isNotEmpty) {
      res += '|dir_rel: ${dirRelPath.join('/')}';
    }
    return res;
  }
}
