import 'package:bull_fs/bull_fs.dart';
import 'package:example/bf_test_route.dart';
import 'package:example/folder_route.dart';
import 'package:fast_file_picker/fast_file_picker.dart';
import 'package:fc_quick_dialog/fc_quick_dialog.dart';
import 'package:flutter/material.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BullFS Example'),
      ),
      body: Padding(
          padding: const EdgeInsets.all(10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              OutlinedButton(
                  onPressed: () => _openExample(context),
                  child: Text('Examples (Pick a folder first)')),
              const SizedBox(height: 10),
              OutlinedButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (context) => const BFTestRoute())),
                  child: Text('Tests')),
            ],
          )),
    );
  }

  Future<void> _openExample(BuildContext context) async {
    try {
      final pickerResult =
          await FastFilePicker.pickFolder(writePermission: true);
      if (pickerResult == null) {
        return;
      }
      final bfInit = await BFEnvUtil.envFromDirectory(
          path: pickerResult.path, uri: pickerResult.uri);
      if (!context.mounted) {
        return;
      }
      Navigator.of(context).push(MaterialPageRoute(
          builder: (context) => FolderRoute(
                env: bfInit.env,
                name: pickerResult.name,
                path: bfInit.path,
              )));
    } catch (e) {
      if (!context.mounted) {
        return;
      }
      await FcQuickDialog.error(context, error: e, okText: 'OK');
    }
  }
}
