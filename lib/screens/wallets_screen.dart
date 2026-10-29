import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:task_boss/theme.dart';
import 'package:task_boss/models/models.dart';
import 'package:task_boss/services/app_state.dart';
import 'package:task_boss/screens/suite/ledger_details_screen.dart';

class WalletsScreen extends StatefulWidget {
  const WalletsScreen({super.key});
  @override
  State<WalletsScreen> createState() => _WalletsScreenState();
}

class _WalletsScreenState extends State<WalletsScreen> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final app = context.read<AppState>();
    await app.refreshBalance();
    if (mounted) setState(() => _loading = false);
  }

  IconData _getWalletIcon(String type) {
    switch (type.toUpperCase()) {
      case 'MFS': return Icons.phone_android;
      case 'BANK': return Icons.account_balance;
      case 'CASH': default: return Icons.money;
    }
  }

  Color _getWalletColor(String type) {
    switch (type.toUpperCase()) {
      case 'MFS': return const Color(0xFFE11D48);
      case 'BANK': return const Color(0xFF0284C7);
      case 'CASH': default: return const Color(0xFF16A34A);
    }
  }

  void _showCreateWalletModal(BuildContext context) {
    final nameCtl = TextEditingController();
    final instCtl = TextEditingController();
    final accCtl = TextEditingController();
    final initBalCtl = TextEditingController();
    String type = 'CASH';
    bool isDefault = false;
    bool saving = false;
    String? modalError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.canvas,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Future<void> submitCreate() async {
              setModalState(() => modalError = null);
              final name = nameCtl.text.trim();
              if (name.isEmpty) {
                setModalState(() => modalError = 'Wallet name is required');
                return;
              }
              final app = context.read<AppState>();
              setModalState(() => saving = true);
              try {
                final payload = {
                  'custodianId': app.user!.custodianId,
                  'companyId': app.user!.companyId,
                  'name': name,
                  'type': type,
                  'institution': instCtl.text.trim().isNotEmpty ? instCtl.text.trim() : null,
                  'accountNumber': accCtl.text.trim().isNotEmpty ? accCtl.text.trim() : null,
                  'initialBalance': double.tryParse(initBalCtl.text.trim()) ?? 0.0,
                  'isDefault': isDefault,
                };
                final resp = await app.authRequest('POST',
                  Uri.parse('${app.apiBaseUrl}/wallets'),
                  headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${app.token}'},
                  body: jsonEncode(payload),
                );
                if (resp.statusCode >= 200 && resp.statusCode < 300) {
                  await app.refreshBalance();
                  if (ctx.mounted) Navigator.pop(ctx);
                } else {
                  final err = jsonDecode(resp.body)['message'];
                  setModalState(() => modalError = err?.toString() ?? 'Failed to create wallet');
                }
              } catch (e) {
                setModalState(() => modalError = e.toString());
              } finally {
                setModalState(() => saving = false);
              }
            }

            return Padding(
              padding: EdgeInsets.only(top: 20, left: 20, right: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Add New Wallet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryText)),
                    if (modalError != null) Text(modalError!, style: const TextStyle(color: AppTheme.outflowText, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: ['CASH', 'MFS', 'BANK'].map((t) => Expanded(
                        child: GestureDetector(
                          onTap: () => setModalState(() => type = t),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4), padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(color: type == t ? AppTheme.primaryGradientFallback : Colors.grey[200], borderRadius: BorderRadius.circular(8)),
                            child: Text(t, textAlign: TextAlign.center, style: TextStyle(color: type == t ? Colors.white : AppTheme.secondaryText, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      )).toList(),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                        controller: nameCtl,
                        decoration: InputDecoration(
                          labelText: 'Wallet Name',
                          filled: true,
                          fillColor: const Color(0xFFF1F5F9),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        )),
                    if (type != 'CASH') ...[
                      const SizedBox(height: 10),
                      TextField(
                          controller: instCtl,
                          decoration: InputDecoration(
                            labelText: type == 'MFS' ? 'Provider (bKash/Nagad)' : 'Bank Name',
                            filled: true,
                            fillColor: const Color(0xFFF1F5F9),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          )),
                      const SizedBox(height: 10),
                      TextField(
                          controller: accCtl,
                          decoration: InputDecoration(
                            labelText: 'Account Number',
                            filled: true,
                            fillColor: const Color(0xFFF1F5F9),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          )),
                    ],
                    const SizedBox(height: 10),
                    TextField(
                        controller: initBalCtl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Initial Opening Balance (৳)',
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
                        )),
                    const SizedBox(height: 10),
                    SwitchListTile(
                        title: const Text('Set as Default Wallet'),
                        value: isDefault,
                        onChanged: (v) => setModalState(() => isDefault = v)),
                    const SizedBox(height: 12),
                    SizedBox(
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
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          ),
                          onPressed: saving ? null : submitCreate,
                          child: saving
                              ? const CircularProgressIndicator(color: Colors.white)
                              : const Text('Create Wallet',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                      ),
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
  void _showTransferModal(BuildContext context) {
    final app = context.read<AppState>();
    final wallets = app.wallets;
    if (wallets.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You need at least 2 wallets to transfer.')));
      return;
    }

    String fromId = wallets.first.id;
    String toId = wallets[1].id;
    final amtCtl = TextEditingController();
    final feeCtl = TextEditingController();
    final noteCtl = TextEditingController();
    bool saving = false;
    String? modalError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.canvas,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Future<void> submitTransfer() async {
              setModalState(() => modalError = null);
              if (fromId == toId) {
                setModalState(() => modalError = 'From and To wallets must be different');
                return;
              }
              final amt = double.tryParse(amtCtl.text.trim());
              if (amt == null || amt <= 0) {
                setModalState(() => modalError = 'Valid transfer amount is required');
                return;
              }
              setModalState(() => saving = true);
              try {
                final payload = {
                  'fromWalletId': fromId,
                  'toWalletId': toId,
                  'amount': amt,
                  'fee': double.tryParse(feeCtl.text.trim()) ?? 0.0,
                  'note': noteCtl.text.trim().isNotEmpty ? noteCtl.text.trim() : 'Internal Transfer',
                };
                final resp = await app.authRequest('POST',
                  Uri.parse('${app.apiBaseUrl}/wallets/transfer'),
                  headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${app.token}'},
                  body: jsonEncode(payload),
                );
                if (resp.statusCode >= 200 && resp.statusCode < 300) {
                  await app.refreshBalance();
                  if (ctx.mounted) Navigator.pop(ctx);
                } else {
                  final err = jsonDecode(resp.body)['message'];
                  setModalState(() => modalError = err?.toString() ?? 'Transfer failed');
                }
              } catch (e) {
                setModalState(() => modalError = e.toString());
              } finally {
                setModalState(() => saving = false);
              }
            }

            return Padding(
              padding: EdgeInsets.only(top: 20, left: 20, right: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Wallet Transfer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryText)),
                    if (modalError != null) Text(modalError!, style: const TextStyle(color: AppTheme.outflowText, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('From Wallet', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF64748B))),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: fromId,
                      items: wallets.map((w) => DropdownMenuItem(value: w.id, child: Text('${w.name} (৳${w.currentBalance.toStringAsFixed(2)})'))).toList(),
                      onChanged: (v) { if (v != null) setModalState(() => fromId = v); },
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
                    const SizedBox(height: 10),
                    const Text('To Wallet', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF64748B))),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: toId,
                      items: wallets.map((w) => DropdownMenuItem(value: w.id, child: Text('${w.name} (৳${w.currentBalance.toStringAsFixed(2)})'))).toList(),
                      onChanged: (v) { if (v != null) setModalState(() => toId = v); },
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
                    const SizedBox(height: 10),
                    const Text('Transfer Amount (৳)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF64748B))),
                    const SizedBox(height: 6),
                    TextField(controller: amtCtl, keyboardType: const TextInputType.numberWithOptions(decimal: true), 
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
                    )),
                    const SizedBox(height: 10),
                    const Text('Fee (৳, optional)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF64748B))),
                    const SizedBox(height: 6),
                    TextField(controller: feeCtl, keyboardType: const TextInputType.numberWithOptions(decimal: true), 
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
                    )),
                    const SizedBox(height: 10),
                    const Text('Note (optional)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF64748B))),
                    const SizedBox(height: 6),
                    TextField(controller: noteCtl, decoration: InputDecoration(
                        hintText: 'Add a note here...',
                        filled: true,
                        fillColor: const Color(0xFFF1F5F9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    )),
                    const SizedBox(height: 12),
                    Center(
                      child: SizedBox(
                        width: 200,
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
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            ),
                            onPressed: saving ? null : submitTransfer,
                            child: saving
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                  )
                                : const Text(
                                    'Transfer',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                      ),
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
    final app = context.watch<AppState>();
    final wallets = app.wallets;
    final totalBalance = wallets.fold(0.0, (sum, w) => sum + w.currentBalance);

    return Scaffold(
      backgroundColor: AppTheme.canvas,
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: AppTheme.slateCardGradient,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total Wallet Balance', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Text('৳${totalBalance.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('${wallets.length} Active Wallets', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white.withValues(alpha: 0.1),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  side: const BorderSide(color: Colors.white24),
                                ),
                              ),
                              onPressed: () => _showTransferModal(context),
                              icon: const Icon(Icons.swap_horiz, size: 18),
                              label: const Text('Transfer', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                
                  

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('All Wallets', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryText)),
                      TextButton.icon(
                        onPressed: () => _showCreateWalletModal(context),
                        icon: const Icon(Icons.add_circle_outline, size: 18),
                        label: const Text('Add Wallet', style: TextStyle(fontWeight: FontWeight.bold)),
                      )
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_loading && wallets.isEmpty)
                    const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
                  else
                    ...wallets.map((wallet) => _buildWalletCard(wallet)),
                    _buildAssignedLedgersSection(),
                    const SizedBox(height: 36),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }


  void _showEditWalletModal(BuildContext context, Wallet wallet) {
    final nameCtl = TextEditingController(text: wallet.name);
    final instCtl = TextEditingController(text: wallet.institution ?? '');
    final accCtl = TextEditingController(text: wallet.accountNumber ?? '');
    bool isDefault = wallet.isDefault;
    bool saving = false;
    String? modalError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.canvas,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Future<void> submitEdit() async {
              setModalState(() => modalError = null);
              final name = nameCtl.text.trim();
              if (name.isEmpty) {
                setModalState(() => modalError = 'Wallet name is required');
                return;
              }
              final app = context.read<AppState>();
              setModalState(() => saving = true);
              try {
                await app.updateWallet(
                  walletId: wallet.id,
                  name: name,
                  institution: instCtl.text.trim().isNotEmpty ? instCtl.text.trim() : null,
                  accountNumber: accCtl.text.trim().isNotEmpty ? accCtl.text.trim() : null,
                  isDefault: isDefault,
                );
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                setModalState(() {
                  saving = false;
                  modalError = e.toString().replaceAll('Exception: ', '');
                });
              }
            }

            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Edit Wallet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryText)),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                      ],
                    ),
                    if (modalError != null)
                      Container(
                        padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(color: AppTheme.outflowBg, border: Border.all(color: AppTheme.outflowBorder), borderRadius: BorderRadius.circular(8)),
                        child: Text(modalError!, style: const TextStyle(color: AppTheme.outflowText, fontSize: 13)),
                      ),
                    TextField(controller: nameCtl, decoration: InputDecoration(
                        labelText: 'Wallet Name *',
                        filled: true,
                        fillColor: const Color(0xFFF1F5F9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    )),
                    const SizedBox(height: 12),
                    TextField(controller: instCtl, decoration: InputDecoration(
                        labelText: 'Institution / Provider',
                        filled: true,
                        fillColor: const Color(0xFFF1F5F9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    )),
                    const SizedBox(height: 12),
                    TextField(controller: accCtl, decoration: InputDecoration(
                        labelText: 'Account Number',
                        filled: true,
                        fillColor: const Color(0xFFF1F5F9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    )),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      title: const Text('Set as Default Wallet'),
                      value: isDefault,
                      onChanged: (val) => setModalState(() => isDefault = val ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
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
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          ),
                          onPressed: saving ? null : submitEdit,
                          child: saving
                              ? const CircularProgressIndicator(color: Colors.white)
                              : const Text('Save Changes',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _confirmDeleteWallet(BuildContext context, Wallet wallet) {
    if (wallet.isDefault) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cannot Delete Default Wallet'),
          content: const Text('This is your primary default wallet. Set another wallet as default before deleting this one.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete / Archive ${wallet.name}'),
        content: Text(
          'Are you sure you want to delete "${wallet.name}"?\n\n'
          'Note: Wallets with historical transactions will be safely archived to preserve financial records.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppTheme.outflowText),
            onPressed: () async {
              Navigator.pop(ctx);
              final app = context.read<AppState>();
              try {
                await app.deleteWallet(wallet.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Wallet ${wallet.name} removed/archived successfully.')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  final msg = e.toString().replaceAll('Exception: ', '');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(msg), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Delete / Archive', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletCard(Wallet wallet) {
    final typeColor = _getWalletColor(wallet.type);
    final icon = _getWalletIcon(wallet.type);
    return Container(
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.cardBorder)),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: typeColor.withAlpha(30), child: Icon(icon, color: typeColor, size: 20)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(wallet.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.primaryText)),
                    if (wallet.isDefault) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: AppTheme.primaryGradientFallback.withAlpha(30), borderRadius: BorderRadius.circular(4)),
                        child: const Text('DEFAULT', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.primaryGradientFallback)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text('${wallet.type}${wallet.institution != null ? " • ${wallet.institution}" : ""}', style: const TextStyle(color: AppTheme.secondaryText, fontSize: 12)),
              ],
            ),
          ),
          Text('৳${wallet.currentBalance.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppTheme.primaryText)),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppTheme.secondaryText, size: 20),
            onSelected: (val) {
              if (val == 'edit') {
                _showEditWalletModal(context, wallet);
              } else if (val == 'delete') {
                _confirmDeleteWallet(context, wallet);
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'edit',
                child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Edit Wallet')]),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(children: [Icon(Icons.delete, size: 18, color: Colors.red), SizedBox(width: 8), Text('Delete / Archive', style: TextStyle(color: Colors.red))]),
              ),
            ],
          ),
        ],
      ),
    );
  }
  Widget _buildAssignedLedgersSection() {
    final app = context.watch<AppState>();
    final role = (app.currentUser?.role ?? '').toUpperCase();
    if (role != 'MANAGER' && role != 'SUITE_ADMIN' && role != 'SUITE') {
      return const SizedBox.shrink();
    }
    final ledgers = app.myLedgers.isNotEmpty
        ? app.myLedgers
        : [
            {
              'id': 'bd4bf36e-be9c-4bc2-b3dc-805c360b2164',
              'name': 'Barakah Condominium Project',
              'status': 'ACTIVE',
              'description': 'Our ongoing project at Priyanka Runway City',
            }
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Assigned Ledgers',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: Color(0xFF0F172A),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${ledgers.length} Active',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ...ledgers.map((ledger) {
          final name = ledger['name']?.toString() ?? 'Barakah Condominium Project';
          final status = ledger['status']?.toString().toUpperCase() ?? 'ACTIVE';

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0F172A), // Midnight Slate
                  Color(0xFF020617), // Deep Obsidian
                ],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.10),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.25),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF059669).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          status,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF34D399),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _showManageTeamModal(context, ledger),
                        icon: const Icon(Icons.group_add_outlined, size: 14, color: Colors.white),
                        label: const Text(
                          'Manage Team',
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => LedgerDetailsScreen(
                                ledgerId: ledger['id']?.toString() ?? '',
                                initialName: name,
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.12),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('View Ledger', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                            SizedBox(width: 4),
                            Icon(Icons.arrow_forward_rounded, size: 14),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  void _showManageTeamModal(BuildContext context, Map<String, dynamic> ledger) {
    final List<Map<String, String>> employees = [
      {'id': 'shafin-id', 'name': 'Shafin Ahmed', 'handle': 'shafin.taskgroup'},
      {'id': 'ayaz-id', 'name': 'Ayaz Mustaqeem', 'handle': 'ayaz.taskgroup'},
    ];

    List<String> selectedEmployeeIds = List<String>.from(ledger['assignedEmployeeIds'] ?? []);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Delegate Team: ${ledger['name'] ?? 'Ledger'}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(modalCtx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Assign employees who can record expenses and view segments in this ledger.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 16),
                  ...employees.map((emp) {
                    final empId = emp['id'] ?? '';
                    final isAssigned = selectedEmployeeIds.contains(empId);
                    return Material(
                      color: Colors.transparent,
                      child: CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(emp['name'] ?? 'Employee', style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('@${emp['handle'] ?? 'employee'}', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                        value: isAssigned,
                        activeColor: const Color(0xFF0F172A),
                        onChanged: (val) {
                          setModalState(() {
                            if (val == true) {
                              selectedEmployeeIds.add(empId);
                            } else {
                              selectedEmployeeIds.remove(empId);
                            }
                          });
                        },
                      ),
                    );
                  }),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () async {
                        final app = context.read<AppState>();
                        await app.assignEmployeesToLedger(ledger['id']?.toString() ?? '', selectedEmployeeIds);
                        setState(() {
                          ledger['assignedEmployeeIds'] = selectedEmployeeIds;
                        });
                        if (context.mounted) {
                          Navigator.pop(modalCtx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Team assignments updated successfully!'), backgroundColor: Color(0xFF059669)),
                          );
                        }
                      },
                      child: const Text('Save Assignments', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
  }