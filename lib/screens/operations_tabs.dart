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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: AppTheme.primaryGradientFallback,
                      child: Text(
                        userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Hello,', style: TextStyle(fontSize: 12, color: AppTheme.secondaryText)),
                        Text(
                          userName,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.primaryText),
                        ),
                      ],
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Total Balance', style: TextStyle(fontSize: 12, color: AppTheme.secondaryText)),
                    Text(
                      '৳${balance.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppTheme.primaryText),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            color: AppTheme.canvas,
            child: const TabBar(
              labelColor: AppTheme.primaryGradientFallback,
              unselectedLabelColor: AppTheme.secondaryText,
              indicatorColor: AppTheme.primaryGradientFallback,
              indicatorWeight: 3,
              labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              tabs: [
                Tab(text: 'Activity'),
                Tab(text: 'Handover'),
                Tab(text: 'History'),
              ],
            ),
          ),
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
