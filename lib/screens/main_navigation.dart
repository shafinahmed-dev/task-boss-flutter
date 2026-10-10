import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:task_boss/services/app_state.dart';
import 'package:task_boss/screens/manager/manager_dashboard_shell.dart';
import 'package:task_boss/screens/suite/suite_governance_screen.dart';

import 'package:task_boss/screens/operations_tabs.dart';
import 'package:task_boss/screens/wallets_screen.dart';
import 'package:task_boss/screens/account_screen.dart';
import 'package:task_boss/widgets/notifications_sheet.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().initialize();
    });
  }

  int _currentIndex = 0;
  bool _isBalanceVisible = true;

  final List<Widget> _pages = [
    const OperationsTabs(),
    const WalletsScreen(),
  ];

  String _formatAmount(double amount) {
    return amount.toStringAsFixed(2);
  }

  Widget _buildTopBar(AppState appState) {
    return Container(
      color: const Color(0xFF1E2638), // Dark Navy
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              // Profile Capsule
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.account_circle_rounded, size: 18, color: Color(0xFF0F172A)),
                      const SizedBox(width: 6),
                      Text(
                        appState.currentUser?.name ?? 'Employee',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF64748B)),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              // Personal Balance Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Text(
                      _isBalanceVisible 
                          ? '৳ ${_formatAmount(appState.userBalance ?? appState.balance ?? 0.0)}' 
                          : '৳ ••••••',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => setState(() => _isBalanceVisible = !_isBalanceVisible),
                      child: Icon(
                        _isBalanceVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        size: 16,
                        color: const Color(0xFF64748B),
                      ),
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
                        size: 18,
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
    final role = appState.user?.role;

    if (role == 'SUITE_ADMIN') {
      return SuiteGovernanceScreen();
    }
    if (role == 'MANAGER') {
      return ManagerDashboardShell();
    }

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
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1E293B), Color(0xFF111827)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          border: Border(
            top: BorderSide(
              color: Colors.white.withValues(alpha: 0.08),
              width: 0.8,
            ),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (idx) => setState(() => _currentIndex = idx),
          selectedItemColor: Colors.white,
          unselectedItemColor: const Color(0xFF94A3B8),
          backgroundColor: Colors.transparent,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          showSelectedLabels: false,
          showUnselectedLabels: false,
          iconSize: 26,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.sync_alt_rounded),
              label: 'Operations',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.account_balance_wallet_outlined),
              label: 'Wallets',
            ),
          ],
        ),
      ),
    );
  }
}
