import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:task_boss/models/models.dart';

double _toDouble(dynamic val) {
  if (val == null) return 0.0;
  if (val is num) return val.toDouble();
  if (val is String) return double.tryParse(val) ?? 0.0;
  return 0.0;
}

class AppState extends ChangeNotifier {
  String? token;
  AuthUser? user;
  double balance = 0.0;
  int pendingCount = 0;
  bool isReady = false;
  List<Wallet> wallets = [];

  final String apiBaseUrl = 'http://localhost:3000';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final storedToken = prefs.getString('@auth_token');
    final storedUserStr = prefs.getString('@auth_user');

    if (storedToken != null && storedUserStr != null) {
      try {
        final parsedUser = AuthUser.fromJson(jsonDecode(storedUserStr));
        token = storedToken;
        user = parsedUser;
        await _fetchBalanceData();
      } catch (e) {
        // failed to parse
      }
    }
    isReady = true;
    notifyListeners();
  }

  Future<void> login(String newToken, AuthUser newUser) async {
    token = newToken;
    user = newUser;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('@auth_token', newToken);
    await prefs.setString('@auth_user', jsonEncode(newUser.toJson()));
    
    await _fetchBalanceData();
    notifyListeners();
  }

  Future<void> logout() async {
    token = null;
    user = null;
    balance = 0.0;
    pendingCount = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('@auth_token');
    await prefs.remove('@auth_user');
    notifyListeners();
  }

  Future<void> refreshBalance() async {
    await _fetchBalanceData();
    notifyListeners();
  }

  Future<void> fetchWallets() async {
    if (user == null || token == null) return;
    try {
      final url = Uri.parse('$apiBaseUrl/wallets?custodianId=${user!.custodianId}');
      final resp = await http.get(url, headers: {'Authorization': 'Bearer $token'});
      if (resp.statusCode == 200) {
        final List list = jsonDecode(resp.body);
        wallets = list.map((item) => Wallet.fromJson(item)).toList();
      }
    } catch (e) {
      // offline fallback
    }
  }
  Future<void> updateWallet({
    required String walletId,
    String? name,
    String? institution,
    String? accountNumber,
    bool? isDefault,
  }) async {
    if (token == null) return;
    final url = Uri.parse('$apiBaseUrl/wallets/$walletId');
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (institution != null) body['institution'] = institution;
    if (accountNumber != null) body['accountNumber'] = accountNumber;
    if (isDefault != null) body['isDefault'] = isDefault;

    final resp = await http.patch(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      await refreshBalance();
    } else {
      final data = jsonDecode(resp.body);
      final msg = data['message'] ?? 'Failed to update wallet';
      throw Exception(msg is List ? msg.join(', ') : msg.toString());
    }
  }

  Future<void> deleteWallet(String walletId) async {
    if (token == null) return;
    final url = Uri.parse('$apiBaseUrl/wallets/$walletId');
    final resp = await http.delete(
      url,
      headers: {
        'Authorization': 'Bearer $token',
      },
    );

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      await refreshBalance();
    } else {
      final data = jsonDecode(resp.body);
      final msg = data['message'] ?? 'Failed to delete wallet';
      throw Exception(msg is List ? msg.join(', ') : msg.toString());
    }
  }

  Future<void> _fetchBalanceData() async {
    if (user == null || token == null) return;
    try {
      await fetchWallets();

      double rawBalance = 0.0;
      if (wallets.isNotEmpty) {
        rawBalance = wallets.fold(0.0, (sum, w) => sum + w.currentBalance);
      } else {
        final url = Uri.parse('$apiBaseUrl/ledger/custodians/${user!.custodianId}/balance?companyId=${user!.companyId}');
        final resp = await http.get(url, headers: {'Authorization': 'Bearer $token'});
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          final rawBal = data['balance'] ?? data['netBalance'] ?? data['currentBalance'];
          rawBalance = _toDouble(rawBal);
        }
      }
      
      final notifUrl = Uri.parse('$apiBaseUrl/custody/notifications?custodianId=${user!.custodianId}&companyId=${user!.companyId}');
      final notifResp = await http.get(notifUrl, headers: {'Authorization': 'Bearer $token'});
      double pendingDeductions = 0.0;
      if (notifResp.statusCode == 200) {
        final data = jsonDecode(notifResp.body);
        final pending = data['pendingTransfers'] as List? ?? [];
        pendingCount = pending.where((t) {
          final status = (t['status'] ?? '').toString().toLowerCase();
          final isIncoming = t['toCustodianId'] == user!.custodianId || t['to_custodian_id'] == user!.custodianId;
          return (status == 'pending') && isIncoming;
        }).length;

        for (var t in pending) {
          final status = (t['status'] ?? '').toString().toLowerCase();
          final isOutgoing = t['fromCustodianId'] == user!.custodianId || t['from_custodian_id'] == user!.custodianId;
          if (status == 'pending' && isOutgoing) {
            final amt = _toDouble(t['amount']);
            final fee = _toDouble(t['fee'] ?? t['metadata']?['fee']);
            pendingDeductions += (amt + fee);
          }
        }
      }
      balance = rawBalance - pendingDeductions;
    } catch (e) {
      // Ignore network errors offline
    }
  }
}
