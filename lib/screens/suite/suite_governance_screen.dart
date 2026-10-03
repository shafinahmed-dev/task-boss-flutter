import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:task_boss/theme.dart';
import 'package:task_boss/services/app_state.dart';
import 'package:task_boss/widgets/app_header_bar.dart';

class SuiteGovernanceScreen extends StatefulWidget {
  const SuiteGovernanceScreen({super.key});

  @override
  State<SuiteGovernanceScreen> createState() => _SuiteGovernanceScreenState();
}

class _SuiteGovernanceScreenState extends State<SuiteGovernanceScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = false;
  List<dynamic> _concerns = [];
  List<dynamic> _managers = [];
  Map<String, dynamic> _summary = {};
  Set<String> _showPasswords = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchAllData());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      backgroundColor: AppTheme.expenseText,
    ));
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      backgroundColor: Colors.green.shade600,
    ));
  }

  Future<void> _fetchAllData() async {
    setState(() => _loading = true);
    try {
      final appState = context.read<AppState>();
      await Future.wait<void>([
        appState.fetchConcerns(),
        appState.fetchManagers(),
        appState.fetchSuiteSummary(),
      ]);
      _concerns = appState.concerns;
      _managers = appState.managers;
      _summary = appState.suiteSummary;
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label, labelStyle: const TextStyle(color: Colors.white70),
      filled: true, fillColor: AppTheme.slateDark,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF2E3D54), width: 1)),
    );
  }

  void _showConcernSheet([Map<String, dynamic>? concern]) {
    final isEditing = concern != null;
    final nameCtl = TextEditingController(text: isEditing ? concern['name'] : '');
    final codeCtl = TextEditingController(text: isEditing ? concern['code'] : '');

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: AppTheme.slateMid,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        bool saving = false;
        return StatefulBuilder(
          builder: (ctx2, setSS) => Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx2).viewInsets.bottom + 24, left: 20, right: 20, top: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(isEditing ? 'Edit Concern' : 'Add Concern', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 16),
                TextField(controller: nameCtl, style: const TextStyle(color: Colors.white), decoration: _inputDecoration('Concern Name (e.g. TASK Design)')),
                const SizedBox(height: 12),
                TextField(controller: codeCtl, style: const TextStyle(color: Colors.white), decoration: _inputDecoration('Short Code (e.g. TDC)')),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.slateDark, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: saving ? null : () async {
                    if (nameCtl.text.trim().isEmpty || codeCtl.text.trim().isEmpty) { _showError('All fields are required'); return; }
                    setSS(() => saving = true);
                    try {
                      final app = context.read<AppState>();
                      if (isEditing) {
                        await app.updateConcern(id: concern['id'], name: nameCtl.text.trim(), code: codeCtl.text.trim().toUpperCase());
                        _showSuccess('Concern updated successfully');
                      } else {
                        await app.createConcern(name: nameCtl.text.trim(), code: codeCtl.text.trim().toUpperCase());
                        _showSuccess('Concern created successfully');
                      }
                      if (ctx2.mounted) Navigator.pop(ctx2);
                      _fetchAllData();
                    } catch (e) {
                      _showError(e.toString().replaceFirst('Exception: ', ''));
                    } finally {
                      if (ctx2.mounted) setSS(() => saving = false);
                    }
                  },
                  child: saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showManagerSheet([Map<String, dynamic>? manager]) {
    final isEditing = manager != null;
    final nameCtl = TextEditingController(text: isEditing ? manager['name'] : '');
    final prefixCtl = TextEditingController();
    final passCtl = TextEditingController();
    String designation = isEditing ? (manager['designation'] ?? 'CEO') : 'CEO';
    
    final List<String> selectedCompanyIds = [];
    if (isEditing) {
      final mComps = manager['companies'] as List? ?? [];
      selectedCompanyIds.addAll(mComps.map((c) => c['id'].toString()));
    }
    
    final designOpts = ['CEO', 'COO', 'CFO', 'Managing Director', 'Executive Director', 'General Manager', 'Manager'];

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: AppTheme.slateMid,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        bool saving = false;
        return StatefulBuilder(
          builder: (ctx2, setSS) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx2).viewInsets.bottom + 24, left: 20, right: 20, top: 24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(isEditing ? 'Edit Manager' : 'Provision Manager', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 16),
                    TextField(controller: nameCtl, style: const TextStyle(color: Colors.white), decoration: _inputDecoration('Full Name')),
                    const SizedBox(height: 12),
                    
                    if (!isEditing) ...[
                      TextField(
                        controller: prefixCtl, onChanged: (_) => setSS(() {}),
                        style: const TextStyle(color: Colors.white), decoration: _inputDecoration('Handle Prefix (e.g. ceoman)'),
                      ),
                      if (prefixCtl.text.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6, left: 4),
                          child: Text('Handle preview: ${prefixCtl.text.trim().toLowerCase().replaceAll(RegExp(r"[^a-z0-9]"), "")}', style: const TextStyle(color: Colors.lightGreenAccent, fontSize: 12)),
                        ),
                      const SizedBox(height: 12),
                    ],
                    
                    TextField(
                      controller: passCtl, style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration(isEditing ? 'New Password (leave blank to keep)' : 'Secure Password'),
                    ),
                    const SizedBox(height: 12),
                    
                    TextFormField(
                      initialValue: designation,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration('Designation / Title (e.g. Managing Director)'),
                      onChanged: (val) => designation = val,
                    ),
                    const SizedBox(height: 16),
                    const Text('Assign Concerns:', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8, runSpacing: 8,
                      children: _concerns.map((c) {
                        final id = c['id'].toString();
                        final isSel = selectedCompanyIds.contains(id);
                        return FilterChip(
                          label: Text('${c['name']} [${c['code']}]'), selected: isSel,
                          selectedColor: AppTheme.slateAccent, backgroundColor: AppTheme.slateDark,
                          labelStyle: TextStyle(color: isSel ? Colors.white : Colors.white70),
                          onSelected: (sel) => setSS(() { if (sel) selectedCompanyIds.add(id); else selectedCompanyIds.remove(id); }),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.slateDark, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      onPressed: saving ? null : () async {
                        if (nameCtl.text.trim().isEmpty) { _showError('Name is required'); return; }
                        if (!isEditing && prefixCtl.text.trim().isEmpty) { _showError('Handle prefix required'); return; }
                        if (!isEditing && passCtl.text.trim().isEmpty) { _showError('Password required'); return; }
                        
                        setSS(() => saving = true);
                        try {
                          final app = context.read<AppState>();
                          if (isEditing) {
                            await app.updateManager(id: manager['id'], name: nameCtl.text.trim(), designation: designation, newPassword: passCtl.text.trim(), companyIds: selectedCompanyIds);
                            _showSuccess('Manager updated successfully');
                          } else {
                            await app.provisionManager(name: nameCtl.text.trim(), handlePrefix: prefixCtl.text.trim(), password: passCtl.text.trim(), designation: designation, companyIds: selectedCompanyIds);
                            _showSuccess('Manager provisioned successfully');
                          }
                          if (ctx2.mounted) Navigator.pop(ctx2);
                          _fetchAllData();
                        } catch (e) {
                          _showError(e.toString().replaceFirst('Exception: ', ''));
                        } finally {
                          if (ctx2.mounted) setSS(() => saving = false);
                        }
                      },
                      child: saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _deleteConcern(String id) async {
    final conf = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.slateMid,
        title: const Text('Delete Concern', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to delete this concern?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppTheme.expenseText))),
        ],
      )
    );
    if (conf != true) return;
    try {
      await context.read<AppState>().deleteConcern(id);
      _showSuccess('Concern deleted');
      _fetchAllData();
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _deleteManager(String id) async {
    final conf = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.slateMid,
        title: const Text('Delete Manager', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to delete this manager account?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppTheme.expenseText))),
        ],
      )
    );
    if (conf != true) return;
    try {
      await context.read<AppState>().deleteManager(id);
      _showSuccess('Manager deleted');
      _fetchAllData();
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.canvas,
      body: Column(
        children: [
          const AppHeaderBar(),
          Container(
            color: AppTheme.slateMid,
            child: TabBar(
              controller: _tabController, labelColor: Colors.white, unselectedLabelColor: Colors.white60,
              indicatorColor: Colors.white, indicatorWeight: 3, labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              tabs: const [ Tab(text: 'Concerns'), Tab(text: 'Managers'), Tab(text: 'Ledgers') ],
            ),
          ),
          Expanded(
            child: _loading && _concerns.isEmpty
              ? const Center(child: CircularProgressIndicator(color: AppTheme.slateDark))
              : TabBarView(
                  controller: _tabController,
                  children: [_buildConcernsTab(), _buildManagersTab(), _buildLedgersTab()],
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildConcernsTab() {
    return Scaffold(
      backgroundColor: AppTheme.canvas,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.slateDark,
        onPressed: () => _showConcernSheet(),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Concern', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: RefreshIndicator(
        color: AppTheme.slateDark, onRefresh: _fetchAllData,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Company Concerns', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.primaryText)),
                Text('${_concerns.length} Registered', style: const TextStyle(color: AppTheme.secondaryText, fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
            if (_concerns.isEmpty && !_loading)
              Container(
                padding: const EdgeInsets.all(32),
                margin: const EdgeInsets.only(top: 20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.cardBorder)),
                child: Column(
                  children: const [
                    Icon(Icons.domain_disabled_rounded, size: 48, color: AppTheme.mutedText),
                    SizedBox(height: 12),
                    Text('No concerns registered yet.', style: TextStyle(color: AppTheme.primaryText, fontWeight: FontWeight.bold, fontSize: 16)),
                    SizedBox(height: 4),
                    Text('Tap "+ Add Concern" below to register your first business entity.', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.secondaryText, fontSize: 12)),
                  ],
                ),
              ),
            ..._concerns.map((c) => GestureDetector(

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
          builder: (ctx) => _buildConcernBreakdownModal(data),
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

  Widget _buildConcernBreakdownModal(Map<String, dynamic> data) {
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

}
