import 'package:uuid/uuid.dart';

/// The type of a financial ledger entry in the system.
enum FlowType {
  /// Fiat deposited directly into a Bank Account (opening capital)
  FUND_BANK,

  /// Bought USDT on Bybit P2P — fiat left Bank, USDT entered Bybit (side == 0)
  BUY_USDT,

  /// Sold USDT on Bybit P2P — USDT left Bybit, EGP entered VF Cash number (side == 1)
  SELL_USDT,

  /// VF Cash transferred to a Retailer — VF Cash balance decreased, Retailer debt increased
  DISTRIBUTE_VFCASH,

  /// Collector collected cash from a Retailer — Retailer debt decreased, Collector cashOnHand increased
  COLLECT_CASH,

  /// Collector deposited cash into a Bank Account — Collector cashOnHand decreased, Bank balance increased
  DEPOSIT_TO_BANK,

  /// Collector deposited cash into the default Vodafone number — Collector cashOnHand decreased, VF balance increased
  DEPOSIT_TO_VFCASH,

  /// Vodafone Cash tracking transfer fee deducted during distribution
  EXPENSE_VFCASH_FEE,

  /// Admin manual correction of a previous transaction
  ADMIN_ADJUSTMENT,
  
  /// Retailer paid debt via VF Cash — VF Cash balance increased, Retailer debt decreased
  CREDIT_RETURN,
  
  /// Fee collected during a Credit Return transaction
  CREDIT_RETURN_FEE,

  /// Profit retained on Vodafone retail operations
  VFCASH_RETAIL_PROFIT,

  /// Manual deduction from a bank account (e.g. balance correction for a missed BUY_USDT deduction)
  BANK_DEDUCTION,

  /// Internal transfer of Vodafone Cash from one number to another
  INTERNAL_VF_TRANSFER,

  /// Fee deducted for an internal Vodafone Cash transfer
  INTERNAL_VF_TRANSFER_FEE,

  /// InstaPay cash sent to retailer; InstaPay debt increases
  DISTRIBUTE_INSTAPAY,

  /// Profit margin entry recorded alongside each distribution
  INSTAPAY_DIST_PROFIT,

  /// Cash collected from retailer against InstaPay debt
  COLLECT_INSTAPAY_CASH,
  
  /// InstaPay transfer fee deducted from bank during distribution
  EXPENSE_INSTAPAY_FEE,

  /// Loan issued from bank or collector to a borrower
  LOAN_ISSUED,

  /// Loan repayment received from a borrower
  LOAN_REPAYMENT,

  /// General expense paid from a bank account
  EXPENSE_BANK,

  /// General expense paid from a VF number balance
  EXPENSE_VFNUMBER,

  /// General expense paid from collector cash
  EXPENSE_COLLECTOR,
}

extension FlowTypeExtension on FlowType {
  String get label {
    switch (this) {
      case FlowType.FUND_BANK:       return 'fund_bank';
      case FlowType.BUY_USDT:        return 'buy_usdt';
      case FlowType.SELL_USDT:       return 'sell_usdt';
      case FlowType.DISTRIBUTE_VFCASH: return 'distribute_vfcash_action';
      case FlowType.COLLECT_CASH:    return 'collect_cash';
      case FlowType.DEPOSIT_TO_BANK: return 'deposit_to_bank_action';
      case FlowType.DEPOSIT_TO_VFCASH: return 'deposit_to_vfcash_action';
      case FlowType.EXPENSE_VFCASH_FEE: return 'expense_vfcash_fee';
      case FlowType.ADMIN_ADJUSTMENT:   return 'admin_adjustment';
      case FlowType.CREDIT_RETURN:      return 'credit_return';
      case FlowType.CREDIT_RETURN_FEE:  return 'credit_return_fee';
      case FlowType.VFCASH_RETAIL_PROFIT: return 'vfcash_retail_profit';
      case FlowType.BANK_DEDUCTION:     return 'bank_deduction';
      case FlowType.INTERNAL_VF_TRANSFER: return 'internal_vf_transfer';
      case FlowType.INTERNAL_VF_TRANSFER_FEE: return 'internal_vf_transfer_fee';
      case FlowType.DISTRIBUTE_INSTAPAY: return 'distribute_instapay';
      case FlowType.INSTAPAY_DIST_PROFIT: return 'instapay_dist_profit';
      case FlowType.COLLECT_INSTAPAY_CASH: return 'collect_instapay_cash';
      case FlowType.EXPENSE_INSTAPAY_FEE: return 'expense_instapay_fee';
      case FlowType.LOAN_ISSUED:        return 'loan_issued';
      case FlowType.LOAN_REPAYMENT:     return 'loan_repayment';
      case FlowType.EXPENSE_BANK:       return 'expense_bank';
      case FlowType.EXPENSE_VFNUMBER:   return 'expense_vfnumber';
      case FlowType.EXPENSE_COLLECTOR:  return 'expense_collector';
    }
  }

  static FlowType fromString(String s) {
    return FlowType.values.firstWhere(
      (f) => f.toString().split('.').last == s || f.label == s,
      orElse: () => FlowType.FUND_BANK,
    );
  }
}

class FinancialTransaction {
  final String id;
  final FlowType type;

  /// Amount in EGP (or USDT quantity for BUY/SELL)
  final double amount;

  /// EGP price per USDT (only relevant for BUY_USDT / SELL_USDT)
  final double? usdtPrice;

  /// USDT quantity (only relevant for BUY_USDT / SELL_USDT)
  final double? usdtQuantity;

  /// Source entity id (e.g. bankAccountId, vfNumberId, retailerId, collectorId)
  final String? fromId;
  final String? fromLabel;

  /// Destination entity id
  final String? toId;
  final String? toLabel;

  /// Bybit order ID if sourced from Bybit sync
  final String? bybitOrderId;

  /// Bybit payment method / account info (e.g. bank name + account number)
  final String? paymentMethod;

  final String? notes;
  final String? category;
  final String createdByUid;
  final DateTime timestamp;

  FinancialTransaction({
    String? id,
    required this.type,
    required this.amount,
    this.usdtPrice,
    this.usdtQuantity,
    this.fromId,
    this.fromLabel,
    this.toId,
    this.toLabel,
    this.bybitOrderId,
    this.paymentMethod,
    this.notes,
    this.category,
    required this.createdByUid,
    DateTime? timestamp,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.toString().split('.').last,
        'amount': amount,
        if (usdtPrice != null) 'usdtPrice': usdtPrice,
        if (usdtQuantity != null) 'usdtQuantity': usdtQuantity,
        if (fromId != null) 'fromId': fromId,
        if (fromLabel != null) 'fromLabel': fromLabel,
        if (toId != null) 'toId': toId,
        if (toLabel != null) 'toLabel': toLabel,
        if (bybitOrderId != null) 'bybitOrderId': bybitOrderId,
        if (paymentMethod != null) 'paymentMethod': paymentMethod,
        if (notes != null) 'notes': notes,
        if (category != null) 'category': category,
        'createdByUid': createdByUid,
        'timestamp': timestamp.millisecondsSinceEpoch,
      };

  factory FinancialTransaction.fromMap(Map<String, dynamic> map) {
    double asDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    final ts = map['timestamp'];
    DateTime time;
    if (ts is int) {
      time = DateTime.fromMillisecondsSinceEpoch(ts);
    } else {
      time = DateTime.tryParse(ts?.toString() ?? '') ?? DateTime.now();
    }

    return FinancialTransaction(
      id: map['id']?.toString() ?? const Uuid().v4(),
      type: FlowTypeExtension.fromString(map['type']?.toString() ?? 'FUND_BANK'),
      amount: asDouble(map['amount']),
      usdtPrice: map['usdtPrice'] != null ? asDouble(map['usdtPrice']) : null,
      usdtQuantity: map['usdtQuantity'] != null ? asDouble(map['usdtQuantity']) : null,
      fromId: map['fromId']?.toString(),
      fromLabel: map['fromLabel']?.toString(),
      toId: map['toId']?.toString(),
      toLabel: map['toLabel']?.toString(),
      bybitOrderId: map['bybitOrderId']?.toString(),
      paymentMethod: map['paymentMethod']?.toString(),
      notes: map['notes']?.toString(),
      category: map['category']?.toString(),
      createdByUid: map['createdByUid']?.toString() ?? 'system',
      timestamp: time,
    );
  }
}
