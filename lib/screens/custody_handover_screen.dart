import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:task_boss/theme.dart';
import 'package:task_boss/services/app_state.dart';
import 'package:task_boss/models/models.dart';
import 'package:task_boss/utils/show_receipt_modal.dart';

class CustodyHandoverScreen extends StatefulWidget {
  const CustodyHandoverScreen({super.key});

  @override
  State<CustodyHandoverScreen> createState() => _HandoverState();
}

class _HandoverState extends State<CustodyHandoverScreen> {
  final _amountCtl = TextEditingController();
  final _chargeCtl = TextEditingController();
  final _noteCtl = TextEditingController();
  
  Wallet? _selectedWallet;
  String? _selectedPaymentMethod;

  bool _saving = false;
  List<dynamic> _recipients = [];
  String? _recipient;
  String? _error;
  String? _success;
  Map<String, dynamic>? _lastSavedReceipt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final app = context.read<AppState>();
      await app.fetchWallets();
      if (mounted) {
        setState(() {
          if (app.wallets.isNotEmpty) {
            _selectedWallet = app.wallets.firstWhere((w) => w.isDefault, orElse: () => app.wallets.first);
            final rails = PaymentRails.getMethods(_selectedWallet!.type, 'out');
            _selectedPaymentMethod = rails.isNotEmpty ? rails.first : 'Physical Cash';
          }
        });
        _fetchRec();
      }
    });
  }

  Future<void> _fetchRec() async {
    final app = context.read<AppState>();
    if (app.user == null) return;
    try {
      final url = Uri.parse('${app.apiBaseUrl}/custody/custodians?companyId=${app.user!.companyId}');
      final res = await http.get(url, headers: {
        'Authorization': 'Bearer ${app.token}',
        'x-company-id': app.user!.companyId,
      });
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List;
        setState(() {
          _recipients = list.where((c) => c['id'] != app.user!.custodianId).toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _submit() async {
    setState(() { _error = null; _success = null; });
    final amt = double.tryParse(_amountCtl.text.trim());
    if (amt == null || amt <= 0) {
      setState(() => _error = 'Please enter a valid amount greater than 0.');
      return;
    }
    if (_recipient == null || _recipient!.isEmpty) {
      setState(() => _error = 'Please select a receiver custodian.');
      return;
    }
    final feeText = _chargeCtl.text.trim();
    final feeVal = feeText.isEmpty ? 0.0 : (double.tryParse(feeText) ?? -1.0);
    if (feeVal < 0) {
      setState(() => _error = 'Please enter a valid charge amount (0 or greater).');
      return;
    }

    final app = context.read<AppState>();
    final available = _selectedWallet?.currentBalance ?? app.balance;
    final totalDeducted = amt + feeVal;
    if (totalDeducted > available) {
      setState(() => _error = 'Total deducted (৳${totalDeducted.toStringAsFixed(2)}) exceeds selected wallet balance (৳${available.toStringAsFixed(2)}).');
      return;
    }

    final noteText = _noteCtl.text.trim();
    final paymentRail = _selectedPaymentMethod ?? 'Physical Cash';
    setState(() => _saving = true);
    try {
      final payload = {
        'companyId': app.user!.companyId,
        'idempotencyKey': const Uuid().v4(),
        'fromCustodianId': app.user!.custodianId,
        'toCustodianId': _recipient,
        'fromWalletId': _selectedWallet?.id,
        'walletId': _selectedWallet?.id,
        'amount': amt,
        'fee': feeVal,
        'channel': paymentRail,
        'paymentMethod': paymentRail,
        'notes': noteText.isNotEmpty ? noteText : null,
        'note': noteText.isNotEmpty ? noteText : null,
        'description': noteText.isNotEmpty ? noteText : null,
        'metadata': {
          'baseAmount': amt,
          'fee': feeVal,
          'channel': paymentRail,
          'paymentMethod': paymentRail,
          'fromWalletId': _selectedWallet?.id,
          'walletId': _selectedWallet?.id,
          'walletName': _selectedWallet?.name,
          'category': 'Handover Transfer',
          'note': noteText,
          'notes': noteText,
        },
      };

      final res = await http.post(
        Uri.parse('${app.apiBaseUrl}/custody/transfers'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${app.token}',
          'x-company-id': app.user!.companyId,
        },
        body: jsonEncode(payload),
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final resData = jsonDecode(res.body);
        final receiptNo = resData['receiptNo'] ?? resData['metadata']?['voucherNumber'] ?? 'HND-${const Uuid().v4().substring(0, 8).toUpperCase()}';
        
        final recipientObj = _recipients.firstWhere((c) => c['id'] == _recipient, orElse: () => null);
        final recipientName = recipientObj != null ? (recipientObj['name'] ?? 'Recipient') : 'Recipient';

        setState(() {
          _lastSavedReceipt = {
            'receiptNo': receiptNo,
            'date': DateTime.now(),
            'type': 'Handover Transfer',
            'category': recipientName,
            'wallet': _selectedWallet?.name ?? 'Wallet',
            'method': paymentRail,
            'note': noteText,
            'amount': amt,
            'fee': feeVal,
          };
          _amountCtl.clear();
          _chargeCtl.clear();
          _noteCtl.clear();
          _recipient = null;
          _success = 'Handover of ৳${amt.toStringAsFixed(2)}${feeVal > 0 ? ' (+ ৳${feeVal.toStringAsFixed(2)} fee)' : ''} submitted! Receiver must confirm.';
        });
        await app.refreshBalance();
      } else {
        final err = jsonDecode(res.body);
        final msg = err['message'] ?? err['error'];
        throw Exception(msg is List ? msg.join(', ') : (msg?.toString() ?? 'Handover failed (HTTP ${res.statusCode})'));
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
    final amtVal = double.tryParse(_amountCtl.text.trim()) ?? 0.0;
    final feeVal = double.tryParse(_chargeCtl.text.trim()) ?? 0.0;
    final totalVal = amtVal + feeVal;

    return Scaffold(
      backgroundColor: AppTheme.canvas,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Transfer Funds', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryGradientFallback)),
            const SizedBox(height: 12),
            if (_error != null) _banner(_error!, AppTheme.expenseBg, AppTheme.expenseBorder, AppTheme.expenseText),
            if (_success != null) _banner(_success!, AppTheme.confirmedBg, AppTheme.confirmedBorder, AppTheme.confirmedText),

            // Symmetrical 2x2 Layout - Row 1: Wallet & Recipient Custodian
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Wallet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<Wallet>(
                        initialValue: app.wallets.contains(_selectedWallet) ? _selectedWallet : (app.wallets.isNotEmpty ? app.wallets.first : null),
                        decoration: _inputDec('Select Wallet'),
                        items: app.wallets.map((w) {
                          return DropdownMenuItem<Wallet>(
                            value: w,
                            child: Text('${w.name} (৳${w.currentBalance.toStringAsFixed(0)})', overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          );
                        }).toList(),
                        onChanged: (w) {
                          if (w == null) return;
                          setState(() {
                            _selectedWallet = w;
                            final rails = PaymentRails.getMethods(w.type, 'out');
                            _selectedPaymentMethod = rails.contains(_selectedPaymentMethod)
                                ? _selectedPaymentMethod
                                : (rails.isNotEmpty ? rails.first : 'Physical Cash');
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Recipient Custodian', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: _recipient,
                        decoration: _inputDec('Select...'),
                        items: _recipients.map((c) => DropdownMenuItem(value: c['id'] as String, child: Text(c['name'] ?? 'Unknown', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)))).toList(),
                        onChanged: (v) => setState(() => _recipient = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Symmetrical 2x2 Layout - Row 2: Amount & Fee
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Amount', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      TextField(controller: _amountCtl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: _inputDec('0.00'), onChanged: (_) => setState(() {})),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Fee', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      TextField(controller: _chargeCtl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: _inputDec('0.00'), onChanged: (_) => setState(() {})),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            const Text('Method', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            Builder(
              builder: (context) {
                final walletType = _selectedWallet?.type ?? 'CASH';
                final rails = PaymentRails.getMethods(walletType, 'out');
                final currentMethod = (rails.contains(_selectedPaymentMethod))
                    ? _selectedPaymentMethod
                    : (rails.isNotEmpty ? rails.first : 'Physical Cash');

                return DropdownButtonFormField<String>(
                  initialValue: currentMethod,
                  decoration: _inputDec('Select Method'),
                  items: rails.map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 12)))).toList(),
                  onChanged: (v) {
                    setState(() => _selectedPaymentMethod = v);
                  },
                );
              },
            ),
            const SizedBox(height: 16),

            const Text('Note', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            TextField(
              controller: _noteCtl,
              maxLines: 2,
              decoration: _inputDec('e.g. Daily cash collection handover'),
            ),
            const SizedBox(height: 16),

            if (amtVal > 0 || feeVal > 0) Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppTheme.cardBg, border: Border.all(color: AppTheme.cardBorder), borderRadius: BorderRadius.circular(10)),
              child: Column(children: [
                _impactRow('Base Handover Amount:', '৳${amtVal.toStringAsFixed(2)}'),
                if (feeVal > 0) _impactRow('Transfer Fee (Expense):', '৳${feeVal.toStringAsFixed(2)}'),
                const Divider(),
                _impactRow('Total Balance Deduction:', '৳${totalVal.toStringAsFixed(2)}', bold: true),
              ]),
            ),
            const SizedBox(height: 20),

            Center(
              child: SizedBox(
                width: 280,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryGradientFallback,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Send', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Inline Receipt Status Container
            Center(
              child: _lastSavedReceipt == null
                  ? const Text(
                      'Hit Send to Generate Receipt',
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

  Widget _banner(String t, Color bg, Color border, Color text) => Container(
    padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(10)),
    child: Text(t, style: TextStyle(color: text, fontWeight: FontWeight.bold, fontSize: 13)),
  );

  InputDecoration _inputDec(String h) => InputDecoration(
    hintText: h, filled: true, fillColor: AppTheme.inputBg, border: const OutlineInputBorder(),
  );

  Widget _impactRow(String l, String v, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(l, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
      Text(v, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w900 : FontWeight.bold, color: bold ? AppTheme.primaryGradientFallback : Colors.black)),
    ]),
  );
}
