class Wallet {
  final String id;
  final String custodianId;
  final String companyId;
  final String name;
  final String type; // CASH, MFS, BANK
  final String? accountNumber;
  final String? institution;
  final bool isDefault;
  final double currentBalance;

  Wallet({
    required this.id,
    required this.custodianId,
    required this.companyId,
    required this.name,
    required this.type,
    this.accountNumber,
    this.institution,
    this.isDefault = false,
    this.currentBalance = 0.0,
  });

  factory Wallet.fromJson(Map<String, dynamic> json) {
    return Wallet(
      id: json['id']?.toString() ?? '',
      custodianId: json['custodianId']?.toString() ?? '',
      companyId: json['companyId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      type: (json['type']?.toString() ?? 'CASH').toUpperCase(),
      accountNumber: json['accountNumber']?.toString(),
      institution: json['institution']?.toString(),
      isDefault: json['isDefault'] == true,
      currentBalance: (json['currentBalance'] is num)
          ? (json['currentBalance'] as num).toDouble()
          : (double.tryParse(json['currentBalance']?.toString() ?? '') ?? 0.0),
    );
  }

  String get maskedAccount {
    if (accountNumber == null || accountNumber!.isEmpty) return '';
    if (accountNumber!.length <= 4) return accountNumber!;
    return '•••• ${accountNumber!.substring(accountNumber!.length - 4)}';
  }
}