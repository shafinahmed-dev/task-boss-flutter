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

  List<dynamic> _visibleSegments = [];
  final _amtCtl = TextEditingController();
  final _chgCtl = TextEditingController();
  final _noteCtl = TextEditingController();
  
  String? _selectedWalletId;
  String? _selectedPaymentMethod;
  List<dynamic> _wallets = [];
  bool _saving = false;
  String? _error;
  String get _tab => _flowType == 'INFLOW' ? 'in' : 'out';

  Map<String, dynamic>? _lastSavedReceipt;
  List<dynamic> _eligibleUsers = [];
  bool _loadingEligibleUsers = false;
  String? _selectedRecipientId;

  Future<void> _fetchEligibleUsers() async {
    final app = context.read<AppState>();
    if (app.user == null) return;
    setState(() {
      _loadingEligibleUsers = true;
      _error = null;
    });
    try {
      final res = await app.authRequest('GET', Uri.parse('${app.apiBaseUrl}/custody/custodians'));
      List<dynamic> rawUsers = [];
      if (res.statusCode == 200) {
        final rawData = jsonDecode(res.body);
        rawUsers = rawData is List ? rawData : (rawData['custodians'] ?? rawData['data'] ?? []);
      }

      final currentUserId = app.user?.id ?? app.user?.userId;
      final currentCustodianId = app.user?.custodianId;
      debugPrint('CURRENT LOGGED IN USER: $currentUserId, CUSTODIAN: $currentCustodianId');
      debugPrint('RAW USERS RECEIVED: ${rawUsers.length}');

      final currentId = currentUserId?.toString();
      final currentCustId = currentCustodianId?.toString();

      final eligible = rawUsers.where((u) {
        final uId = u['id']?.toString();
        final linkedUserId = u['linkedUserId']?.toString() ?? u['linkedUser']?['id']?.toString() ?? u['userId']?.toString();
        final role = (u['role'] ?? u['user']?['role'] ?? u['linkedUser']?['role'] ?? '').toString().toLowerCase();

        // Exclude current logged-in user (cannot handover to self)
        if (uId != null && uId == currentCustId) return false;
        if (linkedUserId != null && linkedUserId == currentId) return false;

        // Exclude suite administrative account
        if (role == 'suite' || role == 'admin' || role == 'suite_admin') return false;

        return true;
      }).toList();

      debugPrint('ELIGIBLE HANDOVER USERS: ${eligible.length}');

      if (mounted) {
        setState(() {
          _eligibleUsers = eligible;
          if (_selectedRecipientId == null && eligible.isNotEmpty) {
            _selectedRecipientId = eligible.first['id']?.toString();
          }
        });
      }
    } catch (e) {
      debugPrint('_fetchEligibleUsers error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loadingEligibleUsers = false;
        });
      }
    }
  }

  Widget _buildHandoverRecipientSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.swap_horiz_rounded, size: 18, color: AppTheme.slateMid),
              const SizedBox(width: 8),
              const Text(
                'Select User',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppTheme.primaryText,
                ),
              ),
              const Spacer(),
              if (_loadingEligibleUsers)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.refresh, size: 18, color: AppTheme.secondaryText),
                  onPressed: _fetchEligibleUsers,
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loadingEligibleUsers)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12.0),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (_eligibleUsers.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.pendingBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.pendingBorder),
              ),
              child: const Text(
                'No other users found in your company.',
                style: TextStyle(color: AppTheme.pendingText, fontSize: 13),
              ),
            )
          else
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _selectedRecipientId,
              hint: const Text('Select User', style: TextStyle(color: AppTheme.mutedText, fontSize: 13)),
              items: _eligibleUsers.map((u) {
                final uId = u['id']?.toString() ?? u['userId']?.toString() ?? '';
                final name = u['name'] ?? u['user']?['name'] ?? 'Unknown';
                final concern = u['concern_code'] ?? u['concernCode'] ?? u['concern'] ?? 'TDC';
                final designation = u['designation'] ?? u['role'] ?? '';
                final displayText = designation.isNotEmpty
                    ? '$name [$concern] • $designation'
                    : '$name [$concern]';

                return DropdownMenuItem<String>(
                  value: uId,
                  child: Text(
                    displayText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppTheme.primaryText,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (val) {
                setState(() => _selectedRecipientId = val);
              },
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _loadWallets() async {
    final app = context.read<AppState>();
    List<dynamic> loadedWallets = [];
    try {
      final identifier = (app.user?.custodianId.isNotEmpty ?? false)
          ? app.user!.custodianId
          : (app.user?.userId ?? '');
      final res = await app.authRequest(
        'GET',
        Uri.parse('${app.apiBaseUrl}/custody/wallets?custodianId=$identifier'),
      );
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        if (list.isNotEmpty) {
          loadedWallets = list;
          app.wallets = list.map((item) => Wallet.fromJson(item)).toList();
        }
      }
    } catch (_) {}

    if (loadedWallets.isEmpty) {
      await app.fetchWallets();
      if (app.wallets.isNotEmpty) {
        loadedWallets = app.wallets.map((w) => {
          'id': w.id,
          'name': w.name,
          'type': w.type,
          'isDefault': w.isDefault,
          'currentBalance': w.currentBalance,
          'balance': w.currentBalance,
        }).toList();
      }
    }
    await app.refreshBalance();

    debugPrint('[CaptureMovement] _loadWallets: ${_wallets.length} wallets, appState: ${app.wallets.length}');

    if (mounted) {
      final availableWallets = loadedWallets.isNotEmpty
          ? loadedWallets
          : app.wallets.map((w) => {
              'id': w.id,
              'name': w.name,
              'type': w.type,
              'isDefault': w.isDefault,
              'currentBalance': w.currentBalance,
              'balance': w.currentBalance,
            }).toList();

      if (availableWallets.isNotEmpty) {
        setState(() {
          _wallets = availableWallets;
          if (_selectedWalletId == null || !availableWallets.any((w) => w['id']?.toString() == _selectedWalletId)) {
            final defaultWallet = availableWallets.firstWhere(
              (w) => w['isDefault'] == true,
              orElse: () => availableWallets.first,
            );
            _selectedWalletId = defaultWallet['id']?.toString() ?? availableWallets.first['id']?.toString();
            final wType = defaultWallet['type']?.toString() ?? 'CASH';
            final methods = PaymentRails.getMethods(wType, _tab);
            _selectedPaymentMethod = methods.isNotEmpty ? methods.first : 'Physical Cash';
          }
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final app = context.read<AppState>();
      _fetchEligibleUsers();
      await _loadWallets();
      await app.fetchMyLedgers();
      if (app.myLedgers.isNotEmpty && mounted) {
        final genOps = app.myLedgers.firstWhere(
          (l) => l['code'] == 'GEN-OPS',
          orElse: () => app.myLedgers.first,
        );
        setState(() => _selectedLedgerId = genOps['id'].toString());
      }
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

  String? _selectedLedgerId;

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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 16, left: 16, right: 16, top: 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('New Segment', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
            const SizedBox(height: 16),
            TextField(
              controller: TextEditingController(text: name),
              onChanged: (val) => name = val,
              decoration: InputDecoration(labelText: 'Segment Name', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
            ),
            const SizedBox(height: 16),
            const Text('Applies To', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
            const SizedBox(height: 8),
            Row(
              children: [
                ChoiceChip(label: const Text('Both'), selected: type == 'BOTH', onSelected: (s) => setModalState(() => type = 'BOTH')),
                const SizedBox(width: 8),
                ChoiceChip(label: const Text('Inflow Only'), selected: type == 'INFLOW', onSelected: (s) => setModalState(() => type = 'INFLOW')),
                const SizedBox(width: 8),
                ChoiceChip(label: const Text('Outflow Only'), selected: type == 'OUTFLOW', onSelected: (s) => setModalState(() => type = 'OUTFLOW')),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity, height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () async {
                  if (name.isEmpty) return;
                  final messenger = ScaffoldMessenger.of(this.context);
                  final nav = Navigator.of(ctx);
                  final targetLedgerId = _selectedLedgerId ?? 'bd4bf36e-be9c-4bc2-b3dc-805c360b2164';
                  final newCat = await app.createCategory(name: name, type: type, companyId: cid);
                  if (!mounted) return;
                  if (newCat != null) {
                    final createdCat = {
                      'id': newCat['id']?.toString() ?? name,
                      'name': name,
                      'ledgerId': targetLedgerId,
                      'type': type,
                    };
                    setState(() {
                      app.concernCategories.removeWhere((c) => c['name'].toString().toLowerCase() == name.toLowerCase());
                      app.concernCategories.add(createdCat);
                      _selectedCategory = createdCat;
                      _categorySearchCtrl.clear();
                      _visibleSegments = app.concernCategories.where((s) => s['ledgerId'] == _selectedLedgerId).toList();
                    });
                    await app.fetchMyLedgers();


                    nav.pop();
                    messenger.showSnackBar(SnackBar(content: Text('Category "$name" created')));
                  } else {
                    messenger.showSnackBar(SnackBar(content: Text(app.errorMessage ?? 'Failed to create category')));
                  }
                },
                child: const Text('Create Category', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
  void _showEditCategoryModal(BuildContext context, AppState app, Map<String, dynamic> category) {
    String name = category['name']?.toString() ?? '';
    String type = category['type']?.toString() ?? 'BOTH';
    final categoryId = category['id']?.toString() ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Manage Category', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.delete_rounded, color: Colors.red),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(this.context);
                      final nav = Navigator.of(ctx);
                      final confirm = await showDialog<bool>(
                        context: ctx,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('Delete Category'),
                          content: const Text('Are you sure you want to delete this category?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext, true),
                              child: const Text('Delete', style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      );

                      if (confirm == true) {
                        try {
                          await app.deleteCategory(categoryId);
                          if (!mounted) return;
                          nav.pop();
                          if (_selectedCategory?['id'] == categoryId) {
                            setState(() {
                              _selectedCategory = null;
                            });
                          }
                          messenger.showSnackBar(
                            const SnackBar(content: Text('Category deleted successfully')),
                          );
                        } catch (e) {
                          if (!mounted) return;
                          messenger.showSnackBar(
                            SnackBar(content: Text('Failed to delete: ${e.toString()}')),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
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

                  final messenger = ScaffoldMessenger.of(this.context);
                  final nav = Navigator.of(ctx);
                  try {
                    await app.updateCategory(
                      id: categoryId,
                      name: name,
                      type: type,
                    );

                    if (!mounted) return;
                    nav.pop();
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Category updated successfully')),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    messenger.showSnackBar(
                      SnackBar(content: Text('Failed to update: ${e.toString()}')),
                    );
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
      String? effectiveLedgerId = _selectedLedgerId;
      if ((effectiveLedgerId == null || effectiveLedgerId.isEmpty) && app.myLedgers.isNotEmpty) {
        final genOps = app.myLedgers.firstWhere(
          (l) => l['code'] == 'GEN-OPS',
          orElse: () => app.myLedgers.first,
        );
        effectiveLedgerId = genOps['id']?.toString();
      }

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
        'ledgerId': effectiveLedgerId,
        'segmentId': _selectedCategory?['id'],
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
        await _loadWallets();
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
    final wallets = app.wallets.isNotEmpty
        ? app.wallets
        : _wallets.map((w) => Wallet.fromJson(Map<String, dynamic>.from(w))).toList();

    if (wallets.isNotEmpty) {
      if (_selectedWalletId == null || !wallets.any((w) => w.id == _selectedWalletId)) {
        final defaultWallet = wallets.firstWhere(
          (w) => w.isDefault,
          orElse: () => wallets.first,
        );
        _selectedWalletId = defaultWallet.id;
      }
    } else {
      _selectedWalletId = null;
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
      _selectedPaymentMethod = availableMethods.isNotEmpty ? availableMethods.first : 'Physical Cash';
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
            // Hidden on Activity Outflow (only shown on Handover tab)
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
                  const Text('Ledger', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.primaryText)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    key: ValueKey('ledger_${_selectedLedgerId ?? (app.myLedgers.isNotEmpty ? app.myLedgers.first['id'].toString() : 'none')}'),
                    initialValue: _selectedLedgerId ?? (app.myLedgers.isNotEmpty ? app.myLedgers.first['id'].toString() : null),
                    hint: const Text('Select Ledger', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: Color(0xFF94A3B8))),
                    items: app.myLedgers.map((l) {
                      final isGenOps = l['code'] == 'GEN-OPS';
                      final lName = l['name']?.toString() ?? 'Ledger';
                      return DropdownMenuItem<String>(
                        value: l['id'].toString(),
                        child: Text(
                          isGenOps ? '$lName (Default)' : lName,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() {
                      _selectedLedgerId = v;
                      _selectedCategory = null;
                    }),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFFF1F5F9),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildCategoryCard(app),
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
                        isExpanded: true,
                        hint: Text(
                          wallets.isEmpty ? 'No wallets found' : 'Select Wallet',
                          style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                        ),
                        items: wallets.map((w) {
                          final walletLabel = '${w.name} (৳${w.currentBalance.toStringAsFixed(0)})';
                          return DropdownMenuItem<String>(
                            value: w.id,
                            child: Text(
                              walletLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          );
                        }).toList(),
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
                              isExpanded: true,
                              initialValue: availableMethods.contains(_selectedPaymentMethod) ? _selectedPaymentMethod : availableMethods.first,
                              items: availableMethods.map((m) => DropdownMenuItem<String>(
                                value: m,
                                child: Text(
                                  m,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                ),
                              )).toList(),
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
                      color: AppTheme.outflowText,
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

    Map<String, dynamic>? selectedLedger;
    if (_selectedLedgerId != null && app.myLedgers.isNotEmpty) {
      try {
        selectedLedger = app.myLedgers.firstWhere(
          (l) => l['id'].toString() == _selectedLedgerId,
        );
      } catch (_) {}
    }
    if (selectedLedger == null && app.myLedgers.isNotEmpty) {
      selectedLedger = app.myLedgers.firstWhere(
        (l) => l['code'] == 'GEN-OPS',
        orElse: () => app.myLedgers.first,
      );
    }

    List<dynamic> categories = [];
    if (selectedLedger != null &&
        selectedLedger['segments'] is List &&
        (selectedLedger['segments'] as List).isNotEmpty) {
      categories = (selectedLedger['segments'] as List).where((s) {
        final matchesSearch = query.isEmpty ||
            (s['name']?.toString().toLowerCase().contains(query) ?? false);
        return matchesSearch;
      }).toList();
    } else {
      categories = app.concernCategories.where((c) {
        final matchesFlow = c['type'] == _flowType || c['type'] == 'BOTH';
        final matchesSearch = query.isEmpty ||
            (c['name']?.toString().toLowerCase().contains(query) ?? false);
        return matchesFlow && matchesSearch;
      }).toList();
    }

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
        const Row(
          children: [
            Icon(Icons.category_outlined, size: 18, color: Color(0xFF0F172A)),
            SizedBox(width: 8),
            Text(
              'Segment',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Search
        SizedBox(
          height: 42,
          child: TextField(
            controller: _categorySearchCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search or type new segment...',
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
      height: 52,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A), // Deep Obsidian Glass Track
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // 1. INFLOW TAB (EMERALD GLOW GRADIENT WHEN ACTIVE)
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (!isInflow) {
                  setState(() {
                    _flowType = 'INFLOW';
                    _selectedCategory = null;
                  });
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: isInflow
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF059669), // Vivid Emerald
                            Color(0xFF047857), // Deep Forest Emerald
                          ],
                        )
                      : null,
                  color: isInflow ? null : Colors.transparent,
                  boxShadow: isInflow
                      ? [
                          BoxShadow(
                            color: const Color(0xFF10B981).withValues(alpha: 0.45),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.arrow_downward_rounded,
                        size: 16,
                        color: isInflow ? Colors.white : Colors.white.withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Inflow',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isInflow ? FontWeight.w700 : FontWeight.w500,
                          color: isInflow ? Colors.white : Colors.white.withValues(alpha: 0.6),
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 2. OUTFLOW TAB (ROSE/RUBY GLOW GRADIENT WHEN ACTIVE)
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (isInflow) {
                  setState(() {
                    _flowType = 'OUTFLOW';
                    _selectedCategory = null;
                  });
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: !isInflow
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFFE11D48), // Rose Crimson
                            Color(0xFFBE123C), // Deep Ruby Red
                          ],
                        )
                      : null,
                  color: !isInflow ? null : Colors.transparent,
                  boxShadow: !isInflow
                      ? [
                          BoxShadow(
                            color: const Color(0xFFF43F5E).withValues(alpha: 0.45),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.arrow_upward_rounded,
                        size: 16,
                        color: !isInflow ? Colors.white : Colors.white.withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Outflow',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: !isInflow ? FontWeight.w700 : FontWeight.w500,
                          color: !isInflow ? Colors.white : Colors.white.withValues(alpha: 0.6),
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

}
