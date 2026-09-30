
  Future<List<dynamic>> fetchConcerns() async {
    final resp = await authRequest('GET', Uri.parse('$apiBaseUrl/companies'));
    if (resp.statusCode >= 200 && resp.statusCode < 300) return jsonDecode(resp.body) as List;
    throw Exception(jsonDecode(resp.body)['message'] ?? 'Failed to fetch concerns');
  }

  Future<void> createConcern({required String name, required String code}) async {
    final resp = await authRequest('POST', Uri.parse('$apiBaseUrl/companies'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'name': name, 'code': code}));
    if (resp.statusCode >= 200 && resp.statusCode < 300) return;
    throw Exception(jsonDecode(resp.body)['message'] ?? 'Failed to create concern');
  }

  Future<void> updateConcern({required String id, required String name, required String code}) async {
    final resp = await authRequest('PATCH', Uri.parse('$apiBaseUrl/companies/$id'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'name': name, 'code': code}));
    if (resp.statusCode >= 200 && resp.statusCode < 300) return;
    throw Exception(jsonDecode(resp.body)['message'] ?? 'Failed to update concern');
  }

  Future<void> deleteConcern(String id) async {
    final resp = await authRequest('DELETE', Uri.parse('$apiBaseUrl/companies/$id'));
    if (resp.statusCode >= 200 && resp.statusCode < 300) return;
    throw Exception(jsonDecode(resp.body)['message'] ?? 'Failed to delete concern');
  }

  Future<List<dynamic>> fetchManagers() async {
    final resp = await authRequest('GET', Uri.parse('$apiBaseUrl/suite/managers'));
    if (resp.statusCode >= 200 && resp.statusCode < 300) return jsonDecode(resp.body) as List;
    throw Exception(jsonDecode(resp.body)['message'] ?? 'Failed to fetch managers');
  }

  Future<void> provisionManager({required String name, required String handlePrefix, required String password, required String designation, required List<String> companyIds}) async {
    final resp = await authRequest('POST', Uri.parse('$apiBaseUrl/suite/provision-manager'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'name': name, 'handlePrefix': handlePrefix, 'password': password, 'designation': designation, 'companyIds': companyIds}));
    if (resp.statusCode >= 200 && resp.statusCode < 300) return;
    throw Exception(jsonDecode(resp.body)['message'] ?? 'Failed to provision manager');
  }

  Future<void> updateManager({required String id, required String name, required String designation, String? newPassword, List<String>? companyIds}) async {
    final body = <String, dynamic>{'name': name, 'designation': designation, 'companyIds': companyIds};
    if (newPassword != null && newPassword.isNotEmpty) body['password'] = newPassword;
    final resp = await authRequest('PATCH', Uri.parse('$apiBaseUrl/suite/managers/$id'), headers: {'Content-Type': 'application/json'}, body: jsonEncode(body));
    if (resp.statusCode >= 200 && resp.statusCode < 300) return;
    throw Exception(jsonDecode(resp.body)['message'] ?? 'Failed to update manager');
  }

  Future<void> deleteManager(String id) async {
    final resp = await authRequest('DELETE', Uri.parse('$apiBaseUrl/suite/managers/$id'));
    if (resp.statusCode >= 200 && resp.statusCode < 300) return;
    throw Exception(jsonDecode(resp.body)['message'] ?? 'Failed to delete manager');
  }

  Future<Map<String, dynamic>> fetchSuiteSummary() async {
    final resp = await authRequest('GET', Uri.parse('$apiBaseUrl/suite/ledger-summary'));
    if (resp.statusCode >= 200 && resp.statusCode < 300) return jsonDecode(resp.body) as Map<String, dynamic>;
    throw Exception(jsonDecode(resp.body)['message'] ?? 'Failed to fetch ledger summary');
  }
}
