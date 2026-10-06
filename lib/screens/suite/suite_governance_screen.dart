import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../login_screen.dart';
import '../../services/app_state.dart';
import 'suite_transactions_screen.dart';


class SuiteGovernanceScreen extends StatefulWidget {
  const SuiteGovernanceScreen({super.key});

  @override
  State<SuiteGovernanceScreen> createState() => _SuiteGovernanceScreenState();
}

class _SuiteGovernanceScreenState extends State<SuiteGovernanceScreen> {
  int _selectedTabIndex = 0;
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
      if (b is num) total += b.toDouble();
      else total += double.tryParse(b?.toString() ?? '0') ?? 0.0;
    }
    return total;
  }

  String _formatAmount(dynamic val) {
    if (val == null) return '0.00';
    final numVal = (val is num) ? val.toDouble() : (double.tryParse(val.toString()) ?? 0.0);
    return numVal.toStringAsFixed(2);
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
            child: _isLoading && app.concerns.isEmpty && app.managers.isEmpty
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF1E2638)))
                : RefreshIndicator(
                    onRefresh: _loadData,
                    color: const Color(0xFF1E2638),
                    child: _selectedTabIndex == 0
                        ? _buildDashboardTab(context, app, totalCash)
                        : _buildManageTab(context, app),
                  ),
          ),
        ],
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
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
            Row(
              children: [
                _buildTopTabItem('Dashboard', 0),
                _buildTopTabItem('Manage', 1),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopTabItem(String label, int index) {
    final isSelected = _selectedTabIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedTabIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? Colors.white : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : const Color(0xFF94A3B8),
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            ),
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
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'TOTAL GROUP BALANCE',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white70,
                      size: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '৳ ${_formatAmount(totalGroupCash)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Consolidated cash across all active concerns',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                ),
              ],
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
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.arrow_downward_rounded, size: 16, color: Color(0xFF10B981)),
                        SizedBox(width: 6),
                        Text('Inflow', style: TextStyle(color: Color(0xFF10B981), fontSize: 13, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '৳ ${_formatAmount(inflow)}',
                      style: const TextStyle(color: Color(0xFF0F172A), fontSize: 18, fontWeight: FontWeight.bold),
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
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.arrow_upward_rounded, size: 16, color: Color(0xFFEF4444)),
                        SizedBox(width: 6),
                        Text('Outflow', style: TextStyle(color: Color(0xFFEF4444), fontSize: 13, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '৳ ${_formatAmount(outflow)}',
                      style: const TextStyle(color: Color(0xFF0F172A), fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
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
              if (rank == 1) rankColor = const Color(0xFFF59E0B);
              else if (rank == 2) rankColor = const Color(0xFF64748B);
              else if (rank == 3) rankColor = const Color(0xFFB45309);

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
        final members = (data['members'] as List? ?? []);

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
                      child: members.isEmpty
                          ? const Center(child: Text('No assigned members.', style: TextStyle(color: Color(0xFF64748B))))
                          : ListView.separated(
                              controller: controller,
                              itemCount: members.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final mem = members[i];
                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE2E8F0))),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(mem['name'] ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                                            Text('@${mem['handle'] ?? ''} • ${mem['designation'] ?? mem['role'] ?? ''}', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                                          ],
                                        ),
                                      ),
                                      Text('৳ ${_formatAmount(mem['balance'])}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                                    ],
                                  ),
                                );
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
