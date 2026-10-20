import os

content = """import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:task_boss/services/app_state.dart';

class LedgerDetailsScreen extends StatefulWidget {
  final String ledgerId;
  final String initialName;

  const LedgerDetailsScreen({
    Key? key,
    required this.ledgerId,
    required this.initialName,
  }) : super(key: key);

  @override
  State<LedgerDetailsScreen> createState() => _LedgerDetailsScreenState();
}

class _LedgerDetailsScreenState extends State<LedgerDetailsScreen> {
  Map<String, dynamic>? _ledger;
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() => _isLoading = true);
    final app = context.read<AppState>();
    if (app.managers.isEmpty) {
      await app.fetchManagers();
    }
    final data = await app.fetchLedgerDetails(widget.ledgerId);
    if (mounted) {
      setState(() {
        _ledger = data;
        _isLoading = false;
      });
    }
  }

  void _openEditModal() {
    if (_ledger == null) return;
    final ledger = _ledger!;
    final nameCtrl = TextEditingController(text: ledger['name']?.toString() ?? '');
    final descCtrl = TextEditingController(text: ledger['description']?.toString() ?? '');
    String status = ledger['status']?.toString() ?? 'ACTIVE';
    bool isPerpetual = ledger['isPerpetual'] ?? true;
    
    final managersRaw = ledger['managers'] as List? ?? [];
    Set<String> selectedManagerIds = managersRaw.map((m) => m['id'].toString()).toSet();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final app = context.read<AppState>();
            final allManagers = app.managers;

            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                top: 16,
                left: 20,
                right: 20,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Edit & Manage Ledger',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                    const Divider(color: Color(0xFFE2E8F0)),
                    const SizedBox(height: 10),

                    const Text('Ledger Name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                    const SizedBox(height: 6),
                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      ),
                    ),
                    const SizedBox(height: 14),

                    const Text('Description', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                    const SizedBox(height: 6),
                    TextField(
                      controller: descCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      ),
                    ),
                    const SizedBox(height: 14),

                    const Text('Status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: status == 'FROZEN' ? 'FROZEN' : 'ACTIVE',
                      items: const [
                        DropdownMenuItem(value: 'ACTIVE', child: Text('ACTIVE (Operational)')),
                        DropdownMenuItem(value: 'FROZEN', child: Text('FROZEN (Read-only lock)')),
                      ],
                      onChanged: (val) {
                        if (val != null) setSheetState(() => status = val);
                      },
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      ),
                    ),
                    const SizedBox(height: 14),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Perpetual Ledger', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                        Switch(
                          value: isPerpetual,
                          activeThumbColor: const Color(0xFF0F172A),
                          onChanged: (val) => setSheetState(() => isPerpetual = val),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Assigned Managers', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                    const SizedBox(height: 8),
                    if (allManagers.isEmpty)
                      const Text('No managers registered in system.', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)))
                    else
                      Container(
                        constraints: const BoxConstraints(maxHeight: 180),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: allManagers.length,
                          itemBuilder: (context, idx) {
                            final m = allManagers[idx];
                            final mId = m['id'].toString();
                            final mName = m['name']?.toString() ?? 'Manager';
                            final isSelected = selectedManagerIds.contains(mId);

                            return CheckboxListTile(
                              value: isSelected,
                              title: Text(mName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                              subtitle: Text(m['handle']?.toString() ?? '', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                              activeColor: const Color(0xFF0F172A),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              onChanged: (val) {
                                setSheetState(() {
                                  if (val == true) {
       
