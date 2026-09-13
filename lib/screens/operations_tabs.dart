import 'package:flutter/material.dart';
import 'package:task_boss/theme.dart';
import 'package:task_boss/screens/capture_movement_screen.dart';
import 'package:task_boss/screens/custody_handover_screen.dart';
import 'package:task_boss/screens/history_screen.dart';

class OperationsTabs extends StatelessWidget {
  const OperationsTabs({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
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
