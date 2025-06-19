import '../bull_fs.dart';

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
