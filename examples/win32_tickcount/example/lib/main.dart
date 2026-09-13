import 'package:flutter/material.dart';
import 'package:win32_tickcount/win32_tickcount.dart';

void main() {
  runApp(const MaterialApp(home: _Home()));
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    final ticks = GetTickCount64();
    return Scaffold(
      appBar: AppBar(title: const Text('win32_tickcount')),
      body: Center(child: Text('GetTickCount64: $ticks')),
    );
  }
}
