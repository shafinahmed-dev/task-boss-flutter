import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:task_boss/screens/operations_tabs.dart';
import 'package:task_boss/screens/manager/manager_overview_screen.dart';
import 'package:task_boss/screens/wallets_screen.dart';
import 'package:task_boss/services/app_state.dart';
import 'package:task_boss/screens/account_screen.dart';
import 'package:task_boss/widgets/notifications_sheet.dart';

class ManagerDashboardShell extends StatefulWidget {
  const ManagerDashboardShell({super.key});

  @override
  State<ManagerDashboardShell> createState() => _ManagerDashboardShellState();
}

class _ManagerDashboardShellState extends State<ManagerDashboardShell> {
  int _currentIndex = 1; // Default to Overview (center tab)
  bool _isPersonalBalanceVisible = true;

  final List<Widget> _pages = const [
    OperationsTabs(),
    ManagerOverviewScreen(),
    WalletsScreen(),
  ];

  String _formatAmount(double amount) {
    return amount.toStringAsFixed(2);
  }

  Widget _buildTopBar(AppState appState) {
    return Container(
      color: const Color(0xFF1E2638), // Dark Navy
      child: SafeArea(
        bottom: false, // Don't include bottom safe area in top bar
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              // Profile Capsule
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    children: [
                      const Icon(Icons.account_circle_rounded, size: 18, color: Color(0xFF0F172A)),
                      const SizedBox(width: 6),
                      Text('${appState.currentUser?.name ?? 'Manager'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF64748B)),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              // Personal Balance Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(20)),
                child: Row(
                  children: [
                    Text(
                      _isPersonalBalanceVisible ? '৳ ${_formatAmount(appState.managerPersonalBalance)}' : '৳ ••••••',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => setState(() => _isPersonalBalanceVisible = !_isPersonalBalanceVisible),
                      child: Icon(_isPersonalBalanceVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 16, color: const Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Notification Bell
              InkWell(
                onTap: () => NotificationsSheet.show(context),
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Badge(
                      isLabelVisible: appState.notificationCount > 0,
                      label: Text(
                        '${appState.notificationCount}',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                      backgroundColor: const Color(0xFFEF4444),
                      child: const Icon(
                        Icons.notifications_none_rounded,
                        color: Color(0xFF0F172A),
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: _buildTopBar(appState),
      ),
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
              _buildNavItem(2, Icons.account_balance_wallet_outlined),
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
        color: isSelected ? Colors.white : const Color(0xFF64748B),
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


