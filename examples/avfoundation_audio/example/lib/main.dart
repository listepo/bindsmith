// ignore_for_file: unused_element
import 'package:avfoundation_audio/avfoundation_audio.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MaterialApp(home: _Home()));
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('avfoundation_audio')),
      body: Center(child: Text('AVFoundation via bindsmith')),
    );
  }
}

/// Keeps the generated API in the tree so `flutter build` compiles it.
BSMAudioPlayer _touch() => BSMAudioPlayer.alloc();
