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
  static const Color navyColor = Color(0xFF0F172A);
  static const Color darkSlate = Color(0xFF0F172A);
  static const Color borderColor = Color(0xFFE2E8F0);

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
                            Text(app.currentUser?.name ?? 'Manager', style: const TextStyle(color: darkSlate, fontSize: 13, fontWeight: FontWeight.bold)),
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
              const SizedBox(height: 16),

              if (concerns.isNotEmpty) ...[
                SizedBox(
                  height: 44,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: concerns.length,
                    itemBuilder: (context, index) {
                      final c = concerns[index];
                      final isSelected = c['id'] == (app.selectedManagerCompanyId ?? concerns.first['id']);
                      return GestureDetector(
                        onTap: () => app.selectManagerCompany(c['id']),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected ? darkSlate : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: isSelected ? Colors.transparent : borderColor),
                          ),
                          child: Center(
                            child: Text(
                              c['name'] ?? 'Concern',
                              style: TextStyle(
                                color: isSelected ? Colors.white : const Color(0xFF64748B),
                                fontSize: isSelected ? 14 : 13,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: darkSlate,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      company['name'] ?? 'Consolidated Concern',
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '৳ ${_formatAmount(companyTotalBalance)}',
                      style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Consolidated cash held across active custodians',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildPeriodChip('Today', 'today', app),
                  _buildPeriodChip('This Week', 'week', app),
                  _buildPeriodChip('This Month', 'month', app),
                  _buildPeriodChip('All Time', 'all', app),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: const Color(0xFF10B981).withOpacity(0.1), shape: BoxShape.circle),
                            child: const Icon(Icons.arrow_downward_rounded, color: Color(0xFF10B981), size: 18),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Inflow', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                              const SizedBox(height: 2),
                              Text('৳ ${_formatAmount(inflow)}', style: const TextStyle(color: darkSlate, fontSize: 15, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: const Color(0xFFEF4444).withOpacity(0.1), shape: BoxShape.circle),
                            child: const Icon(Icons.arrow_upward_rounded, color: Color(0xFFEF4444), size: 18),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Outflow', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                              const SizedBox(height: 2),
                              Text('৳ ${_formatAmount(outflow)}', style: const TextStyle(color: darkSlate, fontSize: 15, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManagerTransactionsScreen())),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Recent Transactions', style: TextStyle(color: darkSlate, fontSize: 15, fontWeight: FontWeight.bold)),
                          Row(
                            children: const [
                              Text('View All', style: TextStyle(color: navyColor, fontSize: 12, fontWeight: FontWeight.bold)),
                              Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B), size: 18),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (recentTx.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('No recent transactions under this concern.', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                        )
                      else
                        ...recentTx.take(3).map((tx) {
                          final isCredit = tx['type'] == 'CREDIT' || (tx['amount'] != null && tx['amount'] > 0);
                          final amount = tx['amount'] ?? 0.0;
                          final desc = tx['description'] ?? tx['memo'] ?? 'Transaction';
                          final dateStr = tx['createdAt'] != null ? tx['createdAt'].toString().substring(0, 10) : '';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: (isCredit ? const Color(0xFF10B981) : const Color(0xFFEF4444)).withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                                    color: isCredit ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                    size: 14,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(desc, style: const TextStyle(color: darkSlate, fontSize: 13, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 2),
                                      Text(dateStr, style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                    ],
                                  ),
                                ),
                                Text(
                                  '\${isCredit ? '+' : '-'}৳ ${_formatAmount(amount.abs())}',
                                  style: TextStyle(
                                    color: isCredit ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Assigned Staff Custodians', style: TextStyle(color: darkSlate, fontSize: 15, fontWeight: FontWeight.bold)),
                        InkWell(
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManagerStaffScreen())),
                          child: const Text('Manage', style: TextStyle(color: navyColor, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (staffList.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('No staff assigned under this concern.', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                      )
                    else
                      ...staffList.take(4).map((staff) {
                        final name = staff['name'] ?? staff['fullName'] ?? 'Staff Member';
                        final role = staff['role'] ?? 'Custodian';
                        final phone = staff['phone'] ?? staff['mobile'] ?? '';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: navyColor.withOpacity(0.1),
                                child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'S', style: const TextStyle(color: navyColor, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name, style: const TextStyle(color: darkSlate, fontSize: 13, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 2),
                                    Text('$role • $phone', style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B), size: 18),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildPeriodChip(String label, String value, AppState app) {
    final isSelected = _selectedPeriod == value;
    return InkWell(
      onTap: () => setState(() => _selectedPeriod = value),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF64748B),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  void _showProfileBottomSheet(BuildContext context, AppState app) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Manager Profile',
                style: TextStyle(color: darkSlate, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                'Name: ${app.currentUser?.name ?? 'Manager'}',
                style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 4),
              Text(
                'Email: ${app.currentUser?.email ?? 'manager@taskboss.com'}',
                style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 4),
              Text(
                'Role: ${app.currentUser?.role ?? 'MANAGER'}',
                style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Log Out'),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await app.logout();
                    if (context.mounted) {
                      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

