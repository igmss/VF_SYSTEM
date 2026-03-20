import 'package:uuid/uuid.dart';

class BankAccount {
  final String id;
  final String bankName;
  final String accountHolder;
  final String accountNumber;
  double balance;
  final DateTime createdAt;
  final DateTime lastUpdatedAt;
  final bool isDefaultForBuy;

  BankAccount({
    String? id,
    required this.bankName,
    required this.accountHolder,
    required this.accountNumber,
    this.balance = 0.0,
    this.isDefaultForBuy = false,
    DateTime? createdAt,
    DateTime? lastUpdatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        lastUpdatedAt = lastUpdatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'bankName': bankName,
        'accountHolder': accountHolder,
        'accountNumber': accountNumber,
        'balance': balance,
        'isDefaultForBuy': isDefaultForBuy,
        'createdAt': createdAt.toIso8601String(),
        'lastUpdatedAt': lastUpdatedAt.toIso8601String(),
      };

  factory BankAccount.fromMap(Map<String, dynamic> map) {
    double asDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString().replaceAll(',', '')) ?? 0.0;
    }

    return BankAccount(
      id: map['id']?.toString() ?? const Uuid().v4(),
      bankName: map['bankName']?.toString() ?? '',
      accountHolder: map['accountHolder']?.toString() ?? '',
      accountNumber: map['accountNumber']?.toString() ?? '',
      balance: asDouble(map['balance']),
      isDefaultForBuy: map['isDefaultForBuy'] ?? false,
      createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '') ?? DateTime.now(),
      lastUpdatedAt: DateTime.tryParse(map['lastUpdatedAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  BankAccount copyWith({
    String? bankName,
    String? accountHolder,
    String? accountNumber,
    double? balance,
    DateTime? lastUpdatedAt,
  }) =>
      BankAccount(
        id: id,
        bankName: bankName ?? this.bankName,
        accountHolder: accountHolder ?? this.accountHolder,
        accountNumber: accountNumber ?? this.accountNumber,
        balance: balance ?? this.balance,
        isDefaultForBuy: this.isDefaultForBuy,
        createdAt: createdAt,
        lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      );
}
