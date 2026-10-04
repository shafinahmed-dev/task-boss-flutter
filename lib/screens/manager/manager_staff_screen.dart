import 'package:flutter/material.dart';

class ManagerStaffScreen extends StatelessWidget {
  const ManagerStaffScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Staff Directory', style: TextStyle(color: Colors.white)), backgroundColor: const Color(0xFF1E2638)),
      body: const Center(child: Text('Staff Directory Placeholder')),
    );
  }
}