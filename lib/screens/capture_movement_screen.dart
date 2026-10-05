import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/app_state.dart';
import '../models/models.dart';
import '../models/wallet_model.dart';

class CaptureMovementScreen extends StatefulWidget {
  const CaptureMovementScreen({super.key});
  @override
  State<CaptureMovementScreen> createState() => _CaptureState();
}

class _CaptureState extends State<CaptureMovementScreen> {
  String _flowType = 'INFLOW';
  Map<String, dynamic>? _selectedCategory;
  final TextEditingController _categorySearchCtrl = TextEditingController();
  final TextEditingController _amtCtl = TextEditingController();
  final TextEditingController _chgCtl = TextEditingController();
  final TextEditingController _noteCtl = TextEditingController();
  String? _selectedWalletId;
  String? _selectedPaymentMethod;
  bool _saving = false;
  String? _error;
  Map<String, dynamic>? _lastSavedReceipt;

  @override
  void initState() {
    super.initState();
    _loadDraft();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final app = context.read<AppState>();
      if (app.effectiveCompanyId.isEmpty) await app.fetchManagerOverview();
      final cid = app.effectiveCompanyId;
      if (cid.isNotEmpty) await app.fetchCategories(companyId: cid);
    });
  }


  Future<void> _loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _flowType = prefs.getString('draft_flow') ?? 'INFLOW';
        _amtCtl.text = prefs.getString('draft_amt') ?? '';
        _chgCtl.text = prefs.getString('draft_chg') ?? '';
        _noteCtl.text = prefs.getString('draft_note') ?? '';
      });
    }
  }

  Future<void> _saveDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('draft_flow', _flowType);
    await prefs.setString('draft_amt', _amtCtl.text);
    await prefs.setString('draft_chg', _chgCtl.text);
    await prefs.setString('draft_note', _noteCtl.text);
  }

  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('draft_flow');
    await prefs.remove('draft_amt');
    await prefs.remove('draft_chg');
    await prefs.remove('draft_note');
  }

  @override
  void dispose() {
    _categorySearchCtrl.dispose();
    _amtCtl.dispose();
    _chgCtl.dispose();
    _noteCtl.dispose();
    super.dispose();
  }

  void _showAddCategoryModal(BuildContext context, AppState app) {
    final nameCtrl = TextEditingController(text: _categorySearchCtrl.text.trim());
    String selectedType = 'BOTH';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 16, left: 16, right: 16, top: 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('New Category / Project Ledger', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
            const SizedBox(height: 16),
            TextField(controller: nameCtrl, decoration: InputDecoration(labelText: 'Category Name', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 16),
            const Text('Applies To', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
            const SizedBox(height: 8),
            Row(children: [
              ChoiceChip(label: const Text('Both'), selected: selectedType == 'BOTH', onSelected: (v) => setModalState(() => selectedType = 'BOTH')),
              const SizedBox(width: 8),
              ChoiceChip(label: const Text('Inflow Only'), selected: selectedType == 'INFLOW', onSelected: (v) => setModalState(() => selectedType = 'INFLOW')),
              const SizedBox(width: 8),
              ChoiceChip(label: const Text('Outflow Only'), selected: selectedType == 'OUTFLOW', onSelected: (v) => setModalState(() => selectedType = 'OUTFLOW')),
            ]),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity, height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  final newCat = await app.createCategory(name: name, type: selectedType, companyId: app.effectiveCompanyId);
                  if (mounted) {
                    Navigator.pop(ctx);
                    if (newCat != null) {
                      setState(() { _selectedCategory = newCat; _categorySearchCtrl.clear(); });
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Category "${newCat['name']}" created')));
                    } else ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(app.errorMessage ?? 'Failed to create category')));
                  }
                },
                child: const Text('Create Category', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      ),
    );

  void _showEditCategoryModal(BuildContext context, AppState app, Map<String, dynamic> category) {
    final nameCtrl = TextEditingController(text: category['name']?.toString() ?? '');
    String selectedType = category['type']?.toString() ?? 'BOTH';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 16, left: 16, right: 16, top: 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Manage Category', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)), onPressed: () async {
                  final confirm = await showDialog<bool>(context: context, builder: (dC) => AlertDialog(title: const Text('Delete Category'), content: Text('Are you sure you want to delete "${category['name']}"?'), actions: [TextButton(onPressed: () => Navigator.pop(dC, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(dC, true), child: const Text('Delete', style: TextStyle(color: Colors.red)))]));
                  if (confirm == true) {
                    final success = await app.deleteCategory(category['id'].toString());
                    if (mounted) {
                      Navigator.pop(ctx);
                      if (success) {
                        setState(() { if (_selectedCategory?['id'] == category['id']) _selectedCategory = null; });
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category deleted')));
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(app.errorMessage ?? 'Failed to delete category')));
                      }
                    }
                  }
                }),
              ]),
              const SizedBox(height: 16),
              TextField(controller: nameCtrl, decoration: InputDecoration(labelText: 'Category Name', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
              const SizedBox(height: 16),
              const Text('Applies To', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
              const SizedBox(height: 8),
              Row(children: [
                ChoiceChip(label: const Text('Both'), selected: selectedType == 'BOTH', onSelected: (v) => setModalState(() => selectedType = 'BOTH')),
                const SizedBox(width: 8),
                ChoiceChip(label: const Text('Inflow Only'), selected: selectedType == 'INFLOW', onSelected: (v) => setModalState(() => selectedType = 'INFLOW')),
                const SizedBox(width: 8),
                ChoiceChip(label: const Text('Outflow Only'), selected: selectedType == 'OUTFLOW', onSelected: (v) => setModalState(() => setModalState(() => selectedType = 'OUTFLOW'))),
              ]),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity, height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    final success = await app.updateCategory(id: category['id'].toString(), name: name, type: selectedType);
                    if (mounted) {
                      Navigator.pop(ctx);
                      if (success) {
                        setState(() { if (_selectedCategory?['id'] == category['id']) _selectedCategory = {..._selectedCategory!, 'name': name, 'type': selectedType}; });
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category updated')));
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(app.errorMessage ?? 'Failed to update category')));
                      }
                    }
                  },
                  child: const Text('Update Category', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ),
        ),
      );
    }
