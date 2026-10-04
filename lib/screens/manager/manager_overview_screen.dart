import 'package:flutter/material.dart';

class ManagerOverviewScreen extends StatelessWidget {
  const ManagerOverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manager Overview', style: TextStyle(color: Colors.white)), backgroundColor: const Color(0xFF1E2638)),
      body: const Center(child: Text('Manager Dashboard Placeholder')),
    );
  }
}
