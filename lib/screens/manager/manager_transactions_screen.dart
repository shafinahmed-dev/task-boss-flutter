import 'package:flutter/material.dart';

class ManagerTransactionsScreen extends StatelessWidget {
  const ManagerTransactionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transactions', style: TextStyle(color: Colors.white)), backgroundColor: const Color(0xFF1E2638)),
      body: const Center(child: Text('Transactions Placeholder')),
    );
  }
}
