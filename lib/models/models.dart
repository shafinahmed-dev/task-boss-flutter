export 'wallet_model.dart';
export 'payment_methods.dart';

class AuthUser {
  final String userId;
  final String handle;
  final String role;
  final String name;
  final String email;
  final String custodianId;
  final String companyId;
  final String? tenantId;
  final String? primaryCompanyId;
  final String designation;
  final String department;

  AuthUser({
    required this.userId,
    required this.handle,
    required this.role,
    required this.name,
    required this.email,
    required this.custodianId,
    required this.companyId,
    this.primaryCompanyId,
    this.tenantId,
    this.designation = '',
    this.department = '',
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      userId: json['userId']?.toString() ?? json['id']?.toString() ?? '',
      handle: json['handle']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      custodianId: json['custodianId']?.toString() ?? '',
      companyId: json['companyId']?.toString() ?? '',
      primaryCompanyId: json['primaryCompanyId']?.toString() ?? json['companyId']?.toString(),
      tenantId: json['tenantId']?.toString(),
      designation: json['designation'] as String? ?? 'User',
      department: json['department'] as String? ?? 'General',
    );
  }

  AuthUser copyWith({
    String? userId,
    String? handle,
    String? role,
    String? name,
    String? email,
    String? custodianId,
    String? companyId,
    String? primaryCompanyId,
    String? tenantId,
    String? designation,
    String? department,
  }) {
    return AuthUser(
      userId: userId ?? this.userId,
      handle: handle ?? this.handle,
      role: role ?? this.role,
      name: name ?? this.name,
      email: email ?? this.email,
      custodianId: custodianId ?? this.custodianId,
      companyId: companyId ?? this.companyId,
      primaryCompanyId: primaryCompanyId ?? this.primaryCompanyId,
      tenantId: tenantId ?? this.tenantId,
      designation: designation ?? this.designation,
      department: department ?? this.department,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'handle': handle,
      'role': role,
      'name': name,
      'email': email,
      'custodianId': custodianId,
      'companyId': companyId,
      'primaryCompanyId': primaryCompanyId,
      'tenantId': tenantId,
      'designation': designation,
      'department': department,
    };
  }
}

class HistoryItem {
  final String id;
  final String type;
  final DateTime date;
  final double amount;
  final double? fee;
  final String? channel;
  final String currency;
  final String? direction;
  final String? entryTag;
  final String? receiptNo;
  final String? syncStatus;
  final String? transferStatus;
  final bool? isOutgoing;
  final String? counterpartyName;
  final String? walletId;
  final String? walletName;
  final String? paymentMethod;

  HistoryItem({
    required this.id,
    required this.type,
    required this.date,
    required this.amount,
    this.fee,
    this.channel,
    required this.currency,
    this.direction,
    this.entryTag,
    this.receiptNo,
    this.syncStatus,
    this.transferStatus,
    this.isOutgoing,
    this.counterpartyName,
    this.walletId,
    this.walletName,
    this.paymentMethod,
  });
}
