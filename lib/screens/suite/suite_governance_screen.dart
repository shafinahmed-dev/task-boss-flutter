import 'dart:convert';
import 'package:flutter/material.dart';
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
  String? _error;

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

  Future<void> _fetchAllData() async {
    setState(() { _loading = true; _error = null; });
    try {
      final app = context.read<AppState>();
      final h = {'Authorization': 'Bearer ${app.token}', 'Accept': 'application/json'};

      final cr = await http.get(Uri.parse('${app.apiBaseUrl}/companies'), headers: h);
      if (cr.statusCode >= 200 && cr.statusCode < 300) _concerns = jsonDecode(cr.body) as List;

      final mr = await http.get(Uri.parse('${app.apiBaseUrl}/suite/managers'), headers: h);
      if (mr.statusCode >= 200 && mr.statusCode < 300) _managers = jsonDecode(mr.body) as List;

      final sr = await http.get(Uri.parse('${app.apiBaseUrl}/suite/ledger-summary'), headers: h);
      if (sr.statusCode >= 200 && sr.statusCode < 300) _summary = (jsonDecode(sr.body) as Map<String, dynamic>);
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      filled: true,
      fillColor: AppTheme.slateDark,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF2E3D54), width: 1)),
    );
  }

  void _showAddConcernSheet() {
    final nameCtl = TextEditingController();
    final codeCtl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.slateMid,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        bool saving = false;
        String? sheetError;
        return StatefulBuilder(
          builder: (ctx2, setSS) => Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx2).viewInsets.bottom + 24, left: 20, right: 20, top: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Add Company Concern', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 16),
                TextField(controller: nameCtl, style: const TextStyle(color: Colors.white), decoration: _inputDecoration('Concern Name (e.g. TASK Design Corp)')),
                const SizedBox(height: 12),
                TextField(controller: codeCtl, style: const TextStyle(color: Colors.white), decoration: _inputDecoration('Short Code (e.g. TDC)')),
                if (sheetError != null) ...[const SizedBox(height: 10), Text(sheetError!, style: const TextStyle(color: AppTheme.expenseText, fontWeight: FontWeight.bold))],
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.slateDark, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: saving ? null : () async {
                    if (nameCtl.text.trim().isEmpty || codeCtl.text.trim().isEmpty) { setSS(() => sheetError = 'All fields are required'); return; }
                    setSS(() { saving = true; sheetError = null; });
                    try {
                      final app = context.read<AppState>();
                      final resp = await http.post(Uri.parse('${app.apiBaseUrl}/companies'),
                        headers: {'Authorization': 'Bearer ${app.token}', 'Content-Type': 'application/json'},
                        body: jsonEncode({'name': nameCtl.text.trim(), 'code': codeCtl.text.trim().toUpperCase()}));
                      if (resp.statusCode >= 200 && resp.statusCode < 300) { Navigator.pop(ctx2); _fetchAllData(); }
                      else { final d = jsonDecode(resp.body); throw Exception(d['message'] ?? 'Failed'); }
                    } catch (e) { setSS(() => sheetError = e.toString().replaceFirst('Exception: ', '')); }
                    finally { if (ctx2.mounted) setSS(() => saving = false); }
                  },
                  child: saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Save Concern', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAddManagerSheet() {
    final nameCtl = TextEditingController();
    final prefixCtl = TextEditingController();
    final passCtl = TextEditingController();
    String designation = 'CEO';
    final List<String> selectedCompanyIds = [];
    final designationOptions = ['CEO', 'COO', 'CFO', 'Managing Director', 'Executive Director', 'General Manager'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.slateMid,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        bool saving = false;
        String? sheetError;
        return StatefulBuilder(
          builder: (ctx2, setSS) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx2).viewInsets.bottom + 24, left: 20, right: 20, top: 24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Provision Executive Manager', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 16),
                    TextField(controller: nameCtl, style: const TextStyle(color: Colors.white), decoration: _inputDecoration('Full Name')),
                    const SizedBox(height: 12),
                    TextField(
                      controller: prefixCtl,
                      onChanged: (_) => setSS(() {}),
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration('Handle Prefix (e.g. ceoman)'),
                    ),
                    if (prefixCtl.text.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6, left: 4),
                        child: Text('Handle: ${prefixCtl.text.trim().toLowerCase().replaceAll(RegExp(r"[^a-z0-9]"), "")}.taskgroup', style: const TextStyle(color: Colors.lightGreenAccent, fontSize: 12)),
                      ),
                    const SizedBox(height: 12),
                    TextField(controller: passCtl, obscureText: true, style: const TextStyle(color: Colors.white), decoration: _inputDecoration('Secure Password')),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      dropdownColor: AppTheme.slateMid,
                      style: const TextStyle(color: Colors.white),
                      value: designation,
                      decoration: _inputDecoration('Designation'),
                      items: designationOptions.map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(color: Colors.white)))).toList(),
                      onChanged: (val) => setSS(() => designation = val ?? 'CEO'),
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
                          label: Text('${c['name']} [${c['code']}]'),
                          selected: isSel,
                          selectedColor: AppTheme.slateAccent,
                          backgroundColor: AppTheme.slateDark,
                          labelStyle: TextStyle(color: isSel ? Colors.white : Colors.white70),
                          onSelected: (sel) => setSS(() { if (sel) selectedCompanyIds.add(id); else selectedCompanyIds.remove(id); }),
                        );
                      }).toList(),
                    ),
                    if (sheetError != null) ...[const SizedBox(height: 10), Text(sheetError!, style: const TextStyle(color: AppTheme.expenseText, fontWeight: FontWeight.bold))],
                    const SizedBox(height: 20),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.slateDark, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      onPressed: saving ? null : () async {
                        if (nameCtl.text.trim().isEmpty || prefixCtl.text.trim().isEmpty || passCtl.text.trim().isEmpty) { setSS(() => sheetError = 'Name, handle prefix, and password required'); return; }
                        setSS(() { saving = true; sheetError = null; });
                        try {
                          final app = context.read<AppState>();
                          final resp = await http.post(Uri.parse('${app.apiBaseUrl}/suite/provision-manager'),
                            headers: {'Authorization': 'Bearer ${app.token}', 'Content-Type': 'application/json'},
                            body: jsonEncode({'name': nameCtl.text.trim(), 'handlePrefix': prefixCtl.text.trim(), 'password': passCtl.text, 'designation': designation, 'companyIds': selectedCompanyIds}));
                          if (resp.statusCode >= 200 && resp.statusCode < 300) { Navigator.pop(ctx2); _fetchAllData(); }
                          else { final d = jsonDecode(resp.body); throw Exception(d['message'] ?? 'Failed'); }
                        } catch (e) { setSS(() => sheetError = e.toString().replaceFirst('Exception: ', '')); }
                        finally { if (ctx2.mounted) setSS(() => saving = false); }
                      },
                      child: saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Provision Manager', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
              controller: _tabController,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              tabs: const [
                Tab(text: 'Concerns'),
                Tab(text: 'Managers'),
                Tab(text: 'Ledgers'),
              ],
            ),
          ),
          Expanded(
            child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.slateDark))
              : _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: AppTheme.expenseText, fontWeight: FontWeight.bold))))
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
        onPressed: _showAddConcernSheet,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Concern', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: RefreshIndicator(
        color: AppTheme.slateDark,
        onRefresh: _fetchAllData,
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
            if (_concerns.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: Text('No concerns registered yet.\nTap + Add Concern to get started.', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.mutedText))),
              ),
            ..._concerns.map((c) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.cardBorder, width: 0.8),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(color: AppTheme.slateDark, borderRadius: BorderRadius.circular(8)),
                    child: Text(c['code'] ?? '--', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c['name'] ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.primaryText)),
                        const SizedBox(height: 4),
                        Text('Custodians: ${c["totalCustodians"] ?? 0} • Wallets: ${c["totalWallets"] ?? 0}', style: const TextStyle(color: AppTheme.secondaryText, fontSize: 11)),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppTheme.mutedText),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildManagersTab() {
    return Scaffold(
      backgroundColor: AppTheme.canvas,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.slateDark,
        onPressed: _showAddManagerSheet,
        icon: const Icon(Icons.person_add_rounded, color: Colors.white),
        label: const Text('Add Manager', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: RefreshIndicator(
        color: AppTheme.slateDark,
        onRefresh: _fetchAllData,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Managing Accounts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.primaryText)),
                Text('${_managers.length} Active', style: const TextStyle(color: AppTheme.secondaryText, fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
            if (_managers.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: Text('No managers provisioned yet.', style: TextStyle(color: AppTheme.mutedText))),
              ),
            ..._managers.map((m) {
              final comps = m['companies'] as List? ?? [];
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.cardBorder, width: 0.8)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(m['name'] ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.primaryText)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: AppTheme.slateMid, borderRadius: BorderRadius.circular(6)),
                          child: Text(m['designation'] ?? 'Manager', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('@${m['handle']}', style: const TextStyle(color: AppTheme.inflowText, fontWeight: FontWeight.w600, fontSize: 12)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6, runSpacing: 4,
                      children: comps.map<Widget>((comp) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: AppTheme.canvas, borderRadius: BorderRadius.circular(4), border: Border.all(color: AppTheme.cardBorder)),
                        child: Text('${comp['name']} [${comp['code']}]', style: const TextStyle(fontSize: 10, color: AppTheme.slateDark)),
                      )).toList(),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildLedgersTab() {
    final tCash = _summary['totalGroupCash'] ?? 0.0;
    return RefreshIndicator(
      color: AppTheme.slateDark,
      onRefresh: _fetchAllData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Group Treasury Ledgers', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.primaryText)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppTheme.slateCardGradient,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('CONSOLIDATED LIQUIDITY', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.0)),
                const SizedBox(height: 8),
                Text('৳ ${tCash.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
                const SizedBox(height: 16),
                const Divider(color: Colors.white24, height: 1),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _statItem('Concerns', (_summary['concernsCount'] ?? 0).toString(), Icons.domain_rounded),
                    _statItem('Managers', (_summary['managersCount'] ?? 0).toString(), Icons.supervisor_account_rounded),
                    _statItem('Staff', (_summary['employeesCount'] ?? 0).toString(), Icons.groups_rounded),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('Suite Modules', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.primaryText)),
          const SizedBox(height: 12),
          _moduleCard(Icons.account_balance_wallet_rounded, 'Budgets & Allocations', 'Manage inter-company fund movements'),
          const SizedBox(height: 10),
          _moduleCard(Icons.savings_rounded, 'Reserves & Savings', 'Long-term liquidity pools'),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 18),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
          ],
        ),
      ],
    );
  }

  Widget _moduleCard(IconData icon, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.cardBorder, width: 0.8)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppTheme.canvas, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: AppTheme.slateDark, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primaryText)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: AppTheme.secondaryText, fontSize: 11)),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppTheme.mutedText),
        ],
      ),
    );
  }
}
