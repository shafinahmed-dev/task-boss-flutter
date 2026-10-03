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

  Widget _buildExecutiveHeader(BuildContext context, double totalGroupCash) {
    final appState = context.watch<AppState>();
    final user = appState.currentUser;
    final companyName = user?.name ?? 'TASK Group Suite';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFF0F172A),
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            InkWell(
              onTap: () => _showAccountBottomSheet(context),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF334155), width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      companyName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white70,
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
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF334155), width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _isCashMasked
                            ? '৳ ••••••'
                            : '৳ ${totalGroupCash.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          _isCashMasked
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          color: Colors.white70,
                          size: 16,
                        ),
                        onPressed: () {
                          setState(() {
                            _isCashMasked = !_isCashMasked;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(
                    Icons.notifications_outlined,
                    color: Colors.white70,
                  ),
                  onPressed: () {},
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAccountBottomSheet(BuildContext context) {
    final appState = context.read<AppState>();
    final user = appState.currentUser;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
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
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFF334155),
                  child: const Icon(Icons.domain_rounded, color: Colors.white),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.name ?? 'TASK Group Suite',
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '@${user?.handle ?? "suite.taskgroup"}',
                        style: const TextStyle(color: Color(0xFF2DD4BF), fontSize: 13),
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
                    style: TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(color: Color(0xFF334155)),
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
                label: const Text('Log Out'),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await appState.logout();
                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      M
