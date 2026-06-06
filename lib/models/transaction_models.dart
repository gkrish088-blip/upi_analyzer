
import 'package:flutter/material.dart';

// ─── Enums ────────────────────────────────────────────────────────────────────

enum TransactionType { debit, credit }

enum TransactionCategory {
  food,
  transport,
  shopping,
  bills,
  entertainment,
  transfer,
  other,
}

// ─── Model ────────────────────────────────────────────────────────────────────

class Transaction {
  // fields
  //required
  final String id;
  final double amount;
  final TransactionType type;
  final DateTime timestamp;
  final String rawSms;
  //optional
  final String? merchant;
  final String? upiRef;
  final String? bankAccount;
  final double? availableBalance;
  final String? source;

  //defaults
  final TransactionCategory category;
  final bool isVerified;

  // main constructor
  const Transaction({
    //required
    required this.id,
    required this.amount,
    required this.type,
    required this.timestamp,
    required this.rawSms,
    //optional
    this.merchant,
    this.upiRef,
    this.bankAccount,
    this.availableBalance,
    this.source,
    //defaults
    this.category = TransactionCategory.other,
    this.isVerified = false,
  });

  // factory: parse from raw SMS string
  factory Transaction.fromSms(String sms, String source) {
    double? amount = extractAmount(sms);
    TransactionType? type = extractTransactionType(sms);
    String? upirefString = extractupiRef(sms);
    String? accountNo = extractAccNo(sms);
    double? availableBalance = extractAvailableBal(sms);
    String? merchant = extractMerchant(sms);
    // for now return a placeholder
    return Transaction(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      amount: amount!,
      type: type!,
      timestamp: extractTimestamp(sms),
      rawSms: sms,
      upiRef: upirefString,
      bankAccount: accountNo,
      availableBalance: availableBalance,
      merchant: merchant,
    );
  }

  // factory: reconstruct from SQLite row (a Map)
  factory Transaction.fromMap(Map<String, dynamic> map) {
    return Transaction(
      id: map['id'] as String,
      amount: (map['amount'] as num).toDouble(),
      type: TransactionType.values.byName(map['type'] as String),
      category: TransactionCategory.values.byName(map['category'] as String),
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      rawSms: map['rawSms'] as String,
      merchant: map['merchant'] as String?,
      upiRef: map['upiRef'] as String?,
      bankAccount: map['bankAccount'] as String?,
      availableBalance: (map['availableBalance'] as num?)?.toDouble(),
      source: map['source'] as String?,
      isVerified: (map['isVerified'] as int) == 1,
    );
  }

  // convert to Map for SQLite storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'amount': amount,
      'type': type.name,
      'category': category.name,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'rawSms': rawSms,
      'merchant': merchant,
      'upiRef': upiRef,
      'bankAccount': bankAccount,
      'availableBalance': availableBalance,
      'source': source,
      'isVerified': isVerified ? 1 : 0,
    };
  }

  // return a copy with some fields changed
  Transaction copyWith({
    String? id,
    double? amount,
    TransactionType? type,
    String? merchant,
    String? upiRef,
    String? bankAccount,
    double? availableBalance,
    DateTime? timestamp,
    String? rawSms,
    String? source,
    TransactionCategory? category,
    bool? isVerified,
  }) {
    return Transaction(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      merchant: merchant ?? this.merchant,
      upiRef: upiRef ?? this.upiRef,
      bankAccount: bankAccount ?? this.bankAccount,
      availableBalance: availableBalance ?? this.availableBalance,
      timestamp: timestamp ?? this.timestamp,
      rawSms: rawSms ?? this.rawSms,
      source: source ?? this.source,
      category: category ?? this.category,
      isVerified: isVerified ?? this.isVerified,
    );
  }

  // ─── Getters ────────────────────────────────────────────────────────────────

  bool get isDebit => type == TransactionType.debit;

  String get formattedAmount {
    // return "₹340" for credit, "-₹340" for debit
    if (isDebit) return '-₹${amount.toStringAsFixed(0)}';
    return '₹${amount.toStringAsFixed(0)}';
  }

  String get formattedDate {
    // return "Today", "Yesterday", or "Jun 1" based on timestamp
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final txDate = DateTime(timestamp.year, timestamp.month, timestamp.day);
    if (txDate == today) return 'Today';
    if (txDate == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return '${_monthAbbr(timestamp.month)} ${timestamp.day}';
  }

  String _monthAbbr(int month) {
    switch (month) {
      case 1: return 'Jan';
      case 2: return 'Feb';
      case 3: return 'Mar';
      case 4: return 'Apr';
      case 5: return 'May';
      case 6: return 'Jun';
      case 7: return 'Jul';
      case 8: return 'Aug';
      case 9: return 'Sep';
      case 10: return 'Oct';
      case 11: return 'Nov';
      case 12: return 'Dec';
      default: return '';
    }
  }

  Color get categoryColor {
    // return color based on category enum
    // same colors we used in home_screen.dart
    switch (category) {
      case TransactionCategory.food:          return const Color(0xFF7B61FF);
      case TransactionCategory.transport:     return const Color(0xFF4CAF50);
      case TransactionCategory.shopping:      return const Color(0xFFFF9800);
      case TransactionCategory.bills:         return const Color(0xFFE91E63);
      case TransactionCategory.entertainment: return const Color(0xFF00BCD4);
      case TransactionCategory.transfer:      return const Color(0xFF2196F3);
      case TransactionCategory.other:         return const Color(0xFF888888);
    }
  }

  IconData get categoryIcon {
    // return icon based on category enum
    // same icons we used in home_screen.dart
    switch (category) {
      case TransactionCategory.food:          return Icons.restaurant_outlined;
      case TransactionCategory.transport:     return Icons.directions_bus_outlined;
      case TransactionCategory.shopping:      return Icons.shopping_bag_outlined;
      case TransactionCategory.bills:         return Icons.bolt_outlined;
      case TransactionCategory.entertainment: return Icons.movie_outlined;
      case TransactionCategory.transfer:      return Icons.swap_horiz_outlined;
      case TransactionCategory.other:         return Icons.receipt_outlined;
    }
  }
}

double? extractAmount(String sms) {
  final Map<String, String> amountPatterns = {
    "currencyBased": r'(?:Rs\.?|INR|₹)\s*([\d,]+(?:\.\d+)?)',
    "debitedBy": r"debited\s+by\s+([\d,]+(?:\.\d+)?)",
    "creditedBy": r"credited\s+by\s+([\d,]+(?:\.\d+)?)",
    "creditedWith": r"credited\s+with\s+([\d,]+(?:\.\d+)?)",
    "paymentOf": r"payment\s+of\s+(?:Rs\.?|INR|₹)?\s*([\d,]+(?:\.\d+)?)",
  };
  double? amount;

  for (final pattern in amountPatterns.values) {
    final match = RegExp(pattern, caseSensitive: false).firstMatch(sms);

    if (match != null) {
      amount = double.tryParse(match.group(1)!.replaceAll(',', ''));
      break;
    }
  }
  if (amount == null) {
    throw Exception("Could not extract amount");
  }
  return amount;
}

String? extractMerchant(String sms) {
  final Map<String, String> merchantPatterns = {
    "upiFormat": r'UPI\/\d+\/([^\/]+)\/',
    "transferTo": r'trf\s+to\s+(.+?)\s+Ref(?:No)?',
    "paidTo": r'paid.*?\sto\s+(.+?)\s+via',
    "sentTo": r'sent\s+to\s+(.+?)(?:\s+from|\s+UPI|\.)',
  };

  String? merchant;

  for (final entry in merchantPatterns.entries) {
    final patternName = entry.key;
    final pattern = entry.value;

    final match = RegExp(pattern, caseSensitive: false).firstMatch(sms);

    if (match != null) {
      merchant = match.group(1)?.trim();

      print('Merchant matched using: $patternName');
      print('Merchant: $merchant');

      break;
    }
  }

  return merchant;
}

TransactionType? extractTransactionType(String sms) {
  final lowercaseSms = sms.toLowerCase();
  TransactionType type;
  if (lowercaseSms.contains("debited") ||
      lowercaseSms.contains("paid") ||
      lowercaseSms.contains("sent")) {
    type = TransactionType.debit;
  } else {
    type = TransactionType.credit;
  }
  return type;
}

String? extractupiRef(String sms) {
  final upiRefRegrex = RegExp(
    r'(?:UPI\s*Ref(?:No)?|Ref\s*[Nn]o|Txn\s*ID|Transaction\s*ID|Refno)\s*:?\s*(\d{10,16})',
    caseSensitive: false,
  );
  final upiRefmatch = upiRefRegrex.firstMatch(sms);
  final upiRefString = upiRefmatch?.group(1);
  return upiRefString;
}

String? extractAccNo(String sms) {
  final accountregrex = RegExp(
    r'(?:A\/c|Acct)\s*([A-ZX]*\d{3,})',
    caseSensitive: false,
  );
  final accountmatch = accountregrex.firstMatch(sms);
  final accountString = accountmatch?.group(1);
  return accountString;
}

double? extractAvailableBal(String sms) {
  double? availableBalance;
  final Map<String, String> balancePatterns = {
    "AvialableBalance":
        r"Available\s+Balance\s*:?\s*(?:Rs\.?|INR|₹)?\s*([\d,]+(?:\.\d+)?)",
    "AvlBal": r"Avl\s+Bal\s*:?\s*(?:Rs\.?|INR|₹)?\s*([\d,]+(?:\.\d+)?)",
    "Bal": r"Bal\s*:?\s*(?:Rs\.?|INR|₹)?\s*([\d,]+(?:\.\d+)?)",
    "accountBalance":
        r"A\/c\s+balance\s+(?:is\s+)?(?:Rs\.?|INR|₹)?\s*([\d,]+(?:\.\d+)?)",
  };

  for (final pattern in balancePatterns.values) {
    final match = RegExp(pattern, caseSensitive: false).firstMatch(sms);

    if (match != null) {
      availableBalance = double.tryParse(match.group(1)!.replaceAll(',', ''));
      break;
    }
  }
  return availableBalance;
}

DateTime extractTimestamp(String sms) {
  // Pattern 1: DD/MM/YYYY at HH:MM AM/PM
  // Example: "paid on 26/04/2026 at 10:38 PM"
  final p1 = RegExp(
    r'(\d{1,2})/(\d{1,2})/(\d{4})\s+at\s+(\d{1,2}):(\d{2})\s*(AM|PM)',
    caseSensitive: false,
  );
  final m1 = p1.firstMatch(sms);
  if (m1 != null) {
    int hour = int.parse(m1.group(4)!);
    final minute = int.parse(m1.group(5)!);
    final isPm = m1.group(6)!.toUpperCase() == 'PM';
    if (isPm && hour != 12) hour += 12;
    if (!isPm && hour == 12) hour = 0;
    return DateTime(
      int.parse(m1.group(3)!),
      int.parse(m1.group(2)!),
      int.parse(m1.group(1)!),
      hour,
      minute,
    );
  }

  // Pattern 2: DD-MM-YYYY HH:MM (24hr)
  // Example: "on 27-04-2026 17:13"
  final p2 = RegExp(
    r'(\d{1,2})-(\d{1,2})-(\d{4})\s+(\d{1,2}):(\d{2})',
  );
  final m2 = p2.firstMatch(sms);
  if (m2 != null) {
    return DateTime(
      int.parse(m2.group(3)!),
      int.parse(m2.group(2)!),
      int.parse(m2.group(1)!),
      int.parse(m2.group(4)!),
      int.parse(m2.group(5)!),
    );
  }

  // Pattern 3: DD/MM/YY HH:MM (24hr, 2-digit year)
  // Example: "on 26/04/26 10:38"
  final p3 = RegExp(
    r'(\d{1,2})/(\d{1,2})/(\d{2})\s+(\d{1,2}):(\d{2})',
  );
  final m3 = p3.firstMatch(sms);
  if (m3 != null) {
    return DateTime(
      2000 + int.parse(m3.group(3)!),
      int.parse(m3.group(2)!),
      int.parse(m3.group(1)!),
      int.parse(m3.group(4)!),
      int.parse(m3.group(5)!),
    );
  }

  // Pattern 4: DD-MMM-YYYY HH:MM
  // Example: "on 26-Apr-2026 10:38"
  final p4 = RegExp(
    r'(\d{1,2})-(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)-(\d{4})\s+(\d{1,2}):(\d{2})',
    caseSensitive: false,
  );
  final m4 = p4.firstMatch(sms);
  if (m4 != null) {
    const months = ['jan','feb','mar','apr','may','jun',
                    'jul','aug','sep','oct','nov','dec'];
    final month = months.indexOf(m4.group(2)!.toLowerCase()) + 1;
    return DateTime(
      int.parse(m4.group(3)!),
      month,
      int.parse(m4.group(1)!),
      int.parse(m4.group(4)!),
      int.parse(m4.group(5)!),
    );
  }

  // Pattern 5: DD-MMM-YY (date only, no time)
  // Example: "on 06-Jun-26"
  final p5 = RegExp(
    r'(\d{1,2})-(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)-(\d{2})',
    caseSensitive: false,
  );
  final m5 = p5.firstMatch(sms);
  if (m5 != null) {
    const months = ['jan','feb','mar','apr','may','jun',
                    'jul','aug','sep','oct','nov','dec'];
    final month = months.indexOf(m5.group(2)!.toLowerCase()) + 1;
    return DateTime(
      2000 + int.parse(m5.group(3)!),
      month,
      int.parse(m5.group(1)!),
    );
  }

  // Pattern 6: YYYY-MM-DD HH:MM (ISO-like format)
  // Example: "2026-04-27 17:13"
  final p6 = RegExp(
    r'(\d{4})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2})',
  );
  final m6 = p6.firstMatch(sms);
  if (m6 != null) {
    return DateTime(
      int.parse(m6.group(1)!),
      int.parse(m6.group(2)!),
      int.parse(m6.group(3)!),
      int.parse(m6.group(4)!),
      int.parse(m6.group(5)!),
    );
  }

  // Pattern 7: DD/MM/YYYY with no time
  // Example: "on 26/04/2026"
  final p7 = RegExp(r'(\d{1,2})/(\d{1,2})/(\d{4})');
  final m7 = p7.firstMatch(sms);
  if (m7 != null) {
    return DateTime(
      int.parse(m7.group(3)!),
      int.parse(m7.group(2)!),
      int.parse(m7.group(1)!),
    );
  }

  // Pattern 8: SBI format DDMmmYY (no separators)
  // Example: "27Mar26", "03Apr26"
  final p8 = RegExp(
    r'(\d{1,2})(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)(\d{2})',
    caseSensitive: false,
  );
  final m8 = p8.firstMatch(sms);
  if (m8 != null) {
    const months = ['jan','feb','mar','apr','may','jun',
                    'jul','aug','sep','oct','nov','dec'];
    final month = months.indexOf(m8.group(2)!.toLowerCase()) + 1;
    return DateTime(
      2000 + int.parse(m8.group(3)!),
      month,
      int.parse(m8.group(1)!),
    );
  }

  // Fallback: no recognizable date found
  // Use DateTime.now() — deduplication still works via
  // upiRef or amount+account fingerprint
  print('🕐 No pattern matched for: ${sms.substring(0, sms.length > 50 ? 50 : sms.length)}');
  return DateTime.now();
}
