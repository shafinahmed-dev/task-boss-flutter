import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../../services/app_state.dart';

class SuiteGovernanceScreen extends StatefulWidget {
  const SuiteGovernanceScreen({super.key});

  @override
  State<SuiteGovernanceScreen> createState() => _SuiteGovernanceScreenState();
}

class _SuiteGovernanceScreenState extends State<SuiteGovernanceScreen> {
  int _selectedTabIndex = 0;
  final Set<String> _revealedPasswordManagerIds = {};
  bool _isLoading = false;

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

  void _showAddEditConcernModal(BuildContext context, [Map<String, dynamic>? concern]) {}
  void _showAddEditManagerModal(BuildContext context, [Map<String, dynamic>? manager]) {}

  Widget _buildConcernsTab() {
    final appState = context.watch<AppState>();
    return ListView.builder(
      itemCount: appState.concerns.length,
      itemBuilder: (ctx, i) {
        final c = appState.concerns[i];
        return ListTile(
          onTap: () => _showConcernDetailsModal(context, c),
          title: Text(c['name'], style: const TextStyle(color: Colors.white)),
          subtitle: Text('৳ ${c['totalBalance'] ?? 0} • ${c['totalMembers'] ?? 0} Members', style: const TextStyle(color: Colors.white60)),
          trailing: IconButton(icon: const Icon(Icons.edit, color: Colors.white), onPressed: () => _showAddEditConcernModal(context, c)),
        );
      },
    );
  }


  Widget _buildManagersTab() {
    final appState = context.watch<AppState>();
    return ListView.builder(
      itemCount: appState.managers.length,
      itemBuilder: (ctx, i) {
        final m = appState.managers[i];
        final revealed = _revealedPasswordManagerIds.contains(m['id']);
        return ListTile(
          title: Text(m['name'], style: const TextStyle(color: Colors.white)),
          subtitle: Text('${m['designation']} (@${m['handle']})', style: const TextStyle(color: Colors.white60)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(revealed ? Icons.visibility_off : Icons.visibility, color: Colors.white),
                onPressed: () => setState(() => revealed ? _revealedPasswordManagerIds.remove(m['id']) : _revealedPasswordManagerIds.add(m['id'])),
              ),
              IconButton(
                icon: const Icon(Icons.copy, color: Colors.white),
                onPressed: () => Clipboard.setData(ClipboardData(text: m['rawPassword'] ?? '')),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLedgersTab() {
    final appState = context.watch<AppState>();
    final summary = appState.suiteSummary;
    return ListView(
      children: [
        ListTile(title: Text('Total Group Cash: ${summary['totalGroupCash']}', style: const TextStyle(color: Colors.white))),
        ListTile(title: Text('Concerns: ${summary['concernsCount']}', style: const TextStyle(color: Colors.white))),
        ListTile(title: Text('Managers: ${summary['managersCount']}', style: const TextStyle(color: Colors.white))),
        ListTile(title: Text('Employees: ${summary['employeesCount']}', style: const TextStyle(color: Colors.white))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Suite Governance', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1E293B),
        actions: const [
          Icon(Icons.notifications, color: Colors.white),
          SizedBox(width: 16),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _selectedTabIndex == 0
              ? _buildConcernsTab()
              : _selectedTabIndex == 1
                  ? _buildManagersTab()
                  : _buildLedgersTab(),
      floatingActionButton: _selectedTabIndex == 2
          ? null
          : FloatingActionButton(
              onPressed: () => _selectedTabIndex == 0 ? _showAddEditConcernModal(context) : _showAddEditManagerModal(context),
              child: const Icon(Icons.add),
            ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF1E293B),
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        currentIndex: _selectedTabIndex,
        onTap: (index) => setState(() => _selectedTabIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.business), label: 'Concerns'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Managers'),
          BottomNavigationBarItem(icon: Icon(Icons.account_balance), label: 'Ledgers'),
        ],
      ),
    );
  }
}

