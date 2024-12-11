import 'package:bull_fs/bull_fs.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:fc_quick_dialog/fc_quick_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FolderRoute extends StatefulWidget {
  final BFEnv env;
  final String name;
  final BFPath path;

  const FolderRoute(
      {super.key, required this.env, required this.name, required this.path});

  @override
  State<FolderRoute> createState() => _FolderRouteState();
}

class _FolderRouteState extends State<FolderRoute> {
  List<BFEntity> _contents = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
      ),
      body: Padding(padding: const EdgeInsets.all(8), child: _buildBody()),
    );
  }

  Future<void> _reload() async {
    try {
      final env = widget.env;
      final contents = await env.listDir(widget.path);
      contents.sort((a, b) {
        if (a.isDir && !b.isDir) {
          return -1;
        }
        if (!a.isDir && b.isDir) {
          return 1;
        }
        return a.name.compareTo(b.name);
      });
      setState(() {
        _contents = contents;
      });
    } catch (err) {
      if (!mounted) {
        return;
      }
      await FcQuickDialog.error(context,
          title: 'Error', error: err, okText: 'OK');
    }
  }

  Widget _buildBody() {
    return Column(
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(widget.path.toString()),
            const SizedBox(width: 10),
            ElevatedButton(
                onPressed: () async {
                  await Clipboard.setData(
                      ClipboardData(text: widget.path.toString()));
                  if (!mounted) {
                    return;
                  }
                  await FcQuickDialog.info(context,
                      title: 'URI copied',
                      content: widget.path.toString(),
                      okText: 'OK');
                },
                child: const Text('Copy BFPath')),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            ElevatedButton(
              onPressed: _reload,
              child: const Text('Reload'),
            ),
            const SizedBox(width: 20),
            ElevatedButton(
              onPressed: () async {
                try {
                  final names = await FcQuickDialog.textInput(context,
                      title: 'Enter names, e.g. a/b/c',
                      okText: 'OK',
                      cancelText: 'Cancel');
                  if (names == null) {
                    return;
                  }
                  final child = await widget.env
                      .child(widget.path, names.split('/').lock);
                  if (!mounted) {
                    return;
                  }
                  if (child == null) {
                    await FcQuickDialog.error(context,
                        title: 'Not found',
                        error: 'Child not found',
                        okText: 'OK');
                  } else {
                    await FcQuickDialog.info(context,
                        title: 'Child found',
                        content: child.toString(),
                        okText: 'OK');
                  }
                } catch (err) {
                  if (!mounted) {
                    return;
                  }
                  await FcQuickDialog.error(context,
                      title: 'Error', error: err, okText: 'OK');
                }
              },
              child: const Text('Find child'),
            ),
            const SizedBox(width: 20),
            ElevatedButton(
              onPressed: () async {
                try {
                  final path = await FcQuickDialog.textInput(context,
                      title: 'Enter a path (e.g. a/b/c)',
                      okText: 'OK',
                      cancelText: 'Cancel');
                  if (path == null) {
                    return;
                  }
                  final components = path.split('/');
                  final uriInfo =
                      await widget.env.mkdirp(widget.path, components.lock);
                  if (!mounted) {
                    return;
                  }
                  await FcQuickDialog.info(context,
                      title: 'Directories created',
                      content: uriInfo.toString(),
                      okText: 'OK');
                  await _reload();
                } catch (err) {
                  if (!mounted) {
                    return;
                  }
                  await FcQuickDialog.error(context,
                      title: 'Error', error: err, okText: 'OK');
                }
              },
              child: const Text('mkdir -p'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Expanded(child: _buildList()),
      ],
    );
  }

  Widget _buildItemView(BFEntity ent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ent.isDir
            ? Row(
                children: [
                  const Icon(Icons.folder),
                  const SizedBox(width: 10),
                  Text(ent.name),
                  const SizedBox(width: 10),
                  IconButton(
                      onPressed: () {
                        final folderRoute = FolderRoute(
                          env: widget.env,
                          path: ent.path,
                          name: ent.name,
                        );
                        Navigator.push<void>(
                          context,
                          MaterialPageRoute(builder: (context) => folderRoute),
                        );
                      },
                      icon: const Icon(Icons.arrow_forward)),
                ],
              )
            : Text(ent.name),
        const SizedBox(height: 10),
        Text(ent.path.toString()),
        if (ent.lastMod != null) ...[
          const SizedBox(height: 10),
          Text('Last modified: ${ent.lastMod}'),
        ],
        const SizedBox(height: 10),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ElevatedButton(
                onPressed: () async {
                  try {
                    if (await FcQuickDialog.confirm(context,
                            title: 'Are you sure you want to delete this item?',
                            yesText: 'Yes',
                            noText: 'No') !=
                        true) {
                      return;
                    }
                    await widget.env.delete(ent.path, ent.isDir);
                    await _reload();
                  } catch (err) {
                    if (!mounted) {
                      return;
                    }
                    await FcQuickDialog.error(context,
                        title: 'Error', error: err, okText: 'OK');
                  }
                },
                child: const Text('Delete')),
            const SizedBox(width: 10),
            ElevatedButton(
                onPressed: () async {
                  try {
                    final st = await widget.env.stat(ent.path, ent.isDir);
                    if (!mounted) {
                      return;
                    }
                    if (st == null) {
                      await FcQuickDialog.info(context,
                          title: 'stat', content: 'null', okText: 'OK');
                      return;
                    }
                    final stringBuilder = StringBuffer();
                    stringBuilder.writeln('Name: ${st.name}');
                    stringBuilder.writeln('Path: ${st.path}');
                    stringBuilder.writeln('Is dir: ${st.isDir}');
                    stringBuilder.writeln('Size: ${st.length}');
                    stringBuilder.writeln('Last modified: ${st.lastMod}');
                    await FcQuickDialog.info(context,
                        title: 'stat',
                        content: stringBuilder.toString(),
                        okText: 'OK');
                  } catch (err) {
                    if (!mounted) {
                      return;
                    }
                    await FcQuickDialog.error(context,
                        title: 'Error', error: err, okText: 'OK');
                  }
                },
                child: const Text('Stat')),
            const SizedBox(width: 10),
            ElevatedButton(
                onPressed: () async {
                  try {
                    final newName = await FcQuickDialog.textInput(context,
                        title: 'Enter a new name',
                        okText: 'OK',
                        cancelText: 'Cancel');
                    if (newName == null) {
                      return;
                    }
                    if (!mounted) {
                      return;
                    }
                    final res = await widget.env
                        .rename(ent.path, ent.isDir, widget.path, newName);
                    if (!mounted) {
                      return;
                    }
                    await FcQuickDialog.info(context,
                        title: 'Renamed',
                        content: res.toString(),
                        okText: 'OK');
                    await _reload();
                  } catch (err) {
                    if (!mounted) {
                      return;
                    }
                    await FcQuickDialog.error(context,
                        title: 'Error', error: err, okText: 'OK');
                  }
                },
                child: const Text('Rename')),
          ],
        )
      ],
    );
  }

  Widget _buildList() {
    return SingleChildScrollView(
      child: Column(
        children: _contents
            .map((df) => Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(5),
                ),
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 10),
                child: _buildItemView(df)))
            .toList(),
      ),
    );
  }
}
