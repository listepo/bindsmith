// ignore_for_file: unused_element
import 'package:dbus_greeter/dbus_greeter.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MaterialApp(home: _Home()));
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('dbus_greeter')),
      body: const Center(child: Text('D-Bus Greeter via bindsmith')),
    );
  }
}

/// Keeps the generated API in the tree so `flutter build` compiles it.
Future<String> _touch(ComExampleGreeter greeter) => greeter.getVersion();
