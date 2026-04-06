import 'package:flutter/material.dart';

/// İstatistik ekranı iskeleti.
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('İstatistik'),
      ),
      body: const Center(
        child: Text('İstatistik içeriği yakında.'),
      ),
    );
  }
}
