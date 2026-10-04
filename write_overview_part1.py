with open('lib/screens/manager/manager_overview_screen.dart', 'w', encoding='utf-8') as f:
    f.write('''import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:task_boss/services/app_state.dart';
import 'manager_transactions_screen.dart';
import 'manager_staff_screen.dart';

class ManagerOverviewScreen extends StatefulWidget {
  const ManagerOverviewScreen({super.key});

  @override
  State<ManagerOverviewScreen> createState() => _ManagerOverviewScreenState();
}

class _ManagerOverviewScreenState extends State<ManagerOverviewScreen> {
  bool _isCashMasked = false;
  String _selectedPeriod = 'month';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = context.read<AppState>();
      app.fetchManagerOverview(period: _selectedPeriod);
      app.fetchManagerConcernEmployees();
    });
  }

  String _formatAmount(dynamic val) {
    if (_isCashMasked) return '••••••';
    if (val == null) return '0.00';
    final n = (val is num) ? val.toDouble() : (double.tryParse(val.toString()) ?? 0.0);
    return n.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    const navyColor = Color(0xFF1E2638);
    const darkSlate = Color(0xFF0F172A);
    const borderColor = Color(0xFFE2E8F0);

    final app = context.watch<AppState>();
    final ov = app.managerOverviewData;
    final company = ov['company'] as Map<String, dynamic>? ?? {};
    final concerns = (ov['assignedConcerns'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];
    final topEmployees = (ov['topEmployees'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];
    final recentTx = (ov['recentTransactions'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];
    
    final companyTotalBalance = company['totalBalance'] ?? 0.0;
    final inflow = ov['totalInflow'] ?? 0.0;
    final outflow = ov['totalOutflow'] ?? 0.0;
    final personalCash = ov['personalCash'] ?? 0.0;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await app.fetchManagerOverview(period: _selectedPeriod);
            await app.fetchManagerConcernEmployees();
          },
          color: navyColor,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: navyColor, borderRadius: BorderRadius.circular(16)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () => _showProfileBottomSheet(context, app),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                        child: Row(
                          children: [
                            const CircleAvatar(radius: 12, backgroundColor: darkSlate, child: Icon(Icons.person, size: 14, color: Colors.white)),
                            const SizedBox(width: 8),
                            Text(app.user?.name ?? 'Manager', style: const TextStyle(color: darkSlate, fontSize: 13, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_drop_down, size: 18, color: darkSlate),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => setState(() => _isCashMasked = !_isCashMasked),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                            child: Row(
                              children: [
                                Text('৳ ${_formatAmount(personalCash)}', style: const TextStyle(color: darkSlate, fontSize: 13, fontWeight: FontWeight.bold)),
                                const SizedBox(width: 6),
                                Icon(_isCashMasked ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 14, color: const Color(0xFF64748B)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                          child: const Icon(Icons.notifications_outlined, size: 18, color: darkSlate),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
''')
print('Overview part 1 written')
