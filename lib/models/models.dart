class AuthUser {
  final String userId;
  final String role;
  final String name;
  final String email;
  final String custodianId;
  final String companyId;

  AuthUser({
    required this.userId,
    required this.role,
    required this.name,
    required this.email,
    required this.custodianId,
    required this.companyId,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      userId: json['userId']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      custodianId: json['custodianId']?.toString() ?? '',
      companyId: json['companyId']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'role': role,
      'name': name,
      'email': email,
      'custodianId': custodianId,
      'companyId': companyId,
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
  });
}
