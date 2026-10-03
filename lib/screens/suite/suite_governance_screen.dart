import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../../services/app_state.dart';
import '../auth/login_screen.dart';

class SuiteGovernanceScreen extends StatefulWidget {
  const SuiteGovernanceScreen({super.key});

  @override
  State<SuiteGovernanceScreen> createState() => _SuiteGovernanceScreenState();
}

class _SuiteGovernanceScreenState extends State<SuiteGovernanceScreen> {
  int _selectedTabIndex = 0;
  final Set<String> _revealedPasswordManagerIds = {};
  bool _isLoading = false;
  bool _isCashMasked = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final appState = context.read<AppState>();
      await Future.wait([
        appState.fetchConcerns(),
        appState.fetchManagers(),
        appState.fetchSuiteSummary(),
      ]);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAccountModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('TASK Group Suite', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            const Text('@suite.taskgroup', style: TextStyle(color: Color(0xFF94A3B8))),
            const SizedBox(height: 16),
            Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: const Color(0xFF064E3B), borderRadius: BorderRadius.circular(20)), child: const Text('SUITE ADMIN', style: TextStyle(color: Color(0xFF34D399), fontSize: 11, fontWeight: FontWeight.bold))),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () {
                context.read<AppState>().logout();
                Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
              },
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
              child: const Text('Log Out'),
            ),
          ],
        ),

  Future<void> _showConcernDetailsModal(BuildContext context, Map<String, dynamic> concern) async {
    final appState = context.read<AppState>();
    final concernId = concern['id'];
    try {
      final token = appState.token;
      final response = await http.get(
        Uri.parse('${appState.apiBaseUrl}/companies/$concernId/breakdown'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (!context.mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (ctx) => _buildConcernBreakdownModal(ctx, data),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load breakdown (${response.statusCode})')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading details: $e')),
        );
      }
    }
  }

  Widget _buildConcernBreakdownModal(BuildContext context, Map<String, dynamic> data) {
    final concern = data['concern'];
    final List members = data['members'];
    final List wallets = data['wallets'];
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8)), child: Text(concern['code'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900))),
            const SizedBox(width: 12),
            Expanded(child: Text(concern['name'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white))),
          ]),
          const SizedBox(height: 8),
          Text('৳ ${double.parse(concern['totalBalance'].toString()).toStringAsFixed(2)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
          const SizedBox(height: 24),
          Text('Members (${members.length})', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
          ...members.map((m) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${m['name']} (@${m['handle']})', style: const TextStyle(color: Colors.white)),
            subtitle: Text('${m['designation']} • ${m['role']}', style: const TextStyle(color: Colors.white60)),
            trailing: Text('৳ ${double.parse(m['balance'].toString()).toStringAsFixed(2)}', style: const TextStyle(color: Colors.greenAccent)),
          )),
          const SizedBox(height: 16),
          Text('Wallets (${wallets.length})', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
          ...wallets.map((w) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(w['name'], style: const TextStyle(color: Colors.white)),
            subtitle: Text('${w['holderName']} • ${w['type']}', style: const TextStyle(color: Colors.white60)),
            trailing: Text('৳ ${double.parse(w['balance'].toString()).toStringAsFixed(2)}', style: const TextStyle(color: Colors.greenAccent)),
          )),
        ],
      ),
    );
  }


  Widget _buildExecutiveHeader() {
    final appState = context.watch<AppState>();
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _showAccountModal(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF334155))),
              child: const Row(children: [Text('TASK Group Suite', style: TextStyle(color: Colors.white)), SizedBox(width: 4), Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white)]),
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF334155))),
            child: Row(children: [
              Text(_isCashMasked ? '৳ ••••••' : '৳ ${appState.suiteSummary['totalGroupCash'] ?? 0}', style: const TextStyle(color: Colors.white)),
              IconButton(icon: Icon(_isCashMasked ? Icons.visibility : Icons.visibility_off, color: Colors.white, size: 16), onPressed: () => setState(() => _isCashMasked = !_isCashMasked)),
            ]),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.notifications_outlined, color: Colors.white),
        ],
      ),
    );
  }

  Widget _buildConcernsTab() {
    final appState = context.watch<AppState>();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Text('Company Concerns', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
              const Spacer(),
              Text('${appState.concerns.length} Registered', style: const TextStyle(color: Color(0xFF94A3B8))),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: appState.concerns.length,
            itemBuilder: (ctx, i) {
              final c = appState.concerns[i];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: const Color(0xFF161F2E),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFF2A374A))),
                child: InkWell(
                  onTap: () => _showConcernDetailsModal(context, c),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(width: 48, height: 48, decoration: BoxDecoration(color: const Color(0xFF0F172A), border: Border.all(color: const Color(0xFF334155)), borderRadius: BorderRadius.circular(10)), child: Center(child: Text(c['code'] ?? '??', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c['name'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                              Text('৳ ${c['totalBalance'] ?? 0} • ${c['totalMembers'] ?? 0} Members', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                            ],
                          ),
                        ),
                        IconButton(icon: const Icon(Icons.edit_outlined, color: Color(0xFF94A3B8)), onPressed: () => _showAddEditConcernModal(context, c)),
                        IconButton(icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)), onPressed: () => appState.deleteConcern(c['id'])),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showAddEditConcernModal(BuildContext context, [Map<String, dynamic>? concern]) {}
  void _showAddEditManagerModal(BuildContext context, [Map<String, dynamic>? manager]) {}

      ),
    );
  }




  Widget _buildManagersTab() {
    final appState = context.watch<AppState>();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Text('Managing Accounts', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
              const Spacer(),
              Text('${appState.managers.length} Active', style: const TextStyle(color: Color(0xFF94A3B8))),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: appState.managers.length,
            itemBuilder: (ctx, i) {
              final m = appState.managers[i];
              final revealed = _revealedPasswordManagerIds.contains(m['id']);
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: const Color(0xFF161F2E),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFF2A374A))),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(m['name'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                        const Spacer(),
                        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: const Color(0xFF064E3B), borderRadius: BorderRadius.circular(20)), child: const Text('MANAGER', style: TextStyle(color: Color(0xFF34D399), fontSize: 11))),
                      ]),
                      Text('@${m['handle']}', style: const TextStyle(color: Color(0xFF2DD4BF))),
                      const SizedBox(height: 8),
                      Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8)), child: Row(children: [
                        Expanded(child: Text('Password: ${revealed ? m['rawPassword'] : '••••••••'}', style: const TextStyle(color: Colors.white))),
                        IconButton(icon: Icon(revealed ? Icons.visibility_off : Icons.visibility, color: Colors.white, size: 16), onPressed: () => setState(() => revealed ? _revealedPasswordManagerIds.remove(m['id']) : _revealedPasswordManagerIds.add(m['id']))),
                        IconButton(icon: const Icon(Icons.copy, color: Colors.white, size: 16), onPressed: () => Clipboard.setData(ClipboardData(text: m['rawPassword'] ?? ''))),
                      ])),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLedgersTab() {
    final appState = context.watch<AppState>();
    final summary = appState.suiteSummary;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF1E293B), Color(0xFF0F172A)]), border: Border.all(color: const Color(0xFF334155)), borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('CONSOLIDATED LIQUIDITY', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, letterSpacing: 1.2)),
                Text('৳ ${summary['totalGroupCash'] ?? 0}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                const Text('Total cash distributed across all active company concerns', style: TextStyle(color: Colors.white60)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _buildMetricCard(Icons.business_rounded, '${summary['concernsCount'] ?? 0}', 'Concerns')),
            const SizedBox(width: 16),
            Expanded(child: _buildMetricCard(Icons.supervisor_account_rounded, '${summary['managersCount'] ?? 0}', 'Managers')),
          ]),
          const SizedBox(height: 16),
          _buildMetricCard(Icons.people_outline_rounded, '${summary['employeesCount'] ?? 0}', 'Employees'),
        ],
      ),
    );
  }

  Widget _buildMetricCard(IconData icon, String value, String label) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: const Color(0xFF161F2E), border: Border.all(color: const Color(0xFF2A374A)), borderRadius: BorderRadius.circular(16)),
    child: Column(children: [Icon(icon, color: const Color(0xFF38BDF8)), Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)), Text(label, style: const TextStyle(color: Color(0xFF94A3B8)))]),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            _buildExecutiveHeader(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _selectedTabIndex == 0
                      ? _buildConcernsTab()
                      : _selectedTabIndex == 1
                          ? _buildManagersTab()
                          : _buildLedgersTab(),
            ),
          ],
        ),
      ),
      floatingActionButton: _selectedTabIndex == 2
          ? null
          : Container(
              decoration: BoxDecoration(color: const Color(0xFF1E293B), border: Border.all(color: const Color(0xFF334155)), borderRadius: BorderRadius.circular(20)),
              child: FloatingActionButton.extended(
                onPressed: () => _selectedTabIndex == 0 ? _showAddEditConcernModal(context) : _showAddEditManagerModal(context),
                backgroundColor: Colors.transparent,
                elevation: 0,
                icon: const Icon(Icons.add_rounded),
                label: Text(_selectedTabIndex == 0 ? 'Add Concern' : 'Add Manager'),
              ),
            ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF1E293B)))),
        child: BottomNavigationBar(
          backgroundColor: const Color(0xFF0A0F1D),
          selectedItemColor: const Color(0xFF38BDF8),
          unselectedItemColor: const Color(0xFF64748B),
          currentIndex: _selectedTabIndex,
          onTap: (index) => setState(() => _selectedTabIndex = index),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.domain_rounded), label: 'Concerns'),
            BottomNavigationBarItem(icon: Icon(Icons.manage_accounts_rounded), label: 'Managers'),
            BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet_rounded), label: 'Ledgers'),
          ],
        ),
      ),
    );
  }
}

