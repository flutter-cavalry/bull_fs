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

/// Like [BFPathBundle], but with an extra [name] field.
class BFPathNameBundle {
  final BFEnv env;
  final BFPath path;
  final String name;

  BFPathNameBundle(this.env, this.path, this.name);

  Map<String, dynamic> toJson() => {
    'env': env.envType(),
    'path': path.encodeToString(),
    'name': name,
  };

  BFPathNameBundle.fromJson(Map<String, dynamic> json)
    : env = BFEnvUtil.typeToEnv(json['env'] as BFEnvType),
      path = decodeStringToBFPath(json['path'] as String),
      name = json['name'] as String;
}
