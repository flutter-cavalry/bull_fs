import '../bull_fs.dart';

/// [BFPathBundle] is a bundle of [BFEnv] and [BFPath].
class BFPathBundle {
  final BFEnv env;
  final BFPath path;

  BFPathBundle(this.env, this.path);

  Map<String, dynamic> toJson() => {
        'env': env.envType(),
        'path': path.encodeToString(),
      };

  BFPathBundle.fromJson(Map<String, dynamic> json)
      : env = BFEnvUtil.typeToEnv(json['env'] as BFEnvType),
        path = decodeStringToBFPath(json['path'] as String);
}
