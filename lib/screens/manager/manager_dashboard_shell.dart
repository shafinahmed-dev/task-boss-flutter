import 'package:flutter/material.dart';
import 'package:task_boss/screens/manager/manager_overview_screen.dart';
import 'package:task_boss/screens/manager/manager_transactions_screen.dart';
import 'package:task_boss/screens/manager/manager_staff_screen.dart';

class ManagerDashboardShell extends StatefulWidget {
  const ManagerDashboardShell({super.key});

  @override
  State<ManagerDashboardShell> createState() => _ManagerDashboardShellState();
}

class _ManagerDashboardShellState extends State<ManagerDashboardShell> {
  int _currentIndex = 1; // Default to Overview (center tab)

  final List<Widget> _pages = [
    const ManagerTransactionsScreen(),
    const ManagerOverviewScreen(),
    const ManagerStaffScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (idx) => setState(() => _currentIndex = idx),
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF1E2638), // Dark Navy
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.sync_alt_rounded), label: 'Transactions'),
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), label: 'Overview'),
          BottomNavigationBarItem(icon: Icon(Icons.group_outlined), label: 'Staff'),
        ],
      ),
    );
  }
}
