import 'dart:convert';
import 'package:flutter/foundation.dart';
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

  List<Map<String, dynamic>> _concerns = [];
  List<Map<String, dynamic>> get concerns => _concerns;

  List<Map<String, dynamic>> _managers = [];
  List<Map<String, dynamic>> get managers => _managers;

  Map<String, dynamic> _suiteSummary = {
    'totalGroupCash': 0.0,
    'concernsCount': 0,
    'managersCount': 0,
    'employeesCount': 0,
  };
  Map<String, dynamic> get suiteSummary => _suiteSummary;

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
        final uid = parsedUser.userId;
        final cachedDesignation = (uid.isNotEmpty ? prefs.getString('pref_designation_$uid') : null) ?? prefs.getString('@user_designation') ?? '';
        final cachedDepartment = (uid.isNotEmpty ? prefs.getString('pref_department_$uid') : null) ?? prefs.getString('@user_department') ?? '';

        token = storedToken;
        user = parsedUser.copyWith(
          designation: (parsedUser.designation.isNotEmpty && parsedUser.designation != 'User')
              ? parsedUser.designation
              : (cachedDesignation.isNotEmpty ? cachedDesignation : parsedUser.designation),
          department: (parsedUser.department.isNotEmpty && parsedUser.department != 'General')
              ? parsedUser.department
              : (cachedDepartment.isNotEmpty ? cachedDepartment : parsedUser.department),
        );
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
    final prefs = await SharedPreferences.getInstance();
    final uid = newUser.userId;

    final cachedDesignation = (uid.isNotEmpty ? prefs.getString('pref_designation_$uid') : null) ?? prefs.getString('@user_designation') ?? '';
    final cachedDepartment = (uid.isNotEmpty ? prefs.getString('pref_department_$uid') : null) ?? prefs.getString('@user_department') ?? '';

    final finalUser = newUser.copyWith(
      designation: (newUser.designation.isNotEmpty && newUser.designation != 'User')
          ? newUser.designation
          : (cachedDesignation.isNotEmpty ? cachedDesignation : (newUser.designation.isNotEmpty ? newUser.designation : 'User')),
      department: (newUser.department.isNotEmpty && newUser.department != 'General')
          ? newUser.department
          : (cachedDepartment.isNotEmpty ? cachedDepartment : (newUser.department.isNotEmpty ? newUser.department : 'General')),
    );

    user = finalUser;
    await prefs.setString('@auth_token', newToken);
    await prefs.setString('@auth_user', jsonEncode(finalUser.toJson()));
    if (uid.isNotEmpty) {
      await prefs.setString('pref_designation_$uid', finalUser.designation);
      await prefs.setString('pref_department_$uid', finalUser.department);
    }
    await prefs.setString('@user_designation', finalUser.designation);
    await prefs.setString('@user_department', finalUser.department);

    await _fetchBalanceData();
    notifyListeners();
  }

  Future<void> updateProfileMeta({required String designation, required String department}) async {
    if (user != null) {
      user = user!.copyWith(designation: designation, department: department);
    }
    final prefs = await SharedPreferences.getInstance();
    final uid = user?.userId ?? '';
    if (uid.isNotEmpty) {
      await prefs.setString('pref_designation_$uid', designation);
      await prefs.setString('pref_department_$uid', department);
    }
    await prefs.setString('@user_designation', designation);
    await prefs.setString('@user_department', department);
    if (user != null) {
      await prefs.setString('@auth_user', jsonEncode(user!.toJson()));
    }

    if (token != null) {
      try {
        final url = Uri.parse('$apiBaseUrl/auth/profile');
        await authRequest(
          'PATCH',
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'designation': designation,
            'department': department,
          }),
        );
      } catch (_) {
        // Fallback gracefully to local storage
      }
    }
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

  Future<void> _fetchSuiteConsolidatedBalanceData() async {
    if (user == null || token == null) return;
    try {
      final url = Uri.parse('$apiBaseUrl/suite/ledger-summary');
      final resp = await authRequest('GET', url);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        _suiteSummary = Map<String, dynamic>.from(data);
        balance = _toDouble(_suiteSummary['totalGroupCash']);
        notifyListeners();
      }
    } catch (e) {
      // offline fallback
    }
  }


  Future<void> _fetchBalanceData() async {
    if (user == null || token == null) return;
    
    // For SUITE_ADMIN, calculate consolidated tenant balance
    if (user!.role == 'SUITE_ADMIN') {
      await _fetchSuiteConsolidatedBalanceData();
      return;
    }

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

  Future<void> fetchConcerns() async {
    final resp = await authRequest('GET', Uri.parse('$apiBaseUrl/companies'));
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final List data = jsonDecode(resp.body);
      _concerns = List<Map<String, dynamic>>.from(data);
      notifyListeners();
      return;
    }
    throw Exception(jsonDecode(resp.body)['message'] ?? 'Failed to fetch concerns');
  }

  Future<void> createConcern({required String name, required String code}) async {
    final resp = await authRequest('POST', Uri.parse('$apiBaseUrl/companies'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'name': name, 'code': code}));
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      await fetchConcerns();
      return;
    }
    throw Exception(jsonDecode(resp.body)['message'] ?? 'Failed to create concern');
  }

  Future<void> updateConcern({required String id, required String name, required String code}) async {
    final resp = await authRequest('PATCH', Uri.parse('$apiBaseUrl/companies/$id'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'name': name, 'code': code}));
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      await fetchConcerns();
      return;
    }
    throw Exception(jsonDecode(resp.body)['message'] ?? 'Failed to update concern');
  }

  Future<void> deleteConcern(String id) async {
    final resp = await authRequest('DELETE', Uri.parse('$apiBaseUrl/companies/$id'));
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      await fetchConcerns();
      return;
    }
    throw Exception(jsonDecode(resp.body)['message'] ?? 'Failed to delete concern');
  }

  Future<void> fetchManagers() async {
    final resp = await authRequest('GET', Uri.parse('$apiBaseUrl/suite/managers'));
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final List data = jsonDecode(resp.body);
      _managers = List<Map<String, dynamic>>.from(data);
      notifyListeners();
      return;
    }
    throw Exception(jsonDecode(resp.body)['message'] ?? 'Failed to fetch managers');
  }

  Future<void> provisionManager({required String name, required String handlePrefix, required String password, required String designation, required List<String> companyIds}) async {
    final resp = await authRequest('POST', Uri.parse('$apiBaseUrl/suite/provision-manager'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'name': name, 'handlePrefix': handlePrefix, 'password': password, 'designation': designation, 'companyIds': companyIds}));
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      await fetchManagers();
      return;
    }
    throw Exception(jsonDecode(resp.body)['message'] ?? 'Failed to provision manager');
  }

  Future<void> updateManager({required String id, required String name, required String designation, String? newPassword, List<String>? companyIds}) async {
    final body = <String, dynamic>{'name': name, 'designation': designation};
    if (companyIds != null) body['companyIds'] = companyIds;
    if (newPassword != null && newPassword.isNotEmpty) body['password'] = newPassword;
    final resp = await authRequest('PATCH', Uri.parse('$apiBaseUrl/suite/managers/$id'), headers: {'Content-Type': 'application/json'}, body: jsonEncode(body));
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      await fetchManagers();
      return;
    }
    throw Exception(jsonDecode(resp.body)['message'] ?? 'Failed to update manager');
  }

  Future<void> deleteManager(String id) async {
    final resp = await authRequest('DELETE', Uri.parse('$apiBaseUrl/suite/managers/$id'));
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      await fetchManagers();
      return;
    }
    throw Exception(jsonDecode(resp.body)['message'] ?? 'Failed to delete manager');
  }

  Future<void> fetchSuiteSummary() async {
    final resp = await authRequest('GET', Uri.parse('$apiBaseUrl/suite/ledger-summary'));
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      _suiteSummary = Map<String, dynamic>.from(jsonDecode(resp.body));
      notifyListeners();
      return;
    }
    throw Exception(jsonDecode(resp.body)['message'] ?? 'Failed to fetch ledger summary');
  }
}
