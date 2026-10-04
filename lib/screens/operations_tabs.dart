import 'package:flutter/material.dart';
import 'package:task_boss/theme.dart';
import 'package:task_boss/screens/capture_movement_screen.dart';
import 'package:task_boss/screens/custody_handover_screen.dart';

class OperationsTabs extends StatelessWidget {
  const OperationsTabs({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
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

