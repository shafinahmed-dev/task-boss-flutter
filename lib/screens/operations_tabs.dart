import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:task_boss/services/app_state.dart';
import 'package:task_boss/theme.dart';
import 'package:task_boss/screens/account_screen.dart';
import 'package:task_boss/screens/capture_movement_screen.dart';
import 'package:task_boss/screens/custody_handover_screen.dart';
import 'package:task_boss/screens/notifications_screen.dart';

class OperationsTabs extends StatefulWidget {
  const OperationsTabs({super.key});

  @override
  State<OperationsTabs> createState() => _OperationsTabsState();
}

class _OperationsTabsState extends State<OperationsTabs> {
  bool _showBalance = false;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _toggleBalance() {
    _hideTimer?.cancel();
    if (!_showBalance) {
      setState(() {
        _showBalance = true;
      });
      _hideTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() {
            _showBalance = false;
          });
        }
      });
    } else {
      setState(() {
        _showBalance = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final userName = app.user?.name ?? 'User';
    final balance = app.balance;
    final pendingCount = app.pendingCount;

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          // ── Dual Floating Pills Header ─────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF161F2E),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Left Pill – User Info (Navigates to AccountScreen)
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AccountScreen(),
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Dark circular avatar
                        Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            color: AppTheme.slateMid,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          userName,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: Color(0xFF475569),
                        ),
                      ],
                    ),
                  ),
                ),

                // Right Group – Interactive Private Balance Pill & Notification Bell
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Interactive Private Balance Pill
                    GestureDetector(
                      onTap: _toggleBalance,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          transitionBuilder: (child, animation) => FadeTransition(
                            opacity: animation,
                            child: child,
                          ),
                          child: _showBalance
                              ? Row(
                                  key: const ValueKey('balance_visible'),
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '৳${balance.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF111827),
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    const Icon(
                                      Icons.visibility_outlined,
                                      size: 14,
                                      color: Color(0xFF64748B),
                                    ),
                                  ],
                                )
                              : const Row(
                                  key: ValueKey('balance_hidden'),
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '৳ ••••••',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.1,
                                        color: Color(0xFF111827),
                                      ),
                                    ),
                                    SizedBox(width: 5),
                                    Icon(
                                      Icons.visibility_off_outlined,
                                      size: 14,
                                      color: Color(0xFF64748B),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 10),

                    // Notification Bell Icon with Badge
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const NotificationsScreen(),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const Icon(
                              Icons.notifications_outlined,
                              color: Colors.white,
                              size: 22,
                            ),
                            if (pendingCount > 0)
                              Positioned(
                                right: 0,
                                top: 0,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEF4444),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFF161F2E),
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Tab Bar ────────────────────────────────────────────────────
          Container(
            color: AppTheme.canvas,
            child: const TabBar(
              labelColor: AppTheme.slateDark,
              unselectedLabelColor: AppTheme.secondaryText,
              indicatorColor: AppTheme.slateDark,
              indicatorWeight: 3,
              labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              tabs: [
                Tab(text: 'Activity'),
                Tab(text: 'Handover'),
              ],
            ),
          ),

          // ── Tab Content ────────────────────────────────────────────────
          const Expanded(
            child: TabBarView(
              children: [
                CaptureMovementScreen(),
                CustodyHandoverScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
