// ignore_for_file: unused_element
import 'package:flutter/material.dart';
import 'package:swift_volume/swift_volume.dart';

void main() {
  runApp(const MaterialApp(home: _Home()));
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('swift_volume')),
      body: Center(child: Text('VolumeKit via bindsmith')),
    );
  }
}

/// Keeps the generated API in the tree so `flutter build` compiles it.
VolumeWrapper _touch() => VolumeWrapper.alloc();
