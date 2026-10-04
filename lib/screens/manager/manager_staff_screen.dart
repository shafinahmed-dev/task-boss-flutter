import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:task_boss/services/app_state.dart';

class ManagerStaffScreen extends StatefulWidget {
  const ManagerStaffScreen({super.key});
  @override
  State<ManagerStaffScreen> createState() => _ManagerStaffScreenState();
}

class _ManagerStaffScreenState extends State<ManagerStaffScreen> {
  String _searchQuery = '';
  final Map<String, bool> _showPasswordMap = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().fetchManagerConcernEmployees();
    });
  }

  String _formatAmount(dynamic val) {
    if (val == null) return '0.00';
    final n = (val is num) ? val.toDouble() : (double.tryParse(val.toString()) ?? 0.0);
    return n.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    const navyColor = Color(0xFF1E2638);
    const darkSlate = Color(0xFF0F172A);
    const borderColor = Color(0xFFE2E8F0);
    final app = context.watch<AppState>();
    final allEmployees = app.managerEmployeesList;

    final filteredEmployees = allEmployees.where((e) {
      final name = (e['name'] ?? '').toString().toLowerCase();
      final handle = (e['handle'] ?? '').toString().toLowerCase();
      final designation = (e['designation'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();
      return name.contains(query) || handle.contains(query) || designation.contains(query);
    }).toList();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Staff Management', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: navyColor,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: () => app.fetchManagerConcernEmployees(),
        color: navyColor,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor)),
                      child: TextField(
                        onChanged: (val) => setState(() => _searchQuery = val),
                        decoration: const InputDecoration(hintText: 'Search staff members...', hintStyle: TextStyle(color: Color(0xFF64748B), fontSize: 13), prefixIcon: Icon(Icons.search_rounded, color: Color(0xFF64748B)), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _showAddEmployeeModal(context, app),
                    child: Container(width: 48, height: 48, decoration: BoxDecoration(color: darkSlate, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.add_rounded, color: Colors.white)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: filteredEmployees.isEmpty
                  ? const Center(child: Text('No staff members found.', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: filteredEmployees.length,
                      itemBuilder: (context, index) {
                        final e = filteredEmployees[index];
                        final id = e['id'] ?? '';
                        final name = e['name'] ?? 'Staff';
                        final handle = e['handle'] ?? '';
                        final designation = e['designation'] ?? 'Staff';
                        final department = e['department'] ?? 'General';
                        final balance = e['balance'] ?? 0.0;
                        final rawPassword = e['rawPassword'] ?? '';
                        final showPassword = _showPasswordMap[id] ?? false;
                        final initials = name.isNotEmpty ? name.substring(0, 1).toUpperCase() : 'S';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 6, offset: const Offset(0, 2))]),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(radius: 22, backgroundColor: navyColor, child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(name, style: const TextStyle(color: darkSlate, fontSize: 14, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 2),
                                        Text('@$handle • $designation ($department)', style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)), child: Text('৳ ${_formatAmount(balance)}', style: const TextStyle(color: darkSlate, fontSize: 13, fontWeight: FontWeight.bold))),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const Divider(height: 1, color: Color(0xFFF1F5F9)),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Text('Password: ', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                                      Text(showPassword ? (rawPassword.isNotEmpty ? rawPassword : '••••••••') : '••••••••', style: const TextStyle(color: darkSlate, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                                      const SizedBox(width: 8),
                                      GestureDetector(onTap: () => setState(() => _showPasswordMap[id] = !showPassword), child: Icon(showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 16, color: const Color(0xFF64748B))),
                                      const SizedBox(width: 8),
                                      if (rawPassword.isNotEmpty)
                                        GestureDetector(
                                          onTap: () {
                                            Clipboard.setData(ClipboardData(text: rawPassword));
                                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password copied to clipboard'), duration: Duration(seconds: 2)))
;
                                          },
                                          child: const Icon(Icons.copy_rounded, size: 16, color: Color(0xFF64748B)),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddEmployeeModal(BuildContext context, AppState app) {
    final nameCtrl = TextEditingController();
    final handleCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final desigCtrl = TextEditingController();
    final deptCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add New Employee',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: handleCtrl,
                decoration: InputDecoration(
                  labelText: 'Handle Prefix (e.g. siteeng1)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                decoration: InputDecoration(
                  labelText: 'Initial Password',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: desigCtrl,
                decoration: InputDecoration(
                  labelText: 'Designation (e.g. Site Engineer)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: deptCtrl,
                decoration: InputDecoration(
                  labelText: 'Department (optional)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 20),
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
                    if (nameCtrl.text.isEmpty || passCtrl.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Name and Password are required')),
                      );
                      return;
                    }
                    Navigator.pop(ctx);
                    final success = await app.provisionEmployee({
                      'name': nameCtrl.text.trim(),
                      'handlePrefix': handleCtrl.text.trim(),
                      'password': passCtrl.text.trim(),
                      'designation': desigCtrl.text.trim(),
                      'department': deptCtrl.text.trim(),
                      'companyId': app.selectedManagerCompanyId ?? '',
                    });
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(success ? 'Employee provisioned successfully' : 'Failed to provision employee')),
                      );
                    }
                  },
                  child: const Text('Provision Employee', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

