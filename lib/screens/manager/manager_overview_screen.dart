import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().fetchManagerOverview();
    });
  }

  String _fmt(dynamic val) {
    if (val == null) return '0.00';
    final n = (val is num) ? val.toDouble() : (double.tryParse(val.toString()) ?? 0.0);
    return n.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final ov = app.managerOverviewData;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Manager Overview', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E2638),
        actions: [IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: () => app.fetchManagerOverview())],
      ),
      body: RefreshIndicator(
        onRefresh: () => app.fetchManagerOverview(),
        color: const Color(0xFF1E2638),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF1E2638), Color(0xFF0F172A)]), borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Total Concern Balance', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                  const SizedBox(height: 8),
                  Text('৳ ${_fmt(ov['totalBalance'])}', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: Text('Inflow: ৳ ${_fmt(ov['totalInflow'])}', style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold))),
                      Expanded(child: Text('Outflow: ৳ ${_fmt(ov['totalOutflow'])}', style: const TextStyle(color: Color(0xFFF87171), fontWeight: FontWeight.bold))),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E2638), foregroundColor: Colors.white),
                    icon: const Icon(Icons.receipt_long, size: 18),
                    label: const Text('Transactions'),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManagerTransactionsScreen())),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1E2638)),
                    icon: const Icon(Icons.people, size: 18),
                    label: const Text('Staff Directory'),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ManagerStaffScreen())),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text('Staff Directory', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
            const SizedBox(height: 8),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: app.managerEmployeesList.length > 5 ? 5 : app.managerEmployeesList.length,
              itemBuilder: (context, i) {
                final e = app.managerEmployeesList[i];
                return ListTile(
                  title: Text(e['name'] ?? 'Staff', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(e['designation'] ?? 'Staff'),
                  trailing: Text('৳ ${_fmt(e['balance'])}', style: const TextStyle(fontWeight: FontWeight.bold)),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
