import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:task_boss/services/app_state.dart';
import 'manager_transactions_screen.dart';

class ManagerOverviewScreen extends StatefulWidget {
  const ManagerOverviewScreen({super.key});

  @override
  State<ManagerOverviewScreen> createState() => _ManagerOverviewScreenState();
}

class _ManagerOverviewScreenState extends State<ManagerOverviewScreen> {
  bool _isCashMasked = true;
  String? _selectedCompanyId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().fetchManagerOverview();
    });
  }

  String _formatAmount(dynamic val) {
    if (val == null) return '0.00';
    final numVal = (val is num) ? val.toDouble() : (double.tryParse(val.toString()) ?? 0.0);
    return numVal.toStringAsFixed(2);
  }
  // ... rest of the implementation
}
