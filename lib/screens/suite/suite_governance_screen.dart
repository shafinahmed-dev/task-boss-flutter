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
        app.fetchSuiteTransactions(),
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

  Widget _buildLiveActivityTicker(BuildContext context, Map<String, dynamic>? latestTxn) {
    final hasTxn = latestTxn != null && latestTxn.isNotEmpty;
    final isInflow = hasTxn && (latestTxn['direction'] ?? '').toString().toUpperCase() == 'IN';
    final double amount = hasTxn ? (latestTxn['amount'] as num? ?? 0).toDouble() : 0.0;
    final String actor = hasTxn
        ? (latestTxn['userName'] ?? latestTxn['collectorName'] ?? 'Staff').toString().trim()
        : 'System';
    final String segment = hasTxn
        ? (latestTxn['segmentName'] ?? latestTxn['notes'] ?? 'Movement').toString().trim()
        : 'Synchronized';

    final Color dotColor = !hasTxn
        ? const Color(0xFF64748B)
        : (isInflow ? const Color(0xFF10B981) : const Color(0xFFEF4444));
    final Color amountColor = isInflow ? const Color(0xFF34D399) : const Color(0xFFF87171);

    return Expanded(
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const SuiteTransactionsScreen(),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withOpacity(0.08),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Glowing Live Pulse Dot
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: dotColor.withOpacity(0.6),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 9),

              // Formatted Rich Text with Clean Spacing
              Expanded(
                child: hasTxn
                    ? Row(
                        children: [
                          Flexible(
                            child: Text(
                              actor,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFF1F5F9),
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6),
                            child: Text(
                              '•',
                              style: TextStyle(fontSize: 10, color: Color(0xFF475569)),
                            ),
                          ),
                          Text(
                            '${isInflow ? '+' : '-'}৳ ${amount.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: amountColor,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6),
                            child: Text(
                              '•',
                              style: TextStyle(fontSize: 10, color: Color(0xFF475569)),
                            ),
                          ),
                          Flexible(
                            child: Text(
                              segment,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ),
                        ],
                      )
                    : const Text(
                        'All accounts synchronized • Ledger active',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: Colors.white.withOpacity(0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrivacyTogglePill(double totalBalance) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      margin: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => setState(() => _isCashMasked = !_isCashMasked),
        borderRadius: BorderRadius.circular(12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.account_balance_wallet_outlined,
              size: 15,
              color: Color(0xFF10B981),
            ),
            const SizedBox(width: 6),
            Text(
              _isCashMasked ? '৳ ••••••' : formatBdt(totalBalance),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFFF1F5F9),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              _isCashMasked ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 14,
              color: const Color(0xFF94A3B8),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopHeaderAndTabs(BuildContext context, double totalCash) {
    final appState = context.watch<AppState>();
    final latestTxn = appState.suiteTransactions.isNotEmpty ? appState.suiteTransactions.first : null;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xFF000000), // Solid Pitch Black (Dominates the left)
            Color(0xFF040812), // Deep Black-Navy Transition
            Color(0xFF0A1526), // Subtle, Muted Midnight Blue (Far right edge)
          ],
          stops: [0.0, 0.55, 1.0],
        ),
        border: Border(
          bottom: BorderSide(
            color: Color(0x14FFFFFF), // Faint 8% white separator
            width: 1.0,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Row(
            children: [
              // Left: Live activity ticker
              _buildLiveActivityTicker(context, latestTxn),

              // Right: Eye balance toggle
              _buildPrivacyTogglePill(totalCash),
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
              'Money Flow',
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
          'Top Cash Holders',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
        const SizedBox(height: 4),
        const Text(
          'Highest cash balance first',
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
                        Text('৳ ${formatBdt(personalBalance)}', style: const TextStyle(color: Color(0xFF0F172A), fontSize: 16, fontWeight: FontWeight.bold)),
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

  Widget _buildDashboardConcernCard(BuildContext context, Map<String, dynamic> concern) {
    final name = concern['name']?.toString() ?? 'Concern';
    final code = concern['code']?.toString() ?? name.split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(3).join();
    final memberCount = (concern['memberCount'] as num? ?? concern['userCount'] as num? ?? concern['totalMembers'] as num? ?? 0).toInt();
    final balance = (concern['balance'] as num? ?? concern['totalBalance'] as num? ?? 0).toDouble();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _openConcernBreakdown(concern),
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Header Row: Code badge + Name (Left) | Member Count (Right)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    code.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.people_alt_outlined, size: 13, color: Color(0xFF64748B)),
                    const SizedBox(width: 3),
                    Text(
                      '$memberCount',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Balance Area
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'CASH BALANCE',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    formatBdt(balance),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
