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
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1E2638), // Dark Navy
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.swap_horiz_rounded),
              _buildCenterElevatedButton(),
              _buildNavItem(2, Icons.people_alt_outlined),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData iconData) {
    final isSelected = _currentIndex == index;
    return IconButton(
      icon: Icon(
        iconData,
        color: isSelected ? Colors.white : Colors.grey,
        size: 28,
      ),
      onPressed: () => setState(() => _currentIndex = index),
    );
  }

  Widget _buildCenterElevatedButton() {
    final isSelected = _currentIndex == 1;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = 1),
      child: Container(
        width: 56,
        height: 56,
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A), // Dark slate
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: isSelected ? Colors.white : Colors.transparent,
            width: 2,
          ),
        ),
        child: const Icon(
          Icons.keyboard_arrow_up_rounded,
          color: Colors.white,
          size: 32,
        ),
      ),
    );
  }
}

