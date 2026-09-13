import 'package:flutter/material.dart';
import 'package:sqlite_desktop/sqlite_desktop.dart';

void main() {
  runApp(const MaterialApp(home: _Home()));
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('sqlite_desktop')),
      body: Center(child: Text(sqlite3_libversion())),
    );
  }
}
