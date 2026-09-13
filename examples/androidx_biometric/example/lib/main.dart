// ignore_for_file: unused_element
import 'package:androidx_biometric/androidx_biometric.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MaterialApp(home: _Home()));
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('androidx_biometric')),
      body: Center(child: Text('AndroidX Biometric via bindsmith')),
    );
  }
}

/// Keeps the generated API in the tree so `flutter build` compiles it.
int _touch(BiometricManager manager) => manager.canAuthenticate();
