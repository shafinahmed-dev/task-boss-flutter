import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../login_screen.dart';
import '../../services/app_state.dart';

class SuiteGovernanceScreen extends StatefulWidget {
  const SuiteGovernanceScreen({super.key});

  @override
  State<SuiteGovernanceScreen> createState() => _SuiteGovernanceScreenState();
}

class _SuiteGovernanceScreenState extends State<SuiteGovernanceScreen> {
  int _selectedTabIndex = 0;
  bool _isCashMasked = true;
  bool _isLoading = false;
  final Set<String> _revealedPasswordManagerIds = {};

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
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: Color(0xFF0F172A),
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
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
                                color: const Color(0xFF0F172A),
                                size: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(
                        Icons.notifications_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Row(
              children: [
                _buildTopTabItem('Concerns', 0),
                _buildTopTabItem('Managers', 1),
                _buildTopTabItem('Ledgers', 2),
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

  void _showAccountBottomSheet(BuildContext context) {
    final appState = context.read<AppState>();
    final user = appState.currentUser ?? appState.user;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 24,
                  backgroundColor: Color(0xFF1E2638),
                  child: Icon(Icons.domain_rounded, color: Colors.white),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.name ?? 'TASK Group Suite',
                        style: const TextStyle(color: Color(0xFF0F172A), fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '@${user?.handle ?? "suite.taskgroup"}',
                        style: const TextStyle(color: Color(0xFF10B981), fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'SUITE ADMIN',
                    style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(color: Color(0xFFE2E8F0)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFEF4444),
                  side: const BorderSide(color: Color(0xFFEF4444)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Log Out', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await appState.logout();
                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => LoginScreen(onSwitchToRegister: () {})),
                      (route) => false,
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConcernsTab() {
    final app = context.watch<AppState>();
    final concerns = app.concerns;

    return RefreshIndicator(
      onRefresh: _loadData,
      color: const Color(0xFF1E2638),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Company Concerns',
                style: TextStyle(color: Color(0xFF0F172A), fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                '${concerns.length} Registered',
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (concerns.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Column(
                children: [
                  Icon(Icons.business_outlined, color: Color(0xFF94A3B8), size: 48),
                  SizedBox(height: 12),
                  Text(
                    'No Concerns Registered',
                    style: TextStyle(color: Color(0xFF0F172A), fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Tap "+ Add Concern" to register your first company entity.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                  ),
                ],
              ),
            )
          else
            ...concerns.map((c) => _buildConcernCard(c)),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildConcernCard(Map<String, dynamic> c) {
    final code = c['code']?.toString() ?? 'CORP';
    final name = c['name']?.toString() ?? 'Unnamed Concern';
    final totalBalance = c['totalBalance'];
    final membersCount = c['totalMembers'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showConcernDetailsModal(context, c),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    code,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '৳ ${_formatAmount(totalBalance)} • $membersCount Members',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: Color(0xFF64748B), size: 20),
                  onPressed: () => _showAddEditConcernModal(context, c),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 20),
                  onPressed: () => _confirmDeleteConcern(c['id'], name),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildManagersTab() {
    final app = context.watch<AppState>();
    final managers = app.managers;

    return RefreshIndicator(
      onRefresh: _loadData,
      color: const Color(0xFF1E2638),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Managing Accounts',
                style: TextStyle(color: Color(0xFF0F172A), fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                '${managers.length} Active',
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (managers.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Column(
                children: [
                  Icon(Icons.manage_accounts_outlined, color: Color(0xFF94A3B8), size: 48),
                  SizedBox(height: 12),
                  Text(
                    'No Managers Provisioned',
                    style: TextStyle(color: Color(0xFF0F172A), fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Tap "+ Add Manager" to create executive leadership accounts.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                  ),
                ],
              ),
            )
          else
            ...managers.map((m) => _buildManagerCard(m)),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildManagerCard(Map<String, dynamic> m) {
    final id = m['id']?.toString() ?? '';
    final name = m['name']?.toString() ?? 'Unnamed';
    final handle = m['handle']?.toString() ?? '';
    final rawPassword = m['rawPassword']?.toString() ?? '';
    final isPasswordVisible = _revealedPasswordManagerIds.contains(id);

    final companies = (m['companies'] as List<dynamic>?) ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Manager',
                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '@$handle',
            style: const TextStyle(
              color: Color(0xFF10B981),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Password: ${isPasswordVisible ? (rawPassword.isNotEmpty ? rawPassword : 'Not set') : '••••••••'}',
                style: const TextStyle(color: Color(0xFF475569), fontSize: 13),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  setState(() {
                    if (isPasswordVisible) {
                      _revealedPasswordManagerIds.remove(id);
                    } else {
                      _revealedPasswordManagerIds.add(id);
                    }
                  });
                },
                child: Icon(
                  isPasswordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: const Color(0xFF475569),
                  size: 16,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () {
                  if (rawPassword.isNotEmpty) {
                    Clipboard.setData(ClipboardData(text: rawPassword));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Password copied to clipboard')),
                    );
                  }
                },
                child: const Icon(Icons.copy_rounded, color: Color(0xFF64748B), size: 16),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (companies.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: companies.map<Widget>((c) {
                final code = (c is Map) ? (c['code'] ?? c['name'] ?? '') : c.toString();
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: Text(
                    '$code [$code]',
                    style: const TextStyle(color: Color(0xFF334155), fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.edit_outlined, color: Color(0xFF64748B), size: 20),
                onPressed: () => _showAddEditManagerModal(context, m),
              ),
              const SizedBox(width: 16),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 20),
                onPressed: () => _confirmDeleteManager(id, name),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLedgersTab() {
    final app = context.watch<AppState>();
    final summary = app.suiteSummary;
    final totalCash = _calculateConsolidatedCash(app);

    return RefreshIndicator(
      onRefresh: _loadData,
      color: const Color(0xFF1E2638),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Group Ledgers & Liquidity',
            style: TextStyle(color: Color(0xFF0F172A), fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CONSOLIDATED LIQUIDITY',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '৳ ${_formatAmount(totalCash)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Total cash distributed across all active company concerns',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  Icons.business_rounded,
                  '${summary['concernsCount'] ?? app.concerns.length}',
                  'Concerns',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  Icons.supervisor_account_rounded,
                  '${summary['managersCount'] ?? app.managers.length}',
                  'Managers',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  Icons.people_outline_rounded,
                  '${summary['employeesCount'] ?? 0}',
                  'Employees',
                ),
              ),
            ],
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildMetricCard(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF0F172A), size: 24),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(color: Color(0xFF0F172A), fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Future<void> _showConcernDetailsModal(BuildContext context, Map<String, dynamic> concern) async {
    final app = context.read<AppState>();
    final concernId = concern['id'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => FutureBuilder<http.Response>(
        future: http.get(
          Uri.parse('${app.apiBaseUrl}/companies/$concernId/breakdown'),
          headers: {
            'Authorization': 'Bearer ${app.token}',
            'Content-Type': 'application/json',
          },
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 250,
              child: Center(child: CircularProgressIndicator(color: Color(0xFF0F172A))),
            );
          }

          if (snapshot.hasError || snapshot.data?.statusCode != 200) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 40),
                  const SizedBox(height: 12),
                  const Text('Failed to load breakdown details', style: TextStyle(color: Color(0xFF0F172A))),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
                ],
              ),
            );
          }

          final data = jsonDecode(snapshot.data!.body) as Map<String, dynamic>;
          final members = (data['members'] as List<dynamic>?) ?? [];
          final wallets = (data['wallets'] as List<dynamic>?) ?? [];

          return Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
            padding: const EdgeInsets.all(24),
            child: ListView(
              shrinkWrap: true,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          concern['name'] ?? '',
                          style: const TextStyle(color: Color(0xFF0F172A), fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Code: ${concern['code']} • Balance: ৳ ${_formatAmount(concern['totalBalance'])}',
                          style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Color(0xFF64748B)),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(color: Color(0xFFE2E8F0), height: 32),
                Text('Assigned Members (${members.length})', style: const TextStyle(color: Color(0xFF0F172A), fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (members.isEmpty)
                  const Text('No members assigned yet.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13))
                else
                  ...members.map((m) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFF0F172A),
                      child: Text((m['name'] ?? 'U')[0].toUpperCase(), style: const TextStyle(color: Colors.white)),
                    ),
                    title: Text(m['name'] ?? '', style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold)),
                    subtitle: Text('${m['designation'] ?? m['role']} • @${m['handle']}', style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                    trailing: Text('৳ ${_formatAmount(m['balance'])}', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                  )),
                const Divider(color: Color(0xFFE2E8F0), height: 32),
                Text('Wallets (${wallets.length})', style: const TextStyle(color: Color(0xFF0F172A), fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (wallets.isEmpty)
                  const Text('No wallets registered yet.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13))
                else
                  ...wallets.map((w) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.account_balance_wallet_outlined, color: Color(0xFF0F172A)),
                    title: Text(w['name'] ?? 'Wallet', style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold)),
                    subtitle: Text(w['holderName'] ?? '', style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                    trailing: Text('৳ ${_formatAmount(w['balance'])}', style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold)),
                  )),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showAddEditConcernModal(BuildContext context, [Map<String, dynamic>? concern]) {
    final app = context.read<AppState>();
    final isEditing = concern != null;
    final nameCtl = TextEditingController(text: isEditing ? concern['name'] : '');
    final codeCtl = TextEditingController(text: isEditing ? concern['code'] : '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEditing ? 'Edit Concern' : 'Add New Concern',
              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtl,
              decoration: const InputDecoration(
                labelText: 'Concern Name',
                hintText: 'e.g. Task Design & Consultancy',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: codeCtl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Short Code',
                hintText: 'e.g. TDC',
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  final name = nameCtl.text.trim();
                  final code = codeCtl.text.trim().toUpperCase();
                  if (name.isEmpty || code.isEmpty) return;

                  Navigator.pop(ctx);
                  try {
                    if (isEditing) {
                      await app.updateConcern(id: concern['id'], name: name, code: code);
                    } else {
                      await app.createConcern(name: name, code: code);
                    }
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(isEditing ? 'Concern updated' : 'Concern created')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed: $e')),
                      );
                    }
                  }
                },
                child: Text(isEditing ? 'Save Changes' : 'Create Concern', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddEditManagerModal(BuildContext context, [Map<String, dynamic>? manager]) {
    final app = context.read<AppState>();
    final isEditing = manager != null;
    final nameCtl = TextEditingController(text: isEditing ? manager['name'] : '');
    final prefixCtl = TextEditingController(
      text: isEditing ? (manager['handle']?.toString().split('.').first ?? '') : '',
    );
    final desigCtl = TextEditingController(text: isEditing ? manager['designation'] : '');
    final passCtl = TextEditingController(text: isEditing ? (manager['rawPassword'] ?? '') : '');

    final selectedCompanyIds = <String>{};
    if (isEditing && manager['companies'] is List) {
      for (final c in manager['companies']) {
        if (c is Map && c['id'] != null) selectedCompanyIds.add(c['id'].toString());
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEditing ? 'Edit Manager' : 'Provision Manager',
                  style: const TextStyle(color: Color(0xFF0F172A), fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtl,
                  decoration: const InputDecoration(labelText: 'Full Name'),
                ),
                if (!isEditing) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: prefixCtl,
                    decoration: const InputDecoration(
                      labelText: 'Handle Prefix',
                      hintText: 'e.g. ceoman',
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: desigCtl,
                  decoration: const InputDecoration(
                    labelText: 'Designation / Title',
                    hintText: 'e.g. Managing Director',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passCtl,
                  decoration: InputDecoration(
                    labelText: isEditing ? 'New Password (leave empty to keep)' : 'Initial Password',
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Assign to Concerns:', style: TextStyle(color: Color(0xFF64748B), fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: app.concerns.map((c) {
                    final cId = c['id'].toString();
                    final isSelected = selectedCompanyIds.contains(cId);
                    return FilterChip(
                      selected: isSelected,
                      label: Text(c['name'] ?? ''),
                      backgroundColor: const Color(0xFFF1F5F9),
                      selectedColor: const Color(0xFF0F172A),
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : const Color(0xFF0F172A),
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      checkmarkColor: Colors.white,
                      onSelected: (val) {
                        setModalState(() {
                          if (val) selectedCompanyIds.add(cId);
                          else selectedCompanyIds.remove(cId);
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () async {
                      final name = nameCtl.text.trim();
                      final desig = desigCtl.text.trim();
                      final pass = passCtl.text.trim();
                      if (name.isEmpty) return;

                      Navigator.pop(ctx);
                      try {
                        if (isEditing) {
                          await app.updateManager(
                            id: manager['id'],
                            name: name,
                            designation: desig,
                            newPassword: pass.isNotEmpty ? pass : null,
                            companyIds: selectedCompanyIds.toList(),
                          );
                        } else {
                          final prefix = prefixCtl.text.trim();
                          if (prefix.isEmpty || pass.isEmpty) return;
                          await app.provisionManager(
                            name: name,
                            handlePrefix: prefix,
                            password: pass,
                            designation: desig,
                            companyIds: selectedCompanyIds.toList(),
                          );
                        }
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(isEditing ? 'Manager updated' : 'Manager provisioned')),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed: $e')),
                          );
                        }
                      }
                    },
                    child: Text(
                      isEditing ? 'Save Changes' : 'Provision Manager',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDeleteConcern(String id, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Delete Concern', style: TextStyle(color: Color(0xFF0F172A))),
        content: Text('Are you sure you want to delete "\$name"?', style: const TextStyle(color: Color(0xFF64748B))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<AppState>().deleteConcern(id);
            },
            child: const Text('Delete', style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteManager(String id, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Delete Manager', style: TextStyle(color: Color(0xFF0F172A))),
        content: Text('Are you sure you want to delete "\$name"?', style: const TextStyle(color: Color(0xFF64748B))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<AppState>().deleteManager(id);
            },
            child: const Text('Delete', style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
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
          if (_isLoading)
            const LinearProgressIndicator(
              color: Color(0xFF1E2638),
              backgroundColor: Color(0xFFF1F5F9),
            ),
          Expanded(
            child: _selectedTabIndex == 0
                ? _buildConcernsTab()
                : _selectedTabIndex == 1
                    ? _buildManagersTab()
                    : _buildLedgersTab(),
          ),
        ],
      ),
      floatingActionButton: _selectedTabIndex == 2
          ? null
          : FloatingActionButton.extended(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: Text(
                _selectedTabIndex == 0 ? 'Add Concern' : 'Add Manager',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                if (_selectedTabIndex == 0) {
                  _showAddEditConcernModal(context);
                } else {
                  _showAddEditManagerModal(context);
                }
              },
            ),
    );
  }
}
