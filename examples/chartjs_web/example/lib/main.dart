// ignore_for_file: unused_element
import 'package:chartjs_web/chartjs_web.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MaterialApp(home: _Home()));
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('chartjs_web')),
      body: Center(child: Text('Chart.js via bindsmith')),
    );
  }
}

/// Keeps the generated API in the tree so `flutter build` compiles it.
Chart _touch() => Chart(
  null,
  ChartConfiguration(
    type: 'bar',
    data: ChartData(datasets: <ChartDataset>[]),
  ),
);
