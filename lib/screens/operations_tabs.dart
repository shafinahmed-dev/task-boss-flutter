import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:task_boss/services/app_state.dart';
import 'package:task_boss/theme.dart';
import 'package:task_boss/screens/capture_movement_screen.dart';
import 'package:task_boss/screens/custody_handover_screen.dart';
import 'package:task_boss/screens/history_screen.dart';

class OperationsTabs extends StatelessWidget {
  const OperationsTabs({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final userName = app.user?.name ?? 'User';
    final balance = app.balance;

    return DefaultTabController(
      length: 3,
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
                // Left Pill – User Info
                Container(
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
                    ],
                  ),
                ),

                // Right Pill – Balance
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                  child: Text(
                    '৳${balance.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827),
                    ),
                  ),
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
                Tab(text: 'History'),
              ],
            ),
          ),

          // ── Tab Content ────────────────────────────────────────────────
          const Expanded(
            child: TabBarView(
              children: [
                CaptureMovementScreen(),
                CustodyHandoverScreen(),
                HistoryScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
