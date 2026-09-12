class PaymentRails {
  static const Map<String, Map<String, List<String>>> matrix = {
    'CASH': {
      'in': ['Physical Cash'],
      'out': ['Physical Cash'],
      'expense': ['Physical Cash'],
    },
    'MFS': {
      'in': ['Received Transfer', 'Bank to MFS', 'Cash In via Agent'],
      'out': ['Send Money', 'MFS to Bank', 'Agent Cash Out'],
      'expense': ['Merchant Payment', 'Pay Bill', 'Mobile Recharge', 'Send Money'],
    },
    'BANK': {
      'in': ['Cheque Deposit', 'Electronic Transfer (NPSB)', 'BEFTN Clearing', 'Direct Cash Deposit'],
      'out': ['NPSB Transfer', 'BEFTN Transfer', 'RTGS Transfer', 'Cheque Issued', 'Branch / ATM Withdrawal'],
      'expense': ['Corporate Card / POS', 'Direct Debit / Utility', 'Bank Charges & VAT'],
    },
  };

  static List<String> getMethods(String walletType, String flowType) {
    final typeKey = walletType.toUpperCase();
    String key = flowType.toLowerCase();
    if (key.contains('in')) {
      key = 'in';
    } else if (key.contains('out')) {
      key = 'out';
    } else if (key.contains('expense')) {
      key = 'expense';
    }

    return matrix[typeKey]?[key] ?? ['Physical Cash'];
  }
}