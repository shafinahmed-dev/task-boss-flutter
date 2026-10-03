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
      ),
    );
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
          
