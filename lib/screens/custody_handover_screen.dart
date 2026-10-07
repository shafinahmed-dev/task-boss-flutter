import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:task_boss/theme.dart';
import 'package:task_boss/models/models.dart';
import 'package:task_boss/services/app_state.dart';
import 'package:task_boss/utils/show_receipt_modal.dart';

class CustodyHandoverScreen extends StatefulWidget {
  const CustodyHandoverScreen({super.key});

  @override
  State<CustodyHandoverScreen> createState() => _CustodyHandoverScreenState();
}

class _CustodyHandoverScreenState extends State<CustodyHandoverScreen> {
  final _amtCtl = TextEditingController();
  final _feeCtl = TextEditingController();
  final _noteCtl = TextEditingController();

  bool _loadingCustodians = true;
  bool _saving = false;
  String? _error;

  List<dynamic> _custodians = [];
  String? _selectedCustodianId;
  String? _selectedWalletId;
  String? _selectedPaymentMethod;

  Map<String, dynamic>? _lastSavedReceipt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _amtCtl.dispose();
    _feeCtl.dispose();
    _noteCtl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final app = context.read<AppState>();
    if (app.wallets.isEmpty) {
      await app.refreshBalance();
    }
    await _fetchCustodians();
  }

  Future<void> _fetchCustodians() async {
    final app = context.read<AppState>();
    if (app.user == null) return;
    setState(() {
      _loadingCustodians = true;
      _error = null;
    });
    try {
      final url = Uri.parse(
          '${app.apiBaseUrl}/custody/custodians?companyId=${app.user!.companyId}');
      final res = await app.authRequest('GET', url);
      if (res.statusCode == 200) {
        final rawData = jsonDecode(res.body);
        List<dynamic> allCustodians = [];
        if (rawData is List) {
          allCustodians = rawData;
        } else if (rawData is Map && rawData['custodians'] is List) {
          allCustodians = rawData['custodians'] as List;
        } else if (rawData is Map && rawData['data'] is List) {
          allCustodians = rawData['data'] as List;
        }
        final others = allCustodians.where((c) {
          final cId =
              c['id']?.toString() ?? c['custodianId']?.toString() ?? '';
          return cId != app.user!.custodianId;
        }).toList();
        setState(() {
          _custodians = others;
          _loadingCustodians = false;
        });
      } else {
        setState(() {
          _custodians = [];
          _loadingCustodians = false;
        });
      }
    } catch (e) {
      setState(() {
        _custodians = [];
        _loadingCustodians = false;
        _error = 'Could not load users. Please try again.';
      });
    }
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
      selectedWallet = wallets.firstWhere(
        (w) => w.id == _selectedWalletId,
        orElse: () => wallets.first,
      );
    } else if (wallets.isNotEmpty) {
      selectedWallet = wallets.first;
    }

    if (selectedWallet == null) {
      setState(
          () => _error = 'No active wallet found. Please create a wallet first.');
      return;
    }

    if (_selectedCustodianId == null || _selectedCustodianId!.isEmpty) {
      setState(() => _error = 'Please select a recipient user.');
      return;
    }

    final amt = double.tryParse(_amtCtl.text.trim());
    if (amt == null || amt <= 0) {
      setState(() => _error = 'Please enter a valid amount greater than 0.');
      return;
    }

    final feeText = _feeCtl.text.trim();
    final feeVal = feeText.isEmpty ? 0.0 : (double.tryParse(feeText) ?? -1.0);
    if (feeVal < 0) {
      setState(() => _error = 'Please enter a valid fee (0 or greater).');
      return;
    }

    final noteText = _noteCtl.text.trim();
    final availableMethods = PaymentRails.getMethods(selectedWallet.type, 'out');
    final paymentMethod =
        (_selectedPaymentMethod != null &&
                availableMethods.contains(_selectedPaymentMethod))
            ? _selectedPaymentMethod!
            : availableMethods.first;

    dynamic recipientData;
    try {
      recipientData = _custodians.firstWhere(
        (c) =>
            (c['id']?.toString() ?? c['custodianId']?.toString() ?? '') ==
            _selectedCustodianId,
      );
    } catch (_) {
      recipientData = null;
    }
    final recipientName = recipientData != null
        ? (recipientData['name'] ??
                recipientData['custodianName'] ??
                recipientData['user']?['name'] ??
                'Unknown')
            .toString()
        : 'Unknown';

    setState(() => _saving = true);
    try {
      final receiptNo =
          'HND-${const Uuid().v4().substring(0, 8).toUpperCase()}';
      final payload = {
        'idempotencyKey': const Uuid().v4(),
        'fromCustodianId': app.user!.custodianId,
        'toCustodianId': _selectedCustodianId,
        'companyId': app.user!.companyId,
        'amount': amt,
        'fee': feeVal,
        'currency': 'BDT',
        'walletId': selectedWallet.id,
        'paymentMethod': paymentMethod,
        'notes': noteText.isNotEmpty ? noteText : null,
        'note': noteText.isNotEmpty ? noteText : null,
        'metadata': {
          'walletId': selectedWallet.id,
          'walletName': selectedWallet.name,
          'paymentMethod': paymentMethod,
          'fee': feeVal,
          'note': noteText,
          'notes': noteText,
          'voucherNumber': receiptNo,
          'recipientName': recipientName,
        },
      };

      final res = await app.authRequest(
        'POST',
        Uri.parse('${app.apiBaseUrl}/custody/transfers'),
        headers: {
          'Content-Type': 'application/json',
          'x-company-id': app.user!.companyId,
        },
        body: jsonEncode(payload),
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final resData = jsonDecode(res.body);
        final returnedNo = resData['receiptNo'] ??
            resData['metadata']?['voucherNumber'] ??
            receiptNo;

        setState(() {
          _lastSavedReceipt = {
            'receiptNo': returnedNo,
            'date': DateTime.now(),
            'type': 'Handover Sent',
            'category': 'To: $recipientName',
            'wallet': selectedWallet!.name,
            'method': paymentMethod,
            'note': noteText,
            'amount': amt,
            'fee': feeVal,
          };
          _amtCtl.clear();
          _feeCtl.clear();
          _noteCtl.clear();
          _selectedCustodianId = null;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Handover transfer submitted successfully!'),
              backgroundColor: AppTheme.confirmedText,
            ),
          );
        }
        await app.refreshBalance();
      } else {
        final errBody = jsonDecode(res.body);
        final errMsg = errBody['message'];
        throw Exception(errMsg is List
            ? errMsg.join(', ')
            : (errMsg?.toString() ?? 'Failed (HTTP ${res.statusCode})'));
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
      final defaultWallet = wallets.firstWhere(
        (w) => w.isDefault,
        orElse: () => wallets.first,
      );
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
        ? PaymentRails.getMethods(selectedWallet.type, 'out')
        : ['Physical Cash'];

    if (_selectedPaymentMethod == null ||
        !availableMethods.contains(_selectedPaymentMethod)) {
      _selectedPaymentMethod = availableMethods.first;
    }

    final amtVal = double.tryParse(_amtCtl.text.trim()) ?? 0.0;
    final feeVal = double.tryParse(_feeCtl.text.trim()) ?? 0.0;

    return Scaffold(
      backgroundColor: AppTheme.canvas,
      body: RefreshIndicator(
        onRefresh: _fetchCustodians,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Handover',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.slateDark,
                ),
              ),
              const SizedBox(height: 16),
              if (_error != null) _banner(_error!),
              _buildRecipientSection(),
              const SizedBox(height: 14),
              _buildWalletSection(wallets, selectedWallet, availableMethods),
              const SizedBox(height: 14),
              _buildAmountSection(),
              const SizedBox(height: 14),
              if (amtVal > 0) _buildSummary(amtVal, feeVal),
              const SizedBox(height: 20),
              _buildSubmitButton(wallets),
              const SizedBox(height: 14),
              _buildReceiptLink(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildRecipientSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.swap_horiz_rounded,
                  size: 18, color: AppTheme.slateMid),
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
              if (_loadingCustodians)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                GestureDetector(
                  onTap: _fetchCustodians,
                  child: const Icon(Icons.refresh,
                      size: 18, color: AppTheme.secondaryText),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loadingCustodians)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12.0),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (_custodians.isEmpty)
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
              initialValue: _selectedCustodianId,
              hint: const Text('Select User',
                  style: TextStyle(color: AppTheme.mutedText, fontSize: 13)),
              items: _custodians.map((c) {
                final cId =
                    c['id']?.toString() ?? c['custodianId']?.toString() ?? '';
                final cName = c['name']?.toString() ??
                    c['custodianName']?.toString() ??
                    c['user']?['name']?.toString() ??
                    'Unknown';
                final cRole = c['role']?.toString() ??
                    c['user']?['role']?.toString() ??
                    '';
                return DropdownMenuItem<String>(
                  value: cId,
                  child: Text(
                    cRole.isNotEmpty ? '$cName ($cRole)' : cName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                );
              }).toList(),
              onChanged: (v) => setState(() => _selectedCustodianId = v),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
        ],
      ),
    );
  }


  Widget _buildWalletSection(
      List<Wallet> wallets, Wallet? selectedWallet, List<String> availableMethods) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.account_balance_wallet,
                  size: 18, color: AppTheme.slateMid),
              SizedBox(width: 8),
              Text(
                'Source Wallet & Payment',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppTheme.primaryText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (wallets.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.pendingBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.pendingBorder),
              ),
              child: const Text(
                'No wallets found. Please create a wallet first.',
                style: TextStyle(color: AppTheme.pendingText, fontSize: 13),
              ),
            )
          else
            _buildWalletPaymentRow(wallets, selectedWallet, availableMethods),
        ],
      ),
    );
  }

  Widget _buildWalletPaymentRow(
      List<Wallet> wallets, Wallet? selectedWallet, List<String> availableMethods) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Wallet',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Color(0xFF64748B))),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                key: ValueKey('wallet_$_selectedWalletId'),
                initialValue: _selectedWalletId,
                items: wallets
                    .map((w) => DropdownMenuItem<String>(
                          value: w.id,
                          child: Text(
                            '${w.name} (৳${w.currentBalance.toStringAsFixed(0)})',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      _selectedWalletId = v;
                      final w = wallets.firstWhere((w) => w.id == v);
                      final methods = PaymentRails.getMethods(w.type, 'out');
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
                      fontSize: 13,
                      color: Color(0xFF64748B))),
              const SizedBox(height: 6),
              selectedWallet?.type.toUpperCase() == 'CASH'
                  ? InputDecorator(
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFFF1F5F9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      child: const Text('Physical Cash',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13),
                          overflow: TextOverflow.ellipsis),
                    )
                  : DropdownButtonFormField<String>(
                      key: ValueKey('method_${selectedWallet?.type}_out'),
                      initialValue: _selectedPaymentMethod,
                      items: availableMethods
                          .map((m) => DropdownMenuItem<String>(
                                value: m,
                                child: Text(m,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13)),
                              ))
                          .toList(),
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
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
            ],
          ),
        ),
      ],
    );
  }


  Widget _buildAmountSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.payments_outlined, size: 18, color: AppTheme.slateMid),
              SizedBox(width: 8),
              Text('Amount Details',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryText)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Transfer Amount (৳)',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF64748B))),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _amtCtl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                      decoration: InputDecoration(
                        hintText: '0.00',
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                        prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 0),
                        prefixIcon: const Padding(
                          padding: EdgeInsets.only(left: 14, right: 8),
                          child: Text('৳', style: TextStyle(color: Color(0xFF64748B), fontSize: 22, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Fee (৳)',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF64748B))),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _feeCtl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                      decoration: InputDecoration(
                        hintText: '0.00',
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                        prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 0),
                        prefixIcon: const Padding(
                          padding: EdgeInsets.only(left: 14, right: 8),
                          child: Text('৳', style: TextStyle(color: Color(0xFF64748B), fontSize: 22, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Note (optional)',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF64748B))),
          const SizedBox(height: 6),
          TextField(
            controller: _noteCtl,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Add a note about this handover...',
              filled: true,
              fillColor: const Color(0xFFF1F5F9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(double amtVal, double feeVal) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        border: Border.all(color: AppTheme.cardBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          _row('Base Amount:', '৳${amtVal.toStringAsFixed(2)}'),
          if (feeVal > 0) _row('Fee:', '৳${feeVal.toStringAsFixed(2)}'),
          const Divider(height: 16),
          _row('Total Handover:', '৳${(amtVal + feeVal).toStringAsFixed(2)}', bold: true),
        ],
      ),
    );
  }


  Widget _buildSubmitButton(List<Wallet> wallets) {
    return Center(
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30)),
            ),
            onPressed: _saving || _loadingCustodians || wallets.isEmpty || _custodians.isEmpty
                ? null
                : _submit,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
            label: Text(
              _saving ? 'Sending...' : 'Send Handover',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReceiptLink() {
    return Center(
      child: _lastSavedReceipt == null
          ? const Text(
              'Submit to generate your Handover Receipt',
              style: TextStyle(color: AppTheme.mutedText, fontSize: 13, fontWeight: FontWeight.w500),
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
                'Download Handover Receipt',
                style: TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
    );
  }

  Widget _banner(String t) => Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppTheme.outflowBg,
          border: Border.all(color: AppTheme.outflowBorder),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(t, style: const TextStyle(color: AppTheme.outflowText, fontWeight: FontWeight.bold)),
      );

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
            Text(value,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: bold ? FontWeight.w900 : FontWeight.bold,
                    color: bold ? AppTheme.primaryGradientFallback : Colors.black)),
          ],
        ),
      );
}

