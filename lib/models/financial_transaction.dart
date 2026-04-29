import 'package:easy_localization/easy_localization.dart';

enum FlowType {
  FUND_BANK,
  BUY_USDT,
  SELL_USDT,
  DISTRIBUTE_VFCASH,
  COLLECT_CASH,
  COLLECT_VFCASH,
  DEPOSIT_TO_BANK,
  DEPOSIT_TO_VFCASH,
  EXPENSE_VFCASH_FEE,
  ADMIN_ADJUSTMENT,
  CREDIT_RETURN,
  CREDIT_RETURN_FEE,
  VFCASH_RETAIL_PROFIT,
  BANK_DEDUCTION,
  INTERNAL_VF_TRANSFER,
  INTERNAL_VF_TRANSFER_FEE,
  DISTRIBUTE_INSTAPAY,
  INSTAPAY_DIST_PROFIT,
  COLLECT_INSTAPAY,
  EXPENSE_INSTAPAY_FEE,
  LOAN_ISSUED,
  LOAN_REPAYMENT,
  EXPENSE_BANK,
  EXPENSE_VFNUMBER,
  EXPENSE_COLLECTOR,
  INVESTOR_CAPITAL_IN,
  INVESTOR_PROFIT_PAID,
  INVESTOR_CAPITAL_OUT,
  PARTNER_PROFIT_PAID_BANK,
  PARTNER_PROFIT_PAID_VF
}

extension FlowTypeExtension on FlowType {
  String get label {
    switch (this) {
      case FlowType.FUND_BANK: return 'fund_bank';
      case FlowType.BUY_USDT: return 'buy_usdt';
      case FlowType.SELL_USDT: return 'sell_usdt';
      case FlowType.DISTRIBUTE_VFCASH: return 'distribute_vfcash';
      case FlowType.COLLECT_CASH: return 'collect_cash';
      case FlowType.COLLECT_VFCASH: return 'collect_vfcash';
      case FlowType.DEPOSIT_TO_BANK: return 'deposit_to_bank';
      case FlowType.DEPOSIT_TO_VFCASH: return 'deposit_to_vfcash';
      case FlowType.EXPENSE_VFCASH_FEE: return 'expense_vfcash_fee';
      case FlowType.ADMIN_ADJUSTMENT: return 'admin_adjustment';
      case FlowType.CREDIT_RETURN: return 'credit_return';
      case FlowType.CREDIT_RETURN_FEE: return 'credit_return_fee';
      case FlowType.VFCASH_RETAIL_PROFIT: return 'vfcash_retail_profit';
      case FlowType.BANK_DEDUCTION: return 'bank_deduction';
      case FlowType.INTERNAL_VF_TRANSFER: return 'internal_vf_transfer';
      case FlowType.INTERNAL_VF_TRANSFER_FEE: return 'internal_vf_transfer_fee';
      case FlowType.DISTRIBUTE_INSTAPAY: return 'distribute_instapay';
      case FlowType.INSTAPAY_DIST_PROFIT: return 'instapay_dist_profit';
      case FlowType.COLLECT_INSTAPAY: return 'collect_instapay';
      case FlowType.EXPENSE_INSTAPAY_FEE: return 'expense_instapay_fee';
      case FlowType.LOAN_ISSUED: return 'loan_issued';
      case FlowType.LOAN_REPAYMENT: return 'loan_repayment';
      case FlowType.EXPENSE_BANK: return 'expense_bank';
      case FlowType.EXPENSE_VFNUMBER: return 'expense_vfnumber';
      case FlowType.EXPENSE_COLLECTOR: return 'expense_collector';
      case FlowType.INVESTOR_CAPITAL_IN: return 'investor_capital_in';
      case FlowType.INVESTOR_PROFIT_PAID: return 'investor_profit_paid';
      case FlowType.INVESTOR_CAPITAL_OUT: return 'investor_capital_out';
      case FlowType.PARTNER_PROFIT_PAID_BANK: return 'partner_profit_paid_bank';
      case FlowType.PARTNER_PROFIT_PAID_VF: return 'partner_profit_paid_vf';
    }
  }

  static FlowType fromString(String str) {
    return FlowType.values.firstWhere(
      (e) => e.toString().split('.').last == str,
      orElse: () => FlowType.ADMIN_ADJUSTMENT,
    );
  }
}

class FinancialTransaction {
  final String id;
  final FlowType type;
  final double amount;
  final double? usdtPrice;
  final double? usdtQuantity;
  final String? fromId;
  final String? fromLabel;
  final String? toId;
  final String? toLabel;
  final String? bybitOrderId;
  final String? paymentMethod;
  final String? notes;
  final String? category;
  final String createdByUid;
  final DateTime timestamp;

  FinancialTransaction({
    required this.id,
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
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
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
  }

  factory FinancialTransaction.fromMap(Map<String, dynamic> map, String id) {
    double asDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    return FinancialTransaction(
      id: map['id']?.toString() ?? id,
      type: FlowTypeExtension.fromString(map['type']?.toString() ?? ''),
      amount: asDouble(map['amount']),
      usdtPrice: (map['usdt_price'] ?? map['usdtPrice']) != null ? asDouble(map['usdt_price'] ?? map['usdtPrice']) : null,
      usdtQuantity: (map['usdt_quantity'] ?? map['usdtQuantity']) != null ? asDouble(map['usdt_quantity'] ?? map['usdtQuantity']) : null,
      fromId: map['from_id']?.toString() ?? map['fromId']?.toString(),
      fromLabel: map['from_label']?.toString() ?? map['fromLabel']?.toString(),
      toId: map['to_id']?.toString() ?? map['toId']?.toString(),
      toLabel: map['to_label']?.toString() ?? map['toLabel']?.toString(),
      bybitOrderId: map['bybit_order_id']?.toString() ?? map['bybitOrderId']?.toString(),
      paymentMethod: map['payment_method']?.toString() ?? map['paymentMethod']?.toString(),
      notes: map['notes']?.toString(),
      category: map['category']?.toString(),
      createdByUid: (map['created_by_uid'] ?? map['createdByUid'])?.toString() ?? 'system',
      timestamp: (map['timestamp'] != null)
          ? (map['timestamp'] is int 
              ? DateTime.fromMillisecondsSinceEpoch(map['timestamp']) 
              : DateTime.tryParse(map['timestamp'].toString()) ?? DateTime.now())
          : DateTime.now(),
    );
  }
}
