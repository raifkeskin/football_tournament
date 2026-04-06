import 'package:flutter/material.dart';

/// Gruplar ekranı iskeleti.
class GroupsScreen extends StatelessWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gruplar'),
      ),
      body: const Center(
        child: Text('Gruplar içeriği yakında.'),
      ),
    );
  }
}
