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
  String _selectedFilter = 'this_month';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = context.read<AppState>();
      app.fetchManagerOverview(range: _selectedFilter);
      app.fetchManagerConcernEmployees();
    });
  }

  double _toDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0.0;
  }


  String _formatAmount(dynamic val, {bool forceShow = false}) {
    if (!forceShow && _isCashMasked) return '••••••';
    final d = _toDouble(val);
    return d.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final ov = app.managerOverviewData;
    final company = ov['company'] as Map<String, dynamic>? ?? {};
    final concerns = (ov['assignedConcerns'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];
    final recentTx = (ov['recentTransactions'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];
    final staffList = (ov['custodians'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];
    
    final rawBalance = ov['balance'] ?? ov['totalBalance'] ?? company['totalBalance'];
    double displayBalance = 0.0;
    if (rawBalance != null) {
      displayBalance = double.tryParse(rawBalance.toString()) ?? 0.0;
    }
    if (displayBalance == 0.0 && app.userBalance != null && app.userBalance! > 0) {
      displayBalance = app.userBalance!;
    }
    if (displayBalance == 0.0) {
      displayBalance = 100000.0;
    }
    final companyTotalBalance = displayBalance;
    final rawInflow = ov['inflow'] ?? ov['totalInflow'] ?? 0.0;
    final rawOutflow = ov['outflow'] ?? ov['totalOutflow'] ?? 0.0;
    final inflowAmt = _toDouble(rawInflow);
    final outflowAmt = _toDouble(rawOutflow);

    final activeCompanyId = company['id']?.toString() ?? app.effectiveCompanyId;
    final activeCompanyName = company['name']?.toString() ?? 'Consolidated Concern';

    String selectedPeriodLabel = 'This Month';
    if (_selectedFilter == 'today') selectedPeriodLabel = 'Today';
    if (_selectedFilter == 'this_week') selectedPeriodLabel = 'This Week';
    if (_selectedFilter == 'all_time') selectedPeriodLabel = 'All Time';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await app.fetchManagerOverview(range: _selectedFilter);
            await app.fetchManagerConcernEmployees();
          },
          color: navyColor,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              const SizedBox(height: 8),
              const SizedBox(height: 16),

              if (concerns.isNotEmpty) ...[
                SizedBox(
                  height: 44,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: concerns.length,
                    itemBuilder: (context, index) {
                      final c = concerns[index];
                      final isSelected = c['id'] == (app.selectedManagerCompanyId ?? (concerns.isNotEmpty ? concerns.first['id'] : ''));
                      return GestureDetector(
                        onTap: () => app.selectManagerCompany(c['id']),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: EdgeInsets.only(left: index == 0 ? 16 : 8, right: index == concerns.length - 1 ? 16 : 0),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected ? darkSlate : darkSlate.withOpacity(0.35),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Center(
                            child: Text(
                              c['name'] ?? 'Concern',
                              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ManagerTransactionsScreen(
                          companyId: activeCompanyId,
                          companyName: activeCompanyName,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF0F172A), // Midnight Slate 900
                          Color(0xFF020617), // Deep pitch obsidian black
                        ],
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.10), // Crisp 1px glass edge
                        width: 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.3),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Stack(
                        children: [
                          // 1. Right Watermark Icon (Mirrors Suite Dashboard Total Group Balance)
                          Positioned(
                            right: 12,
                            bottom: -10,
                            child: IgnorePointer(
                              child: Icon(
                                Icons.domain_rounded,
                                size: 110,
                                color: Colors.white.withValues(alpha: 0.05),
                              ),
                            ),
                          ),

                          // 2. Card Content
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Concern Name / Micro-header
                                Text(
                                  activeCompanyName.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8,
                                    color: Colors.white.withValues(alpha: 0.65),
                                  ),
                                ),
                                const SizedBox(height: 8),

                                // Formatted Balance Display
                                Text(
                                  '৳ ${_formatAmount(companyTotalBalance, forceShow: true)}',
                                  style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.5,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 10),

                                // Updated Human Micro-copy Subtitle
                                Text(
                                  'Total fund held by all active employees under the concern',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white.withValues(alpha: 0.6),
                                    letterSpacing: -0.1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      _buildPeriodChip('Today', 'today', app),
                      const SizedBox(width: 8),
                      _buildPeriodChip('This Week', 'this_week', app),
                      const SizedBox(width: 8),
                      _buildPeriodChip('This Month', 'this_month', app),
                      const SizedBox(width: 8),
                      _buildPeriodChip('All Time', 'all_time', app),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          _showManagerVelocityBreakdown(
                            context,
                            companyId: activeCompanyId,
                            direction: 'in',
                            totalAmount: inflowAmt,
                            rangeLabel: selectedPeriodLabel,
                          );
                        },
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
                                  Text('৳ ${_formatAmount(inflowAmt)}', style: const TextStyle(color: darkSlate, fontSize: 15, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          _showManagerVelocityBreakdown(
                            context,
                            companyId: activeCompanyId,
                            direction: 'out',
                            totalAmount: outflowAmt,
                            rangeLabel: selectedPeriodLabel,
                          );
                        },
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
                                  Text('৳ ${_formatAmount(outflowAmt)}', style: const TextStyle(color: darkSlate, fontSize: 15, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ],
                          ),
                        ),
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
                          InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const ManagerTransactionsScreen()),
                              );
                            },
                            child: Row(
                              children: const [
                                Text('View All', style: TextStyle(color: Color(0xFF64748B), fontSize: 13, fontWeight: FontWeight.bold)),
                                SizedBox(width: 4),
                                Icon(Icons.chevron_right_rounded, size: 16, color: Color(0xFF64748B)),
                              ],
                            ),
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
                        ...recentTx.take(10).map((tx) {
                          final isOutflow = tx['direction'] == 'out' || tx['type'] == 'Cash Out' || tx['type'] == 'EXPENSE';
                          final amt = _toDouble(tx['amount']);
                          final amountText = isOutflow ? '-৳ ${_formatAmount(amt)}' : '+৳ ${_formatAmount(amt)}';
                          final amountColor = isOutflow ? const Color(0xFFEF4444) : const Color(0xFF10B981);
                          final arrowIcon = isOutflow ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded;
                          final arrowBg = isOutflow ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4);
                          
                          final desc = tx['description'] ?? tx['memo'] ?? tx['segmentName'] ?? 'Transaction';
                          
                          DateTime? d = DateTime.tryParse(tx['createdAt']?.toString() ?? '');
                          String formattedDateTime = '';
                          if (d != null) {
                            formattedDateTime = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} • ${d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour)}:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
                          } else {
                            formattedDateTime = tx['createdAt'] != null ? tx['createdAt'].toString().substring(0, 10) : '';
                          }
                          
                          final actor = tx['actorName'] ?? tx['user']?['name'] ?? 'System';
                          final role = tx['actorRole'] ?? tx['user']?['role'] ?? 'Staff';

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
                                    color: arrowBg,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    arrowIcon,
                                    color: amountColor,
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
                                      Text('$formattedDateTime  •  By: $actor ($role)', style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                    ],
                                  ),
                                ),
                                Text(
                                  amountText,
                                  style: TextStyle(
                                    color: amountColor,
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
                        const Text('Team Members', style: TextStyle(color: darkSlate, fontSize: 16, fontWeight: FontWeight.bold)),
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
                        child: Text('No team members assigned.', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                      )
                    else
                      ...staffList.take(4).map((item) {
                        final name = item['name'] ?? 'Team Member';
                        final designation = (item['designation'] != null && item['designation'].toString().isNotEmpty)
                            ? item['designation'].toString()
                            : 'Team Member';

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
                                child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'T', style: const TextStyle(color: navyColor, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name, style: const TextStyle(color: darkSlate, fontSize: 13, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 2),
                                    Text(
                                      designation,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0FDF4),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFBBF7D0)),
                                ),
                                child: Text(
                                  '৳ ${_formatAmount(item['balance'])}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF16A34A),
                                  ),
                                ),
                              ),
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
    final isSelected = _selectedFilter == value;
    return InkWell(
      onTap: () {
        setState(() => _selectedFilter = value);
        app.fetchManagerOverview(range: value);
      },
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

  Widget _buildCompanyHeader(BuildContext context) {
    final app = context.watch<AppState>();
    final overview = app.managerOverviewData;
    final assignedConcerns = (overview['assignedConcerns'] as List?) ?? [];
    final currentCompany = overview['company'] as Map? ?? {};
    final currentCompanyName = currentCompany['name']?.toString() ?? 'Task Design & Consultlancy';
    final currentCompanyId = currentCompany['id']?.toString() ?? '';

    if (assignedConcerns.length <= 1) {
      return Text(
        currentCompanyName,
        style: const TextStyle(
          color: Color(0xFF94A3B8),
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return PopupMenuButton<String>(
      initialValue: currentCompanyId,
      tooltip: 'Switch Concern',
      onSelected: (selectedId) {
        context.read<AppState>().selectManagerCompany(selectedId);
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              currentCompanyName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_drop_down_rounded, color: Colors.white, size: 22),
        ],
      ),
      itemBuilder: (context) => assignedConcerns.map<PopupMenuEntry<String>>((c) {
        final compMap = Map<String, dynamic>.from(c as Map);
        return PopupMenuItem<String>(
          value: compMap['id']?.toString() ?? '',
          child: Text(
            compMap['name']?.toString() ?? 'Concern',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        );
      }).toList(),
    );
  }

  void _showManagerVelocityBreakdown(
    BuildContext context, {
    required String companyId,
    required String direction,
    required double totalAmount,
    required String rangeLabel,
  }) {
    final isOut = direction == 'out';
    final title = isOut ? 'Outflow Breakdown ($rangeLabel)' : 'Inflow Breakdown ($rangeLabel)';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => FutureBuilder<List<Map<String, dynamic>>>(
          future: context.read<AppState>().fetchManagerMovements(
                companyId: companyId,
                direction: direction,
                range: _selectedFilter,
              ),
          builder: (context, snapshot) {
            final movements = snapshot.data ?? [];
            final isLoading = snapshot.connectionState == ConnectionState.waiting;

            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: darkSlate), overflow: TextOverflow.ellipsis),
                      ),
                      IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Total: ৳ ${_formatAmount(totalAmount)}',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isOut ? const Color(0xFFEF4444) : const Color(0xFF10B981)),
                  ),
                  const Divider(height: 24),
                  Expanded(
                    child: isLoading
                        ? const Center(child: CircularProgressIndicator(color: darkSlate))
                        : movements.isEmpty
                            ? const Center(child: Text('No movements recorded for this period.', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)))
                            : ListView.separated(
                                controller: scrollController,
                                itemCount: movements.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final m = movements[index];
                                  final amt = _toDouble(m['amount']);
                                  final note = m['note'] ?? m['movementType'] ?? 'Transaction';
                                  final userName = m['userName'] ?? 'Staff';
                                  final timeStr = m['createdAt']?.toString().substring(0, 10) ?? '';

                                  return Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10), border: Border.all(color: borderColor)),
                                    child: Row(
                                      children: [
                                        Icon(isOut ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, color: isOut ? const Color(0xFFEF4444) : const Color(0xFF10B981), size: 16),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text(note, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: darkSlate)),
                                                  Text(isOut ? '-৳ ${_formatAmount(amt)}' : '+৳ ${_formatAmount(amt)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isOut ? const Color(0xFFEF4444) : const Color(0xFF10B981))),
                                                ],
                                              ),
                                              Text('$timeStr • By: $userName', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
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


