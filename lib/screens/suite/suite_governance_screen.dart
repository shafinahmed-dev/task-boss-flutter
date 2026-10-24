import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../login_screen.dart';
import '../../services/app_state.dart';
import 'suite_transactions_screen.dart';
import 'suite_ledgers_screen.dart';


class SuiteGovernanceScreen extends StatefulWidget {
  const SuiteGovernanceScreen({super.key});

  @override
  State<SuiteGovernanceScreen> createState() => _SuiteGovernanceScreenState();
}

class _SuiteGovernanceScreenState extends State<SuiteGovernanceScreen> {
  int _selectedTabIndex = 0;
  String formatBdt(num value) {
    final formatter = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '৳ ',
      decimalDigits: 2,
    );
    return formatter.format(value);
  }
  bool _isCashMasked = true;
  bool _isLoading = false;
  String _selectedPeriod = 'month';
  final Set<String> _revealedPasswordManagerIds = {};
  final Set<String> _revealedPasswordEmployeeIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final app = context.read<AppState>();
    try {
      await Future.wait<void>([
        app.fetchConcerns(),
        app.fetchManagers(),
        app.fetchSuiteEmployees(),
        app.fetchSuiteDashboard(period: _selectedPeriod),
        app.fetchSuiteSummary(),
      ]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error refreshing suite data: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _timeAgo(dynamic rawDate) {
    if (rawDate == null) return 'recently';
    final date = DateTime.tryParse(rawDate.toString());
    if (date == null) return 'recently';
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 365) return '${(diff.inDays / 365).floor()}y ago';
    if (diff.inDays > 30) return '${(diff.inDays / 30).floor()}mo ago';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }
  void _showVelocityBreakdown(BuildContext context, {required String direction, required double totalAmount, required String rangeLabel}) {
    final isInflow = direction == 'in';
    final title = isInflow ? 'Group Inflows' : 'Group Outflows';
    final themeColor = isInflow ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    String periodParam = 'all_time';
    final p = rangeLabel.toLowerCase();
    if (p.contains('today')) periodParam = 'today';
    if (p.contains('week')) periodParam = 'this_week';
    if (p.contains('month')) periodParam = 'this_month';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(width: 44, height: 4, decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: themeColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                          child: Icon(isInflow ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, color: themeColor, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                            Text('Total: ৳ ${totalAmount.toStringAsFixed(2)} • $rangeLabel', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                          ],
                        ),
                      ],
                    ),
                    IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B))),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE2E8F0)),
              Expanded(
                child: FutureBuilder<dynamic>(
                  future: context.read<AppState>().fetchSuiteMovements(
                    direction: direction,
                    range: periodParam,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final items = (snapshot.data as List<Map<String, dynamic>>?) ?? [];

                    if (items.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isInflow ? Icons.file_download_off_rounded : Icons.file_upload_outlined,
                              size: 40,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'No ${isInflow ? "inflows" : "outflows"} recorded for this period.',
                              style: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final amt = double.tryParse(item['amount']?.toString() ?? '0') ?? 0.0;
                        final note = (item['note'] ?? item['movementType'] ?? (isInflow ? 'Inflow' : 'Outflow')).toString();
                        final user = item['userName'] ?? 'Staff';
                        final time = _timeAgo(item['createdAt']);
                        final voucher = item['voucherNumber']?.toString() ?? '';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isInflow ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  isInflow ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                                  color: themeColor,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      note,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'By $user • $time${voucher.isNotEmpty ? ' • $voucher' : ''}',
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                isInflow ? '+৳ ${amt.toStringAsFixed(2)}' : '-৳ ${amt.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: themeColor,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }


  double _calculateConsolidatedCash(AppState app) {
    if (app.dashboardData['totalGroupCash'] != null) {
      final val = app.dashboardData['totalGroupCash'];
      if (val is num) return val.toDouble();
      return double.tryParse(val.toString()) ?? 0.0;
    }
    if (app.suiteSummary['totalGroupCash'] != null) {
      final val = app.suiteSummary['totalGroupCash'];
      if (val is num) return val.toDouble();
      return double.tryParse(val.toString()) ?? 0.0;
    }
    double total = 0.0;
    for (final c in app.concerns) {
      final b = c['totalBalance'];
      if (b is num) {
        total += b.toDouble();
      } else {
        total += double.tryParse(b?.toString() ?? '0') ?? 0.0;
      }
    }
    return total;
  }

  String _formatAmount(dynamic val) {
    if (val == null) return '0.00';
    final numVal = (val is num) ? val.toDouble() : (double.tryParse(val.toString()) ?? 0.0);
    return numVal.toStringAsFixed(2);
  }

  Widget _buildVelocityCard({
    required BuildContext context,
    required bool isInflow,
    required double amount,
    required VoidCallback onTap,
  }) {
    final accentColor = isInflow ? const Color(0xFF34D399) : const Color(0xFFF87171);
    final shadowGlow = isInflow ? const Color(0xFF064E3B) : const Color(0xFF4C0519);
    final gradientColors = isInflow
        ? const [Color(0xFF04130C), Color(0xFF06281B), Color(0xFF064E3B)]
        : const [Color(0xFF140306), Color(0xFF26070E), Color(0xFF4C0519)];

    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
            stops: const [0.0, 0.55, 1.0],
          ),
          border: Border.all(
            color: (isInflow ? const Color(0xFF10B981) : const Color(0xFFEF4444)).withOpacity(0.2),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: shadowGlow.withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              // Top Glass Reflection
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 1,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withOpacity(0.0),
                        Colors.white.withOpacity(0.2),
                        Colors.white.withOpacity(0.0),
                      ],
                    ),
                  ),
                ),
              ),

              // Background Arrow Watermark
              Positioned(
                right: -15,
                bottom: -20,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 0.06,
                    child: Icon(
                      isInflow ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                      size: 95,
                      color: accentColor,
                    ),
                  ),
                ),
              ),

              // Interactive Body
              InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        isInflow ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                        color: accentColor,
                        size: 20,
                      ),
                      const SizedBox(height: 10),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          formatBdt(amount),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Text(
                          isInflow ? 'INFLOW' : 'OUTFLOW',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                            color: accentColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final totalCash = _calculateConsolidatedCash(app);

    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: Column(
        children: [
          _buildTopHeaderAndTabs(context, totalCash),
          Expanded(
            child: _selectedTabIndex == 0
                ? (_isLoading && app.concerns.isEmpty && app.managers.isEmpty
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF1E2638)))
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        color: const Color(0xFF1E2638),
                        child: _buildDashboardTab(context, app, totalCash),
                      ))
                : (_selectedTabIndex == 1
                    ? const SuiteLedgersScreen()
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        color: const Color(0xFF1E2638),
                        child: _buildManageTab(context, app),
                      )),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0F172A),
          border: Border(top: BorderSide(color: Color(0xFF1E2638), width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedTabIndex,
          onTap: (index) => setState(() => _selectedTabIndex = index),
          backgroundColor: const Color(0xFF0F172A),
          selectedItemColor: Colors.white,
          unselectedItemColor: const Color(0xFF64748B),
          selectedFontSize: 12,
          unselectedFontSize: 12,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_rounded),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.menu_book_rounded),
              label: 'Ledgers',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.business_center_rounded),
              label: 'Manage',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopHeaderAndTabs(BuildContext context, double totalCash) {
    final appState = context.watch<AppState>();
    final user = appState.currentUser ?? appState.user;
    final companyName = user?.name ?? 'TASK Group Suite';

    return Container(
      color: const Color(0xFF1E2638),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: () => _showAccountBottomSheet(context),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        companyName,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Color(0xFF0F172A)),
                    ],
                  ),
                ),
              ),

              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.account_balance_wallet_rounded, size: 16, color: Color(0xFF10B981)),
                        const SizedBox(width: 6),
                        Text(
                          _isCashMasked ? '৳ ••••••' : '৳ ${_formatAmount(totalCash)}',
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: () => setState(() => _isCashMasked = !_isCashMasked),
                          child: Icon(
                            _isCashMasked ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            size: 16,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                    onPressed: _loadData,
                    tooltip: 'Refresh Data',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardTab(BuildContext context, AppState app, double totalGroupCash) {
    final dashboard = app.dashboardData;
    final concernsList = dashboard['concerns'] as List? ?? app.concerns;
    final inflow = dashboard['inflow'] ?? 0.0;
    final outflow = dashboard['outflow'] ?? 0.0;
    final leaderboard = dashboard['managersLeaderboard'] as List? ?? [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SuiteTransactionsScreen()),
            );
          },
          borderRadius: BorderRadius.circular(20),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF000000), // True Solid Black
                  Color(0xFF070B14), // Deep Black Transition
                  Color(0xFF0D1B2A), // Elegant Midnight Blue
                ],
                stops: [0.0, 0.5, 1.0],
              ),
              border: Border.all(
                color: Colors.white.withOpacity(0.08),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.45),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: const Color(0xFF0D1B2A).withOpacity(0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                children: [
                  // 1. Top Edge Frosted Glass Highlight Reflection
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withOpacity(0.0),
                            Colors.white.withOpacity(0.25),
                            Colors.white.withOpacity(0.0),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // 2. Large Watermark on Far Right (5% Opacity)
                  Positioned(
                    right: -25,
                    bottom: -30,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: 0.05,
                        child: const Icon(
                          Icons.corporate_fare_rounded,
                          size: 155,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),

                  // 3. Card Interactive Content
                  Padding(
                    padding: const EdgeInsets.all(22.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'TOTAL GROUP BALANCE',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.1,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 13,
                              color: Colors.white.withOpacity(0.45),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          formatBdt(totalGroupCash),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Consolidated cash across all active concerns',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: Color(0xFF94A3B8),
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
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Financial Velocity',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildPeriodChip('Today', 'today'),
              const SizedBox(width: 8),
              _buildPeriodChip('This Week', 'week'),
              const SizedBox(width: 8),
              _buildPeriodChip('This Month', 'month'),
              const SizedBox(width: 8),
              _buildPeriodChip('All Time', 'all'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildVelocityCard(
              context: context,
              isInflow: true,
              amount: (inflow is num) ? inflow.toDouble() : (double.tryParse(inflow.toString()) ?? 0.0),
              onTap: () {
                debugPrint('[Suite] Tapped Inflow card');
                _showVelocityBreakdown(
                  context,
                  direction: 'in',
                  totalAmount: (inflow is num) ? inflow.toDouble() : (double.tryParse(inflow.toString()) ?? 0.0),
                  rangeLabel: _selectedPeriod,
                );
              },
            ),
            const SizedBox(width: 12),
            _buildVelocityCard(
              context: context,
              isInflow: false,
              amount: (outflow is num) ? outflow.toDouble() : (double.tryParse(outflow.toString()) ?? 0.0),
              onTap: () {
                debugPrint('[Suite] Tapped Outflow card');
                _showVelocityBreakdown(
                  context,
                  direction: 'out',
                  totalAmount: (outflow is num) ? outflow.toDouble() : (double.tryParse(outflow.toString()) ?? 0.0),
                  rangeLabel: _selectedPeriod,
                );
              },
            ),
          ],
        ),

        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Concerns',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
            ),
            Text(
              'Tap card for breakdown',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (concernsList.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('No concerns provisioned yet.', style: TextStyle(color: Color(0xFF64748B))),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 2.1,
            ),
            itemCount: concernsList.length,
            itemBuilder: (context, index) => _buildDashboardConcernCard(context, concernsList[index]),
          ),

        const SizedBox(height: 24),
        const Text(
          'Managers by Liquidity',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
        const SizedBox(height: 4),
        const Text(
          'Sorted descending by personal cash-in-hand',
          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 12),
        if (leaderboard.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('No managers provisioned yet.', style: TextStyle(color: Color(0xFF64748B))),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: leaderboard.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (ctx, i) {
              final m = leaderboard[i];
              final rank = m['rank'] ?? (i + 1);
              final name = m['name'] ?? 'Manager';
              final personalBalance = m['personalBalance'] ?? 0.0;
              final comps = (m['companies'] as List? ?? []);
              final concernName = comps.isNotEmpty ? (comps[0]['name'] ?? comps[0]['code'] ?? '') : '';

              Color rankColor = const Color(0xFF0F172A);
              if (rank == 1) {
                rankColor = const Color(0xFFF59E0B);
              } else if (rank == 2) {
                rankColor = const Color(0xFF64748B);
              } else if (rank == 3) {
                rankColor = const Color(0xFFB45309);
              }

              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: rankColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '#$rank',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: const TextStyle(color: Color(0xFF0F172A), fontSize: 15, fontWeight: FontWeight.bold)),
                          if (concernName.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(concernName, style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                          ],
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('৳ ${_formatAmount(personalBalance)}', style: const TextStyle(color: Color(0xFF0F172A), fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildPeriodChip(String label, String periodVal) {
    final isSelected = _selectedPeriod == periodVal;
    return InkWell(
      onTap: () {
        setState(() => _selectedPeriod = periodVal);
        context.read<AppState>().fetchSuiteDashboard(period: periodVal);
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF64748B),
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildConcernBadge(dynamic data) {
    String badgeText = '';

    if (data is Map) {
      if (data['concernBadge'] != null && data['concernBadge'].toString().isNotEmpty) {
        badgeText = data['concernBadge'].toString();
      } else if (data['companyCodes'] is List && (data['companyCodes'] as List).isNotEmpty) {
        badgeText = (data['companyCodes'] as List).join(' • ');
      } else if (data['companyCode'] != null) {
        badgeText = data['companyCode'].toString();
      }
    }

    // Strip any accidental brackets
    badgeText = badgeText.replaceAll('[', '').replaceAll(']', '').trim();
    if (badgeText.isEmpty) badgeText = 'TDC';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        badgeText,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.4,
        ),
      ),
    );
  }


  Widget _buildManageTab(BuildContext context, AppState app) {
    final concerns = app.concerns;
    final managers = app.managers;
    final employees = app.suiteEmployees;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Company Concerns (${concerns.length})',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
            ),
            ElevatedButton.icon(
              onPressed: () => _showAddConcernModal(context),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Concern'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (concerns.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No concerns found.', style: TextStyle(color: Color(0xFF64748B))),
          )
        else
          ...concerns.map((c) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      (c['code'] ?? '').toString().toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c['name'] ?? '',
                          style: const TextStyle(color: Color(0xFF0F172A), fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${c['totalMembers'] ?? 0} Members • ৳ ${_formatAmount(c['totalBalance'])}',
                          style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF64748B)),
                    onPressed: () => _showEditConcernModal(context, c),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFEF4444)),
                    onPressed: () => _confirmDeleteConcern(context, c['id']),
                  ),
                ],
              ),
            );
          }),

        

        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Managers (${managers.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
            ElevatedButton.icon(
              onPressed: () => _showAddManagerModal(context),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Manager'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (managers.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No managers found.', style: TextStyle(color: Color(0xFF64748B))))
        else
          ...managers.map((m) {
            final mId = m['id'] ?? '';
            final isVis = _revealedPasswordManagerIds.contains(mId);
            final rawPwd = m['rawPassword'] ?? '••••••••';
            final compList = (m['companies'] as List? ?? []);
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(m['name'] ?? 'Manager', style: const TextStyle(color: Color(0xFF0F172A), fontSize: 16, fontWeight: FontWeight.bold)),
                                const SizedBox(width: 8),
                                _buildConcernBadge(m),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text('@${m['handle'] ?? ''}', style: const TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.w600)),
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
                          '৳ ${_formatAmount(m['balance'])}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF16A34A),
                          ),
                        ),
                      ),
                      IconButton(icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF64748B)), onPressed: () => _showEditManagerModal(context, m)),
                      IconButton(icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFEF4444)), onPressed: () => _confirmDeleteManager(context, mId)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
                    child: Row(
                      children: [
                        const Text('Password: ', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                        Expanded(child: Text(isVis ? rawPwd : '••••••••', style: const TextStyle(color: Color(0xFF0F172A), fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace'))),
                        InkWell(
                          onTap: () => setState(() => isVis ? _revealedPasswordManagerIds.remove(mId) : _revealedPasswordManagerIds.add(mId)),
                          child: Icon(isVis ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 16, color: Color(0xFF64748B)),
                        ),
                        const SizedBox(width: 12),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: rawPwd));
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password copied')));
                          },
                          child: const Icon(Icons.copy_rounded, size: 16, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),

        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Employees (${employees.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
          ],
        ),
        const SizedBox(height: 12),
        if (employees.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No employee accounts found.', style: TextStyle(color: Color(0xFF64748B))))
        else
          ...employees.map((e) {
            final eId = e['id'] ?? '';
            final isVis = _revealedPasswordEmployeeIds.contains(eId);
            final rawPwd = e['rawPassword'] ?? '••••••••';
            final comp = e['company'];
            final compCode = comp != null ? (comp['code'] ?? comp['name'] ?? '') : '';
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(e['name'] ?? 'Staff', style: const TextStyle(color: Color(0xFF0F172A), fontSize: 15, fontWeight: FontWeight.bold)),
                                const SizedBox(width: 8),
                                _buildConcernBadge(e),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '@${e['handle'] ?? ''} • ${e['designation'] ?? 'Staff'} • Managed by ${e['managerName'] ?? 'Manager'}',
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3))),
                        child: Text('৳ ${_formatAmount(e['balance'])}', style: const TextStyle(color: Color(0xFF10B981), fontSize: 13, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
                    child: Row(
                      children: [
                        const Text('Password: ', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                        Expanded(child: Text(isVis ? rawPwd : '••••••••', style: const TextStyle(color: Color(0xFF0F172A), fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace'))),
                        InkWell(
                          onTap: () => setState(() => isVis ? _revealedPasswordEmployeeIds.remove(eId) : _revealedPasswordEmployeeIds.add(eId)),
                          child: Icon(isVis ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 16, color: Color(0xFF64748B)),
                        ),
                        const SizedBox(width: 12),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: rawPwd));
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password copied')));
                          },
                          child: const Icon(Icons.copy_rounded, size: 16, color: Color(0xFF64748B)),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: () => _showChangePasswordModal(context, eId, e['name'] ?? 'Employee'),
                          style: TextButton.styleFrom(foregroundColor: const Color(0xFF0F172A), padding: EdgeInsets.zero, minimumSize: const Size(50, 30), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                          child: const Text('Change', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),

        const SizedBox(height: 24),
        const Text('Suite Account Security', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  CircleAvatar(radius: 20, backgroundColor: Color(0xFF0F172A), child: Icon(Icons.security_rounded, color: Colors.white, size: 20)),
                  SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TASK Group Suite', style: TextStyle(color: Color(0xFF0F172A), fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('@suite.taskgroup', style: TextStyle(color: Color(0xFF10B981), fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: Color(0xFFE2E8F0), height: 1),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showChangeSuitePasswordModal(context),
                      icon: const Icon(Icons.lock_reset_rounded, size: 16),
                      label: const Text('Change Suite Password'),
                      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF0F172A), side: const BorderSide(color: Color(0xFF0F172A)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmLogout(context),
                      icon: const Icon(Icons.logout_rounded, size: 16),
                      label: const Text('Log Out'),
                      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFEF4444), side: const BorderSide(color: Color(0xFFEF4444)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  void _showAccountBottomSheet(BuildContext context) {
    final appState = context.read<AppState>();
    final user = appState.currentUser ?? appState.user;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(radius: 24, backgroundColor: Color(0xFF1E2638), child: Icon(Icons.domain_rounded, color: Colors.white)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user?.name ?? 'TASK Group Suite', style: const TextStyle(color: Color(0xFF0F172A), fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('@${user?.handle ?? "suite.taskgroup"}', style: const TextStyle(color: Color(0xFF10B981), fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(6)),
                  child: const Text('SUITE ADMIN', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () { Navigator.pop(ctx); _confirmLogout(context); },
                icon: const Icon(Icons.logout_rounded, color: Colors.white),
                label: const Text('Log Out', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardConcernCard(BuildContext context, Map<String, dynamic> c) {
    final code = c['code']?.toString() ?? 'CORP';
    final name = c['name']?.toString() ?? 'Unnamed';
    final totalBalance = c['totalBalance'] ?? 0.0;
    final membersCount = c['totalMembers'] ?? 0;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _showConcernDetailsModal(context, c['id'] ?? '', name),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    code,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '৳ ${_formatAmount(totalBalance)}',
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              '$membersCount Members',
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildMemberCard(String name, String handle, String designation, double balance, bool isManager) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isManager ? const Color(0xFFFFFBEB) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isManager ? const Color(0xFFF59E0B) : const Color(0xFFE2E8F0),
          width: isManager ? 1.5 : 1.0,
        ),
        boxShadow: isManager
            ? [
                BoxShadow(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                )
              ]
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF0F172A),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '${handle.isNotEmpty ? '@$handle • ' : ''}$designation',
                  style: TextStyle(
                    fontSize: 12,
                    color: isManager ? const Color(0xFF92400E) : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          Text(
            '৳ ${balance.toStringAsFixed(2)}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Color(0xFF16A34A),
            ),
          ),
        ],
      ),
    );
  }

  void _showConcernDetailsModal(BuildContext context, String concernId, String concernName) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFF1E2638))),
    );

    try {
      final app = context.read<AppState>();
      final resp = await app.authRequest('GET', Uri.parse('${app.apiBaseUrl}/companies/$concernId/breakdown'));
      if (mounted) Navigator.pop(context);

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final concern = data['concern'] ?? {};
        final sortedMembers = List<Map<String, dynamic>>.from(
          (data['members'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
        );

        // Sort: Managers at the top, then alphabetically by name
        sortedMembers.sort((a, b) {
          final aRole = (a['role'] ?? a['designation'] ?? '').toString().toUpperCase();
          final bRole = (b['role'] ?? b['designation'] ?? '').toString().toUpperCase();
          final aIsManager = aRole.contains('MANAGER');
          final bIsManager = bRole.contains('MANAGER');
          if (aIsManager && !bIsManager) return -1;
          if (!aIsManager && bIsManager) return 1;
          return (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? '');
        });

        if (mounted) {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.white,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            builder: (ctx) => DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, controller) => Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(concern['name'] ?? concernName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                              Text('Code: [${concern['code'] ?? ''}] • Balance: ৳ ${_formatAmount(concern['totalBalance'])}', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                            ],
                          ),
                        ),
                        IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
                      ],
                    ),
                    const Divider(height: 24),
                    const Text('Assigned Members', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                    const SizedBox(height: 12),
                    Expanded(
                      child: sortedMembers.isEmpty
                          ? const Center(child: Text('No assigned members.', style: TextStyle(color: Color(0xFF64748B))))
                          : ListView.builder(
                              controller: controller,
                              itemCount: sortedMembers.length,
                              itemBuilder: (_, i) {
                                final item = sortedMembers[i];
                                final roleStr = (item['role'] ?? item['designation'] ?? '').toString().toUpperCase();
                                final isManager = roleStr.contains('MANAGER');
                                final name = item['name']?.toString() ?? 'Member';
                                final handle = item['handle']?.toString() ?? '';
                                final designation = item['designation']?.toString() ?? (isManager ? 'Manager' : 'Team Member');
                                final balance = double.tryParse(item['balance']?.toString() ?? '0') ?? 0.0;

                                return _buildMemberCard(name, handle, designation, balance, isManager);
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
      } else {
        throw Exception('Failed to fetch concern breakdown');
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading breakdown: $e')));
      }
    }
  }

  void _showAddConcernModal(BuildContext context) {
    final nameController = TextEditingController();
    final codeController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Add Concern', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
            const SizedBox(height: 16),
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Concern Name', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: codeController, decoration: const InputDecoration(labelText: 'Concern Short Code (e.g. TDC)', border: OutlineInputBorder())),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  if (nameController.text.trim().isEmpty || codeController.text.trim().isEmpty) return;
                  try {
                    await context.read<AppState>().createConcern(name: nameController.text.trim(), code: codeController.text.trim());
                    if (mounted) { Navigator.pop(ctx); _loadData(); }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: const Text('Create Concern', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditConcernModal(BuildContext context, Map<String, dynamic> concern) {
    final nameController = TextEditingController(text: concern['name']);
    final codeController = TextEditingController(text: concern['code']);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Edit Concern', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
            const SizedBox(height: 16),
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Concern Name', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: codeController, decoration: const InputDecoration(labelText: 'Concern Short Code', border: OutlineInputBorder())),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  try {
                    await context.read<AppState>().updateConcern(id: concern['id'], name: nameController.text.trim(), code: codeController.text.trim());
                    if (mounted) { Navigator.pop(ctx); _loadData(); }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteConcern(BuildContext context, String concernId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Concern'),
        content: const Text('Are you sure you want to delete this concern?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try { await context.read<AppState>().deleteConcern(concernId); _loadData(); } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showAddManagerModal(BuildContext context) {
    final nameController = TextEditingController();
    final handleController = TextEditingController();
    final passwordController = TextEditingController();
    final designationController = TextEditingController(text: 'Manager');
    final List<String> selectedCompanyIds = [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateModal) {
          final app = context.watch<AppState>();
          return Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Provision Manager', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                  const SizedBox(height: 16),
                  TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Full Name', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: handleController, decoration: const InputDecoration(labelText: 'Handle Prefix (e.g. jhon)', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: designationController, decoration: const InputDecoration(labelText: 'Designation', border: OutlineInputBorder())),
                  const SizedBox(height: 16),
                  const Text('Assigned Concerns:', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: app.concerns.map((c) {
                      final cId = c['id'];
                      final isSelected = selectedCompanyIds.contains(cId);
                      return ChoiceChip(
                        label: Text(c['code'] ?? c['name']),
                        selected: isSelected,
                        onSelected: (val) {
                          setStateModal(() {
                            if (val) selectedCompanyIds.add(cId);
                            else selectedCompanyIds.remove(cId);
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        if (nameController.text.trim().isEmpty || handleController.text.trim().isEmpty || passwordController.text.trim().isEmpty) return;
                        try {
                          await app.provisionManager(
                            name: nameController.text.trim(),
                            handlePrefix: handleController.text.trim(),
                            password: passwordController.text.trim(),
                            designation: designationController.text.trim(),
                            companyIds: selectedCompanyIds,
                          );
                          if (mounted) { Navigator.pop(ctx); _loadData(); }
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                        }
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      child: const Text('Provision Manager', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showEditManagerModal(BuildContext context, Map<String, dynamic> manager) {
    final nameController = TextEditingController(text: manager['name']);
    final handle = manager['handle'] ?? '';
    final prefix = handle.contains('.') ? handle.split('.')[0] : handle;
    final handleController = TextEditingController(text: prefix);
    final passwordController = TextEditingController();
    final designationController = TextEditingController(text: manager['designation']);
    final existingCompanies = (manager['companies'] as List? ?? []).map<String>((c) => c['id'].toString()).toList();
    final List<String> selectedCompanyIds = List.from(existingCompanies);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateModal) {
          final app = context.watch<AppState>();
          return Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Edit Manager', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                  const SizedBox(height: 16),
                  TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Full Name', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: handleController, decoration: const InputDecoration(labelText: 'Handle Prefix', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'New Password (Optional)', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: designationController, decoration: const InputDecoration(labelText: 'Designation', border: OutlineInputBorder())),
                  const SizedBox(height: 16),
                  const Text('Assigned Concerns:', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: app.concerns.map((c) {
                      final cId = c['id'];
                      final isSelected = selectedCompanyIds.contains(cId);
                      return ChoiceChip(
                        label: Text(c['code'] ?? c['name']),
                        selected: isSelected,
                        onSelected: (val) {
                          setStateModal(() {
                            if (val) selectedCompanyIds.add(cId);
                            else selectedCompanyIds.remove(cId);
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        try {
                          await app.updateManager(
                            id: manager['id'],
                            name: nameController.text.trim(),
                            designation: designationController.text.trim(),
                            handlePrefix: handleController.text.trim(),
                            newPassword: passwordController.text.trim().isNotEmpty ? passwordController.text.trim() : null,
                            companyIds: selectedCompanyIds,
                          );
                          if (mounted) { Navigator.pop(ctx); _loadData(); }
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                        }
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _confirmDeleteManager(BuildContext context, String managerId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Manager'),
        content: const Text('Are you sure you want to delete this manager?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try { await context.read<AppState>().deleteManager(managerId); _loadData(); } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordModal(BuildContext context, String userId, String userName) {
    final passwordController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Change Password for $userName', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
            const SizedBox(height: 16),
            TextField(controller: passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'New Password', border: OutlineInputBorder())),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  if (passwordController.text.trim().isEmpty) return;
                  try {
                    await context.read<AppState>().changeUserPassword(userId: userId, newPassword: passwordController.text.trim());
                    if (mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password updated successfully')));
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: const Text('Update Password', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showChangeSuitePasswordModal(BuildContext context) {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Change Suite Master Password', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
            const SizedBox(height: 16),
            TextField(controller: passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'New Master Password', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: confirmController, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm Master Password', border: OutlineInputBorder())),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  if (passwordController.text.trim().isEmpty || passwordController.text != confirmController.text) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passwords do not match or are empty')));
                    return;
                  }
                  try {
                    final app = context.read<AppState>();
                    final user = app.currentUser ?? app.user;
                    if (user != null) {
                      await app.changeUserPassword(userId: user.userId, newPassword: passwordController.text.trim());
                    }
                    if (mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Suite password updated successfully')));
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: const Text('Update Master Password', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out of the Suite?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<AppState>().logout();
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => LoginScreen(onSwitchToRegister: () {})),
                  (route) => false,
                );
              }
            },
            child: const Text('Log Out', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
