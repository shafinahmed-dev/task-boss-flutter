import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:task_boss/theme.dart';
import 'package:task_boss/models/models.dart';
import 'package:task_boss/services/app_state.dart';
import 'package:task_boss/utils/show_receipt_modal.dart';

import 'package:shared_preferences/shared_preferences.dart';
/// Enables mouse-drag (and trackpad/stylus) scrolling on Flutter Web/Desktop.
/// By default Flutter Web restricts drag-scroll to touch pointers only.
class WebDragScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

class CaptureMovementScreen extends StatefulWidget {
  const CaptureMovementScreen({super.key});
  @override
  State<CaptureMovementScreen> createState() => _CaptureState();
}

class _CaptureState extends State<CaptureMovementScreen> {
  String _flowType = 'INFLOW'; // INFLOW | OUTFLOW
  Map<String, dynamic>? _selectedCategory;
  final TextEditingController _categorySearchCtrl = TextEditingController();
  String _catSearchQuery = '';

  final _amtCtl = TextEditingController();
  final _chgCtl = TextEditingController();
  final _noteCtl = TextEditingController();
  
  String? _selectedWalletId;
  String? _selectedPaymentMethod;
  bool _saving = false;
  String? _error;
  String get _tab => _flowType == 'INFLOW' ? 'in' : 'out';

  Map<String, dynamic>? _lastSavedReceipt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final app = context.read<AppState>();
      // If company ID not yet initialized, load overview to establish it
      if (app.selectedManagerCompanyId == null || app.selectedManagerCompanyId!.isEmpty) {
        await app.fetchManagerOverview();
      }
      final cid = _getEffectiveCompanyId(app);
      if (cid.isNotEmpty) {
        await app.fetchCategories(companyId: cid);
      }
    });
    _loadDraft();
  }

  String _getEffectiveCompanyId(AppState app) {
    return app.effectiveCompanyId;
  }

  @override
  void dispose() {
    _categorySearchCtrl.dispose();
    super.dispose();
  }

  void _showAddCategoryModal(BuildContext context, AppState app) {
    String name = _categorySearchCtrl.text.trim();
    String type = 'BOTH';
    final cid = _getEffectiveCompanyId(app);
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('New Category / Project Ledger', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: TextEditingController(text: name),
                onChanged: (val) => name = val,
                decoration: const InputDecoration(labelText: 'Category Name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ChoiceChip(label: const Text('Inflow Only'), selected: type == 'INFLOW', onSelected: (s) => setModalState(() => type = 'INFLOW')),
                  ChoiceChip(label: const Text('Outflow Only'), selected: type == 'OUTFLOW', onSelected: (s) => setModalState(() => type = 'OUTFLOW')),
                  ChoiceChip(label: const Text('Both'), selected: type == 'BOTH', onSelected: (s) => setModalState(() => type = 'BOTH')),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  if (name.isEmpty) return;

                  try {
                    await app.createCategory(
                      name: name,
                      type: type,
                      companyId: cid,
                    );

                    if (mounted) {
                      setState(() {
                        _categorySearchCtrl.clear();
                      });
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Category "$name" created')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to create category: ${e.toString()}')),
                      );
                    }
                  }
                },
                child: const Text('Create Category'),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditCategoryModal(BuildContext c, AppState a, Map<String, dynamic> cat) {
    final nCtrl = TextEditingController(text: cat['name']?.toString() ?? '');
    String sType = cat['type']?.toString() ?? 'BOTH';
    showModalBottomSheet(context: c, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 16, left: 16, right: 16, top: 16), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Manage Category', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
        IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)), onPressed: () async {
          final confirm = await showDialog<bool>(context: c, builder: (dC) => AlertDialog(title: const Text('Delete Category'), content: Text('Are you sure you want to delete "${cat['name']}"?'), actions: [TextButton(onPressed: () => Navigator.pop(dC, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(dC, true), child: const Text('Delete', style: TextStyle(color: Colors.red)))]));
          if (confirm == true) { final s = await a.deleteCategory(cat['id']); if (c.mounted) { Navigator.pop(ctx); if (s) { setState(() { if (_selectedCategory?['id'] == cat['id']) _selectedCategory = null; }); ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Category deleted'))); } else ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(a.errorMessage ?? 'Failed to delete category'))); } }
        })
      ]),
      const SizedBox(height: 16), TextField(controller: nCtrl, decoration: InputDecoration(labelText: 'Category Name', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
      const SizedBox(height: 16), const Text('Applies To', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF64748B))), const SizedBox(height: 8),
      Row(children: [
        ChoiceChip(label: const Text('Inflow Only'), selected: sType == 'INFLOW', onSelected: (v) => setS(() => sType = 'INFLOW')), const SizedBox(width: 8),
        ChoiceChip(label: const Text('Outflow Only'), selected: sType == 'OUTFLOW', onSelected: (v) => setS(() => sType = 'OUTFLOW')), const SizedBox(width: 8),
        ChoiceChip(label: const Text('Both'), selected: sType == 'BOTH', onSelected: (v) => setS(() => sType = 'BOTH'))
      ]),
      const SizedBox(height: 20), SizedBox(width: double.infinity, height: 48, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), onPressed: () async {
        final n = nCtrl.text.trim(); if (n.isEmpty) return; final s = await a.updateCategory(id: cat['id'], name: n, type: sType);
        if (c.mounted) { Navigator.pop(ctx); if (s) { setState(() { if (_selectedCategory?['id'] == cat['id']) _selectedCategory = {..._selectedCategory!, 'name': n, 'type': sType}; }); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category updated'))); } else ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(a.errorMessage ?? 'Failed to update category'))); }
      }, child: const Text('Update Category', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))))
    ])))));
  }

                onPressed: () async {
                  if (name.isEmpty) return;

                  try {
                    await app.updateCategory(
                      id: categoryId,
                      name: name,
                      type: type,
                    );

                    if (mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Category updated successfully')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to update: ${e.toString()}')),
                      );
                    }
                  }
                },
                child: const Text('Update Category'),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }


        ),
      ),
    );
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

  bool get _isOtherTag => false;

  String _getEntryTag(String flowType, String? catName) {
    if (flowType == 'INFLOW') {
      return 'client_payment';
    }
    return 'outflow';
  }

  List<dynamic> _getCategories(AppState app) {
    return app.concernCategories.where((c) => c['type'] == 'BOTH' || c['type'] == _flowType).toList();
  }


  Future<void> _submit() async {
    setState(() => _error = null);
    final app = context.read<AppState>();
    if (app.user == null) {
      setState(() => _error = 'Session expired. Please log in again.');
      return;
    }

    final wallets = app.wallets;
    Wallet? selectedWallet;
    if (_selectedWalletId != null && wallets.isNotEmpty) {
      selectedWallet = wallets.firstWhere((w) => w.id == _selectedWalletId, orElse: () => wallets.first);
    } else if (wallets.isNotEmpty) {
      selectedWallet = wallets.first;
    }

    if (selectedWallet == null) {
      setState(() => _error = 'No active wallet found. Please create a wallet first.');
      return;
    }

    final amt = double.tryParse(_amtCtl.text.trim());
    if (amt == null || amt <= 0) {
      setState(() => _error = 'Enter an amount to continue');
      return;
    }
    final feeText = _chgCtl.text.trim();
    final feeVal = feeText.isEmpty ? 0.0 : (double.tryParse(feeText) ?? -1.0);
    if (feeVal < 0) {
      setState(() => _error = 'Please enter a valid fee/charge (0 or greater).');
      return;
    }
    final noteText = _noteCtl.text.trim();

    if (_selectedCategory == null) {
      setState(() => _error = 'Please select a Category / Project Ledger.');
      return;
    }

    final availableMethods = PaymentRails.getMethods(selectedWallet.type, _flowType == 'INFLOW' ? 'in' : 'out');
    final paymentMethod = (_selectedPaymentMethod != null && availableMethods.contains(_selectedPaymentMethod))
        ? _selectedPaymentMethod!
        : availableMethods.first;

    setState(() => _saving = true);
    try {
      final receiptNo = 'TRX-${const Uuid().v4().substring(0, 8).toUpperCase()}';
      final payload = {
        'idempotencyKey': const Uuid().v4(),
        'direction': _flowType == 'INFLOW' ? 'in' : 'out',
        'amount': amt,
        'currency': 'BDT',
        'channel': selectedWallet.type.toLowerCase(),
        'walletId': selectedWallet.id,
        'paymentMethod': paymentMethod,
        'companyId': app.user!.companyId,
        'collectorId': app.user!.userId,
        'custodianId': app.user!.custodianId,
        'entryTag': _getEntryTag(_flowType, _selectedCategory?['name']),
        'categoryId': _selectedCategory?['id'],
        'occurredAt': DateTime.now().toIso8601String(),
        'notes': noteText.isNotEmpty ? noteText : null,
        'note': noteText.isNotEmpty ? noteText : null,
        'description': noteText.isNotEmpty ? noteText : null,
        'metadata': {
          'category': _selectedCategory?['name'],
          'categoryId': _selectedCategory?['id'],
          'movementType': _flowType == 'INFLOW' ? 'Cash In' : 'Cash Out',
          'note': noteText,
          'notes': noteText,
          'baseAmount': amt,
          'fee': feeVal,
          'channel': selectedWallet.type.toLowerCase(),
          'walletId': selectedWallet.id,
          'paymentMethod': paymentMethod,
          'walletName': selectedWallet.name,
          'directionTab': _flowType == 'INFLOW' ? 'in' : 'out',
          'voucherNumber': receiptNo,
        },
      };

      final res = await app.authRequest(
        'POST',
        Uri.parse('${app.apiBaseUrl}/ledger/movements'),
        headers: {
          'Content-Type': 'application/json',
          'x-company-id': app.user!.companyId
        },
        body: jsonEncode(payload),
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final resData = jsonDecode(res.body);
        final returnedNo = resData['receiptNo'] ?? resData['metadata']?['voucherNumber'] ?? receiptNo;

        setState(() {
          _lastSavedReceipt = {
            'receiptNo': returnedNo,
            'date': DateTime.now(),
            'type': _flowType == 'INFLOW' ? 'Cash In' : 'Cash Out',
            'category': _selectedCategory?['name'],
            'wallet': selectedWallet!.name,
            'method': paymentMethod,
            'note': noteText,
            'amount': amt,
            'fee': feeVal,
          };
          _amtCtl.clear();
          _chgCtl.clear();
          _noteCtl.clear(); _clearDraft();
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Transaction saved successfully!'),
              backgroundColor: AppTheme.confirmedText,
            ),
          );
        }
        await app.refreshBalance();
      } else {
        final err = jsonDecode(res.body)['message'];
        throw Exception(err is List ? err.join(', ') : (err?.toString() ?? 'Failed (HTTP ${res.statusCode})'));
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final wallets = app.wallets;

    if (_selectedWalletId == null && wallets.isNotEmpty) {
      final defaultWallet = wallets.firstWhere((w) => w.isDefault, orElse: () => wallets.first);
      _selectedWalletId = defaultWallet.id;
    }

    Wallet? selectedWallet;
    if (_selectedWalletId != null && wallets.isNotEmpty) {
      selectedWallet = wallets.firstWhere(
        (w) => w.id == _selectedWalletId,
        orElse: () => wallets.first,
      );
    }

    final availableMethods = selectedWallet != null
        ? PaymentRails.getMethods(selectedWallet.type, _tab)
        : ['Physical Cash'];

    if (_selectedPaymentMethod == null || !availableMethods.contains(_selectedPaymentMethod)) {
      _selectedPaymentMethod = availableMethods.first;
    }

    final amtVal = double.tryParse(_amtCtl.text.trim()) ?? 0.0;
    final feeVal = double.tryParse(_chgCtl.text.trim()) ?? 0.0;
    return Scaffold(
      backgroundColor: AppTheme.canvas,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Transactions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.slateDark)),
            const SizedBox(height: 12),
            if (_error != null) _banner(_error!),
            _buildFlowPill(),
            const SizedBox(height: 14),
            _buildCategoryCard(context.watch<AppState>()),
            const SizedBox(height: 14),
            // Card 2: Wallet & Method
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.account_balance_wallet_outlined, size: 18, color: AppTheme.slateMid),
                      SizedBox(width: 8),
                      Text(
                        'Source Wallet & Method',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: AppTheme.primaryText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Wallet',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          )),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        key: ValueKey('wallet_$_selectedWalletId'),
                        initialValue: _selectedWalletId,
                        items: wallets.map((w) => DropdownMenuItem<String>(value: w.id, child: Text('${w.name} (৳${w.currentBalance.toStringAsFixed(0)})', overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)))).toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setState(() {
                              _selectedWalletId = v;
                              final newlySelected = wallets.firstWhere((w) => w.id == v);
                              final methods = PaymentRails.getMethods(newlySelected.type, _tab);
                              _selectedPaymentMethod = methods.first;
                            });
                          }
                        },
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFFF1F5F9),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Method',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          )),
                      const SizedBox(height: 6),
                      selectedWallet?.type.toUpperCase() == 'CASH'
                          ? Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Text('Physical Cash',
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                  overflow: TextOverflow.ellipsis),
                            )
                          : DropdownButtonFormField<String>(
                              key: ValueKey('method_${selectedWallet?.id}_$_selectedPaymentMethod'),
                              initialValue: availableMethods.contains(_selectedPaymentMethod) ? _selectedPaymentMethod : availableMethods.first,
                              items: availableMethods.map((m) => DropdownMenuItem<String>(value: m, child: Text(m, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12), overflow: TextOverflow.ellipsis))).toList(),
                              onChanged: (v) {
                                if (v != null) setState(() => _selectedPaymentMethod = v);
                              },
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: const Color(0xFFF1F5F9),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              ),
                            ),
                    ],
                  ),
                ),
              ],
            ),
                ],
              ),
          ),
          const SizedBox(height: 14),
          // Card 3: Amount Details
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.payments_outlined, size: 18, color: AppTheme.slateMid),
                    SizedBox(width: 8),
                    Text(
                      'Amount Details',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppTheme.primaryText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
            // Symmetrical 2x2 Layout - Row 2: Amount & Fee
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Amount',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          )),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _amtCtl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                        decoration: InputDecoration(
                          hintText: '0.00',
                          hintStyle: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFCBD5E1),
                          ),
                          prefixIcon: const Padding(
                            padding: EdgeInsets.only(left: 14, right: 6),
                            child: Text(
                              '৳',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ),
                          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xFF94A3B8), width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                        ),
                        onChanged: (_) { _saveDraft(); setState(() {}); },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Fee / Charge',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _chgCtl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                        decoration: InputDecoration(
                          hintText: '0.00',
                          hintStyle: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFCBD5E1),
                          ),
                          prefixIcon: const Padding(
                            padding: EdgeInsets.only(left: 14, right: 6),
                            child: Text(
                              '৳',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ),
                          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xFF94A3B8), width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                        ),
                        onChanged: (_) {
                          _saveDraft();
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Note input field below them with comfortable spacing
            Row(
              children: [
                const Text(
                  'Note',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
                if (_isOtherTag)
                  const Text(
                    ' * (Required)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: AppTheme.expenseText,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _noteCtl,
              decoration: InputDecoration(
                hintText: _isOtherTag ? "Required for 'Other'..." : "Note...",
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              onChanged: (_) {
                _saveDraft();
                setState(() {});
              },
            ),
          ],
        ),
      ),
            const SizedBox(height: 14),
            if (amtVal > 0 || feeVal > 0) Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppTheme.cardBg, border: Border.all(color: AppTheme.cardBorder), borderRadius: BorderRadius.circular(10)),
              child: Column(children: [
                _row('Base Amount:', '৳${amtVal.toStringAsFixed(2)}'),
                if (feeVal > 0) _row('Fee / Charge (Expense):', '৳${feeVal.toStringAsFixed(2)}'),
                const Divider(),
                _row(_tab == 'in' ? 'Total Inflow:' : 'Total Outflow:', _tab == 'in' ? '৳${amtVal.toStringAsFixed(2)}' : '৳${(amtVal + feeVal).toStringAsFixed(2)}', bold: true),
              ]),
            ),
            const SizedBox(height: 20),
            Center(
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: AppTheme.slateButtonGradient,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    onPressed: _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 18),
                    label: Text(
                      _saving ? 'Saving...' : 'Save',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: _lastSavedReceipt == null
                  ? const Text(
                      'Hit Save to Generate Receipt',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w500),
                    )
                  : TextButton.icon(
                      onPressed: () {
                        final r = _lastSavedReceipt!;
                        showReceiptModal(
                          context,
                          receiptNo: r['receiptNo'],
                          date: r['date'],
                          type: r['type'],
                          categoryOrRecipient: r['category'],
                          wallet: r['wallet'],
                          method: r['method'],
                          note: r['note'],
                          amount: r['amount'],
                          fee: r['fee'],
                        );
                      },
                      icon: const Icon(Icons.download_rounded, color: Color(0xFF2563EB), size: 18),
                      label: const Text(
                        'Download Receipt',
                        style: TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _banner(String t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        border: Border.all(color: const Color(0xFFFEE2E2)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(t, style: const TextStyle(fontSize: 13, color: Color(0xFF991B1B))),
    );
  }
  Widget _buildCategoryCard(AppState app) {
  final query = _categorySearchCtrl.text.trim().toLowerCase();
  final categories = app.concernCategories.where((c) {
    final matchesFlow = c['type'] == _flowType || c['type'] == 'BOTH';
    final matchesSearch = query.isEmpty ||
        (c['name']?.toString().toLowerCase().contains(query) ?? false);
    return matchesFlow && matchesSearch;
  }).toList();

  final isManager = app.currentUser?.role != 'EMPLOYEE';

  return Container(
    margin: const EdgeInsets.symmetric(vertical: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.category_outlined, size: 18, color: Color(0xFF0F172A)),
            SizedBox(width: 8),
            Text(
              'Category / Project Ledger',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Search & Add Row
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 42,
                child: TextField(
                  controller: _categorySearchCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search categories or projects...',
                    hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                    prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF64748B)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                ),
              ),
            ),
            if (isManager) ...[
              const SizedBox(width: 8),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: IconButton(
                  icon: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
                  padding: EdgeInsets.zero,
                  tooltip: 'Add Category',
                  onPressed: () => _showAddCategoryModal(context, app),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
          // Category Pills or Empty State via clean ternary (no semicolons in list)
        categories.isNotEmpty
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: categories.map((c) {
                    final isSelected = _selectedCategory?["id"] == c["id"];
                    final isInflow = _flowType == "INFLOW";
                    final activeBorderColor = isInflow ? const Color(0xFF10B981) : const Color(0xFFEF4444);
                    final activeBgColor = isInflow ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2);

                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          setState(() {
                            _selectedCategory = isSelected ? null : c;
                          });
                        },
                        onLongPress: () {
                          if (app.currentUser?.role != 'EMPLOYEE') {
                            _showEditCategoryModal(context, app, c);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? activeBgColor : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected ? activeBorderColor : const Color(0xFFE2E8F0),
                              width: isSelected ? 1.5 : 1.0,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isSelected) ...[
                                Icon(Icons.check_rounded, size: 14, color: activeBorderColor),
                                const SizedBox(width: 4),
                              ],
                              Text(
                                c["name"]?.toString() ?? "",
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF475569),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: isManager && _categorySearchCtrl.text.trim().isNotEmpty
                    ? ActionChip(
                        backgroundColor: const Color(0xFFF8FAFC),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                        avatar: const Icon(Icons.add_rounded, size: 16, color: Color(0xFF0F172A)),
                        label: Text(
                          "Create \"${_categorySearchCtrl.text.trim()}\"",
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        onPressed: () => _showAddCategoryModal(context, app),
                      )
                    : const Text(
                        "No categories found.",
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                      ),
              ),
        ],
      ),
    );
  }


  Widget _row(String l, String v, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(l, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
      Text(v, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w900 : FontWeight.bold, color: bold ? AppTheme.primaryGradientFallback : Colors.black)),
    ]),
  );
  Widget _buildFlowPill() {
  final isInflow = _flowType == 'INFLOW';
  return Container(
    height: 48,
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: const Color(0xFF1E2638),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () {
              if (_flowType != 'INFLOW') {
                setState(() {
                  _flowType = 'INFLOW';
                  _selectedCategory = null;
                });
              }
            },
            child: Container(
              decoration: BoxDecoration(
                color: isInflow ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.arrow_downward_rounded,
                    size: 16,
                    color: isInflow ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Inflow',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isInflow ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: () {
              if (_flowType != 'OUTFLOW') {
                setState(() {
                  _flowType = 'OUTFLOW';
                  _selectedCategory = null;
                });
              }
            },
            child: Container(
              decoration: BoxDecoration(
                color: !isInflow ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.arrow_upward_rounded,
                    size: 16,
                    color: !isInflow ? const Color(0xFFEF4444) : const Color(0xFF94A3B8),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Outflow',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: !isInflow ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

}
