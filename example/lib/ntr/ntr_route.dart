import 'package:flutter/material.dart';

import 'ntr_suite.dart';

class NTRRoute extends StatefulWidget {
  final NTRSuite suite;
  const NTRRoute({super.key, required this.suite});

  @override
  State<NTRRoute> createState() => _NTRRouteState();
}

class _NTRRouteState extends State<NTRRoute> {
  String _msg = '';

  @override
  Widget build(BuildContext context) {
    final Widget scaffold = Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text('${widget.suite.suiteName} NTests'),
      ),
      body: Center(
        child: Text(_msg),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final suite = widget.suite;
          suite.onLog = (s) => setState(() => _msg = s);
          await suite.run();
        },
        child: const Icon(Icons.run_circle_outlined),
      ),
    );
    return scaffold;
  }
}
