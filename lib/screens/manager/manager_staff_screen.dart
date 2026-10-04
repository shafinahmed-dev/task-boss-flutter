import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:task_boss/services/app_state.dart';

class ManagerStaffScreen extends StatelessWidget {
  const ManagerStaffScreen({super.key});

  String _formatAmount(dynamic val) {
    if (val == null) return '0.00';
    final n = (val is num) ? val.toDouble() : (double.tryParse(val.toString()) ?? 0.0);
    return n.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final employees = app.managerEmployeesList;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Staff Directory', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E2638),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: () => app.fetchManagerOverview(),
        color: const Color(0xFF1E2638),
        child: employees.isEmpty
            ? const Center(child: Text('No field staff provisioned.', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: employees.length,
                itemBuilder: (context, index) {
                  final e = employees[index];
                  final name = e['name'] ?? 'Staff';
                  final designation = e['designation'] ?? 'Staff';
                  final department = e['department'] ?? 'General';
                  final balance = e['balance'] ?? 0.0;
                  final initials = name.isNotEmpty ? name.substring(0, 1).toUpperCase() : 'S';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        CircleAvatar(radius: 20, backgroundColor: const Color(0xFF1E2638), child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(name, style: const TextStyle(color: Color(0xFF0F172A), fontSize: 14, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text('$designation • $department', style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                          ]),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
                          child: Text('৳ ${_formatAmount(balance)}', style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
