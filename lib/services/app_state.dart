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
  AuthUser? get currentUser => user;

  double balance = 0.0;
  int pendingCount = 0;
  List<Map<String, dynamic>> _pendingTransfers = [];
  List<Map<String, dynamic>> get pendingTransfers => _pendingTransfers;

  List<Map<String, dynamic>> _resolvedTransfers = [];
  List<Map<String, dynamic>> get resolvedTransfers => _resolvedTransfers;
  List<Map<String, dynamic>> _employeeTransactions = [];
  List<Map<String, dynamic>> get employeeTransactions => _employeeTransactions;
  List<Map<String, dynamic>> get transactions => _employeeTransactions;


  int get notificationCount {
    return _pendingTransfers
        .where((t) => t['isIncoming'] == true && t['status'] == 'pending')
        .length;
  }

  Future<void> initialize() async {
    await fetchPendingTransfers();
  }

  Future<void> refreshUserData() async {
    await _fetchBalanceData();
    await fetchPendingTransfers();
    notifyListeners();
  }

  Future<void> fetchPendingTransfers() async {
    try {
      final response = await authRequest('GET', Uri.parse('$apiBaseUrl/custody/transfers/pending'));
      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          if (decoded['transfers'] is List) {
            _pendingTransfers = (decoded['transfers'] as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          }
          if (decoded['resolvedTransfers'] is List) {
            _resolvedTransfers = (decoded['resolvedTransfers'] as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          }
        } else if (decoded is List) {
          _pendingTransfers = decoded
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('fetchPendingTransfers error: $e');
    }
  }

  Future<bool> acceptHandover(String transferId, {String? toWalletId}) async {
    try {
      final payload = <String, dynamic>{};
      if (toWalletId != null && toWalletId.isNotEmpty) {
        payload['toWalletId'] = toWalletId;
      }
      final response = await authRequest(
        'POST',
        Uri.parse('$apiBaseUrl/custody/transfers/$transferId/confirm'),
        headers: {'Content-Type': 'application/json'},
        body: payload.isNotEmpty ? jsonEncode(payload) : null,
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        await fetchPendingTransfers();
        await refreshUserData(); // Refreshes user balance
        if (currentUser?.role == 'MANAGER') {
          await fetchManagerOverview();
        }
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('acceptHandover error: $e');
    }
    return false;
  }

  Future<bool> cancelHandover(String transferId) async {
    try {
      final response = await authRequest(
        'POST',
        Uri.parse('$apiBaseUrl/custody/transfers/$transferId/cancel'),
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        await fetchPendingTransfers();
        await refreshUserData();
        if (currentUser?.role == 'MANAGER') {
          await fetchManagerOverview();
        }
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('cancelHandover error: $e');
    }
    return false;
  }

  Future<bool> declineHandover(String transferId) async {
    try {
      final response = await authRequest(
        'POST',
        Uri.parse('$apiBaseUrl/custody/transfers/$transferId/decline'),
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        await fetchPendingTransfers();
        await refreshUserData();
        if (currentUser?.role == 'MANAGER') {
          await fetchManagerOverview();
        }
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('declineHandover error: $e');
    }
    return false;
  }


  bool isReady = false;
  List<Wallet> wallets = [];

  String? _selectedCompanyId;
  List<Map<String, dynamic>> _suiteConcerns = [];
  List<Map<String, dynamic>> get suiteConcerns => _suiteConcerns;

  List<Map<String, dynamic>> _concerns = [];
  List<Map<String, dynamic>> get concerns => _concerns;

  List<Map<String, dynamic>> _managers = [];
  List<Map<String, dynamic>> get managers => _managers;

  Map<String, dynamic> _dashboardData = {};
  Map<String, dynamic> get dashboardData => _dashboardData;

  List<Map<String, dynamic>> _suiteEmployees = [];
  List<Map<String, dynamic>> get suiteEmployees => _suiteEmployees;
  List<Map<String, dynamic>> get managerEmployeesList => _managerConcernEmployees;
  List<Map<String, dynamic>> _suiteTransactions = [];
  bool _isSuiteLoading = false;
  bool get isSuiteLoading => _isSuiteLoading;

  List<Map<String, dynamic>> get suiteTransactions => _suiteTransactions;
  Map<String, dynamic> _suiteOverview = {};
  Map<String, dynamic> get suiteOverview => _suiteOverview;

  String? _selectedManagerCompanyId;
  String? get selectedManagerCompanyId => _selectedManagerCompanyId;
  Map<String, dynamic> _managerOverviewData = {};
  Map<String, dynamic> get managerOverviewData => _managerOverviewData;
  double get managerPersonalBalance {
    if (_managerOverviewData.containsKey('managerPersonalBalance')) {
      return _toDouble(_managerOverviewData['managerPersonalBalance']);
    }
    return balance;
  }
  double? get userBalance => balance;
  List<Map<String, dynamic>> _managerConcernEmployees = [];
  List<Map<String, dynamic>> get managerConcernEmployees => _managerConcernEmployees;

  List<Map<String, dynamic>> _concernCategories = [];
  List<Map<String, dynamic>> get concernCategories => _concernCategories;

  Future<void> fetchCategories({String? companyId, String? flowType}) async {
    final cid = companyId ?? effectiveCompanyId;
    if (cid.isEmpty) return;
    
    final url = Uri.parse('$apiBaseUrl/categories?companyId=$cid${flowType != null ? '&flowType=$flowType' : ''}');
    final resp = await authRequest('GET', url);
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final List data = jsonDecode(resp.body);
      _concernCategories = List<Map<String, dynamic>>.from(data);
      notifyListeners();
    } else {
      _errorMessage = jsonDecode(resp.body)['message'] ?? 'Failed to fetch categories';
      notifyListeners();
    }
  }

  Future<bool> updateCategory({
    required String id,
    required String name,
    required String type,
  }) async {
    try {
      final response = await authRequest(
        'PATCH',
        Uri.parse('$apiBaseUrl/manager/categories/$id'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name, 'type': type}),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        await fetchCategories(companyId: effectiveCompanyId);
        notifyListeners();
        return true;
      }
      _errorMessage = jsonDecode(response.body)['message'] ?? 'Failed to update category';
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteCategory(String id) async {
    try {
      final response = await authRequest(
        'DELETE',
        Uri.parse('$apiBaseUrl/manager/categories/$id'),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        await fetchCategories(companyId: effectiveCompanyId);
        notifyListeners();
        return true;
      }
      _errorMessage = jsonDecode(response.body)['message'] ?? 'Failed to delete category';
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  String get effectiveCompanyId {
    // 1. Explicitly selected company takes precedence
    if (_selectedCompanyId != null && _selectedCompanyId!.isNotEmpty) {
      return _selectedCompanyId!;
    }
    if (_selectedManagerCompanyId != null && _selectedManagerCompanyId!.isNotEmpty) {
      return _selectedManagerCompanyId!;
    }

    // 2. Authenticated user's companyId
    final u = user;
    if (u != null && u.companyId != null && u.companyId!.isNotEmpty) {
      return u.companyId!;
    }

    // 3. Cached company ID from manager overview
    if (_managerOverviewData['company'] is Map &&
        _managerOverviewData['company']['id'] != null) {
      return _managerOverviewData['company']['id'].toString();
    }

    // 4. First suite concern if loaded
    if (_suiteConcerns.isNotEmpty && _suiteConcerns.first['id'] != null) {
      return _suiteConcerns.first['id'].toString();
    }

    return '';
  }

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  Future<Map<String, dynamic>?> createCategory({
    required String name,
    required String type,
    String? companyId,
  }) async {
    try {
      final cid = (companyId != null && companyId.isNotEmpty)
          ? companyId
          : effectiveCompanyId;

      final response = await authRequest(
        'POST',
        Uri.parse('$apiBaseUrl/manager/categories'),
        headers: {'Content-Type': 'application/json', 'x-company-id': cid},
        body: jsonEncode({'name': name.trim(), 'type': type, 'companyId': cid}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final dynamic raw = jsonDecode(response.body);
        Map<String, dynamic> category;
        if (raw is Map && raw['category'] != null) {
          category = Map<String, dynamic>.from(raw['category']);
        } else if (raw is Map) {
          category = Map<String, dynamic>.from(raw);
        } else {
          category = {'id': '', 'name': name.trim(), 'type': type};
        }

        await fetchCategories(companyId: cid);
        return category;
      } else {
        _errorMessage = jsonDecode(response.body)?['message']?.toString() ?? 'Failed to create category';
        notifyListeners();
        return null;
      }
    } catch (e) {
      _errorMessage = e.toString();
      debugPrint('createCategory error: $e');
      notifyListeners();
      return null;
    }
  }





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
        await fetchPendingTransfers();

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

    try {
      await _fetchBalanceData();
    } catch (e) {
      await fetchPendingTransfers();

      debugPrint('Error fetching balance data on login: $e');
    }
    notifyListeners();
  }

  Future<void> logout() async {
    token = null;
    user = null;
    balance = 0.0;
    pendingCount = 0;
    isReady = true;
    wallets = [];
    _concerns = [];
    _managers = [];
    _dashboardData = {};
    _suiteEmployees = [];
    _suiteTransactions = [];
    _suiteSummary = {
      'totalGroupCash': 0.0,
      'concernsCount': 0,
      'managersCount': 0,
      'employeesCount': 0,
    };

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('@auth_token');
      await prefs.remove('@auth_user');
      await prefs.remove('token');
      await prefs.remove('auth_token');
      await prefs.remove('user');
      await prefs.remove('@auth_pin');
      await prefs.remove('@auth_pin_required');
    } catch (e) {
      debugPrint('Error clearing SharedPreferences on logout: $e');
    }

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
        final movements = data['recentMovements'] as List? ?? [];
        _employeeTransactions = movements.map((e) => Map<String, dynamic>.from(e as Map)).toList();
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

  Future<void> updateManager({
    required String id,
    required String name,
    required String designation,
    String? handlePrefix,
    String? newPassword,
    List<String>? companyIds,
  }) async {
    final body = <String, dynamic>{'name': name, 'designation': designation};
    if (companyIds != null) body['companyIds'] = companyIds;
    if (newPassword != null && newPassword.isNotEmpty) body['password'] = newPassword;
    if (handlePrefix != null && handlePrefix.isNotEmpty) body['handlePrefix'] = handlePrefix;
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

  Future<void> fetchSuiteDashboard({String period = 'month'}) async {
    if (token == null) return;
    try {
      final url = Uri.parse('$apiBaseUrl/suite/dashboard-analytics?period=$period');
      final resp = await authRequest('GET', url);
      if (resp.statusCode == 200) {
        _dashboardData = Map<String, dynamic>.from(jsonDecode(resp.body));
        if (_dashboardData['totalGroupCash'] != null) {
          balance = _toDouble(_dashboardData['totalGroupCash']);
        }
        notifyListeners();
      }
    } catch (e) {
      // offline fallback
    }
  }

  Future<void> fetchSuiteEmployees() async {
    if (token == null) return;
    try {
      final url = Uri.parse('$apiBaseUrl/suite/employees');
      final resp = await authRequest('GET', url);
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final decoded = jsonDecode(resp.body);

        if (decoded is Map && decoded['employees'] is List) {
          _suiteEmployees = (decoded['employees'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        } else if (decoded is List) {
          _suiteEmployees = decoded
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
        notifyListeners();
      }
    } catch (e) {
      // offline fallback
      debugPrint('Error fetching suite employees: $e');
    }
  }
  Future<void> fetchSuiteTransactions({String? companyId, String? range, String? search}) async {
    if (token == null) return;
    _isSuiteLoading = true;
    notifyListeners();
    try {
      final queryParams = <String, String>{};
      if (companyId != null && companyId.isNotEmpty) queryParams['companyId'] = companyId;
      if (range != null && range.isNotEmpty) queryParams['range'] = range;
      if (search != null && search.isNotEmpty) queryParams['search'] = search;
      final uri = Uri.parse('$apiBaseUrl/suite/transactions').replace(queryParameters: queryParams);
      final resp = await authRequest('GET', uri);
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final decoded = jsonDecode(resp.body);
        final List list = decoded['transactions'] ?? [];
        _suiteTransactions = list.map((item) => Map<String, dynamic>.from(item)).toList();
      }
    } catch (e) {
      debugPrint('Error fetching suite transactions: $e');
    } finally {
      _isSuiteLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchSuiteOverview({String? companyId, String? range}) async {
    if (token == null) return;
    try {
      final queryParams = <String, String>{};
      if (companyId != null) queryParams['companyId'] = companyId;
      if (range != null) queryParams['range'] = range;
      final uri = Uri.parse('$apiBaseUrl/suite/overview').replace(queryParameters: queryParams);
      final resp = await authRequest('GET', uri);
      if (resp.statusCode == 200) {
        _suiteOverview = Map<String, dynamic>.from(jsonDecode(resp.body));
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error fetching suite overview: $e');
    }
  }

  Future<void> executeInterConcernTransfer({
    required String fromWalletId,
    required String toWalletId,
    required double amount,
    String? note,
  }) async {
    final resp = await authRequest(
      'POST',
      Uri.parse('$apiBaseUrl/suite/transfer'),
      body: {
        'fromWalletId': fromWalletId,
        'toWalletId': toWalletId,
        'amount': amount,
        'note': note ?? '',
      },
    );
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      notifyListeners();
      return;
    }
    throw Exception(jsonDecode(resp.body)['message'] ?? 'Transfer failed');
  }




  Future<void> changeUserPassword({required String userId, required String newPassword}) async {
    if (token == null) return;
    final url = Uri.parse('$apiBaseUrl/suite/users/$userId/password');
    final resp = await authRequest(
      'PATCH',
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'newPassword': newPassword}),
    );
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      await fetchManagers();
      await fetchSuiteEmployees();
      await fetchSuiteDashboard();
      notifyListeners();
      return;
    }
    final data = jsonDecode(resp.body);
    final msg = data['message'] ?? 'Failed to update password';
    throw Exception(msg is List ? msg.join(', ') : msg.toString());
  }

  void selectManagerCompany(String companyId) {
    _selectedManagerCompanyId = companyId;
    fetchManagerOverview(companyId: companyId);
    notifyListeners();
  }

  Future<void> fetchManagerOverview({String? companyId, String? range}) async {
    try {
      final cid = (companyId != null && companyId.isNotEmpty)
          ? companyId
          : effectiveCompanyId;

      final queryParams = <String>[];
      if (cid.isNotEmpty) queryParams.add('companyId=$cid');
      if (range != null && range.isNotEmpty) queryParams.add('range=$range');

      final queryString = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
      final response = await authRequest('GET', Uri.parse('$apiBaseUrl/manager/overview$queryString'));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          _managerOverviewData = Map<String, dynamic>.from(decoded);
        } else if (decoded is Map) {
          _managerOverviewData = Map<String, dynamic>.from(decoded);
        }
        notifyListeners();
        await fetchPendingTransfers();
      }
    } catch (e) {
      debugPrint('fetchManagerOverview error: $e');
    }
  }

  Future<void> fetchManagerConcernEmployees({String? companyId}) async {
    final cid = companyId ?? _selectedManagerCompanyId ?? '';
    if (token == null) return;
    try {
      final url = Uri.parse('$apiBaseUrl/manager/employees?companyId=$cid');
      final resp = await authRequest('GET', url);
      if (resp.statusCode == 200) {
        final List list = jsonDecode(resp.body);
        _managerConcernEmployees = list.map((item) => Map<String, dynamic>.from(item)).toList();
        notifyListeners();
      }
    } catch (e) {}
  }

  Future<bool> provisionEmployee(Map<String, dynamic> payload) async {
    if (token == null) return false;
    final targetCompanyId = (payload['companyId'] != null && payload['companyId'].toString().isNotEmpty)
        ? payload['companyId']
        : (_selectedManagerCompanyId ?? _managerOverviewData['company']?['id'] ?? '');
    payload['companyId'] = targetCompanyId;

    try {
      final url = Uri.parse('$apiBaseUrl/manager/employees');
      final resp = await authRequest('POST', url, headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        await fetchManagerOverview();
        await fetchManagerConcernEmployees();
        notifyListeners();
        return true;
      } else {
        print('Provision employee error: ${resp.statusCode} - ${resp.body}');
      }
    } catch (e) {
      print('Provision employee exception: $e');
    }
    return false;
  }

  Future<bool> updateEmployee(String employeeId, Map<String, dynamic> payload) async {
    if (token == null) return false;
    try {
      final url = Uri.parse('$apiBaseUrl/manager/employees/$employeeId');
      final resp = await authRequest('PATCH', url, headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        await fetchManagerOverview();
        await fetchManagerConcernEmployees();
        notifyListeners();
        return true;
      } else {
        print('Update employee error: ${resp.statusCode} - ${resp.body}');
        return false;
      }
    } catch (e) {
      print('Update employee exception: $e');
      return false;
    }
  }

  List<Map<String, dynamic>> _managerTransactions = [];
  List<Map<String, dynamic>> get managerTransactionsList => _managerTransactions;
  List<Map<String, dynamic>> get managerTransactions => _managerTransactions;

  Future<void> fetchManagerTransactions({String? companyId}) async {
    try {
      final cid = (companyId != null && companyId.isNotEmpty)
          ? companyId
          : effectiveCompanyId;

      final query = cid.isNotEmpty ? '?companyId=$cid' : '';
      final url = Uri.parse('$apiBaseUrl/manager/transactions$query');
      final response = await authRequest('GET', url);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        List<dynamic> rawList = [];

        if (data is List) {
          rawList = data;
        } else if (data is Map && data['transactions'] is List) {
          rawList = data['transactions'];
        } else if (data is Map && data['data'] is List) {
          rawList = data['data'];
        }

        _managerTransactions = rawList
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();

        notifyListeners();
      }
    } catch (e) {
      debugPrint('fetchManagerTransactions error: $e');
    }
  }
}
