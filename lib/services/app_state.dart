import 'dart:convert';
import 'package:flutter/foundation.dart';
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

  static const String _defaultApiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: kIsWeb ? 'http://localhost:3000' : 'http://192.168.1.45:3000',
  );

  final String apiBaseUrl = _defaultApiUrl;

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

  Future<http.Response> authRequest(
    String method,
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final Map<String, String> mergedHeaders = {
      if (token != null) 'Authorization': 'Bearer $token',
      if (headers != null) ...headers,
    };

    try {
      http.Response response;
      if (method == 'GET') {
        response = await http.get(url, headers: mergedHeaders).timeout(const Duration(seconds: 15));
      } else if (method == 'POST') {
        response = await http.post(url, headers: mergedHeaders, body: body).timeout(const Duration(seconds: 15));
      } else if (method == 'PATCH') {
        response = await http.patch(url, headers: mergedHeaders, body: body).timeout(const Duration(seconds: 15));
      } else if (method == 'DELETE') {
        response = await http.delete(url, headers: mergedHeaders, body: body).timeout(const Duration(seconds: 15));
      } else {
        throw Exception('Unsupported method');
      }

      if (response.statusCode == 401) {
        await logout();
        throw Exception('Session expired. Please log in again.');
      }

      return response;
    } on Exception catch (e) {
      if (e.toString().contains('SocketException') || e.toString().contains('ClientException') || e.toString().contains('Failed host lookup')) {
        throw Exception('Unable to reach server. Please check your internet connection.');
      }
      if (e.toString().contains('TimeoutException')) {
        throw Exception('Request timed out. Please try again.');
      }
      rethrow;
    }
  }


  Future<bool> hasSecurityPin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('@auth_pin');
  }

  Future<bool> verifySecurityPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('@auth_pin');
    final obfuscated = base64Encode(utf8.encode(pin));
    return stored == obfuscated;
  }

  Future<void> setSecurityPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final obfuscated = base64Encode(utf8.encode(pin));
    await prefs.setString('@auth_pin', obfuscated);
    notifyListeners();
  }

  Future<void> removeSecurityPin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('@auth_pin');
    await prefs.remove('@auth_pin_required');
    notifyListeners();
  }

  Future<bool> isPinRequiredForTransactions() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('@auth_pin_required') ?? false;
  }

  Future<void> setPinRequiredForTransactions(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('@auth_pin_required', value);
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
      final resp = await authRequest('GET', url);
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

    final resp = await authRequest(
      'PATCH',
      url,
      headers: {
        'Content-Type': 'application/json',
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
    final resp = await authRequest('DELETE', url);

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
        final resp = await authRequest('GET', url);
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          final rawBal = data['balance'] ?? data['netBalance'] ?? data['currentBalance'];
          rawBalance = _toDouble(rawBal);
        }
      }
      
      final notifUrl = Uri.parse('$apiBaseUrl/custody/notifications?custodianId=${user!.custodianId}&companyId=${user!.companyId}');
      final notifResp = await authRequest('GET', notifUrl);
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
