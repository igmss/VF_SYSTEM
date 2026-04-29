class SystemProfitSnapshot {
  final String date;
  final int workingDays;
  final double openingCapital;
  
  // V3.1 Ledger Breakdown
  final double vfNetProfit;
  final double instaNetProfit;
  final double totalNetProfit;
  final double vfNetPer1000;
  final double instaNetPer1000;
  final double totalFlow;
  
  // Daily Distribution Totals
  final double totalVfDistributed;
  final double totalInstaDistributed;
  
  // Business State / Reconciliation
  final double effectiveStartingCapital;
  final double totalOutstandingLoans;
  final double currentTotalAssets;
  final double bankBalance;
  final double vfNumberBalance;
  final double retailerDebt;
  final double retailerInstaDebt;
  final double collectorCash;
  final double usdExchangeEGP;
  final double adjustedTotalAssets;
  final double reconciledProfit;
  
  // Audit / Technical
  final double globalAvgBuyPrice;
  final double vfSpreadProfit;
  final double vfDepositProfit;
  final double vfDiscountCost;
  final double vfFeeCost;
  final double instaGrossProfit;
  final double instaFeeCost;
  final double generalExpenses;
  final double totalSellUsdt;
  final double totalSellEgp;
  final int sellEntriesCount;
  final int buyEntriesRangeCount;
  final int calculationVersion;
  final int calculatedAt;

  SystemProfitSnapshot({
    required this.date,
    required this.workingDays,
    required this.openingCapital,
    required this.vfNetProfit,
    required this.instaNetProfit,
    required this.totalNetProfit,
    required this.vfNetPer1000,
    required this.instaNetPer1000,
    required this.totalFlow,
    required this.totalVfDistributed,
    required this.totalInstaDistributed,
    required this.effectiveStartingCapital,
    required this.totalOutstandingLoans,
    required this.currentTotalAssets,
    required this.bankBalance,
    required this.vfNumberBalance,
    required this.retailerDebt,
    required this.retailerInstaDebt,
    required this.collectorCash,
    required this.usdExchangeEGP,
    required this.adjustedTotalAssets,
    required this.reconciledProfit,
    required this.globalAvgBuyPrice,
    required this.vfSpreadProfit,
    required this.vfDepositProfit,
    required this.vfDiscountCost,
    required this.vfFeeCost,
    required this.instaGrossProfit,
    required this.instaFeeCost,
    required this.generalExpenses,
    required this.totalSellUsdt,
    required this.totalSellEgp,
    required this.sellEntriesCount,
    required this.buyEntriesRangeCount,
    required this.calculationVersion,
    required this.calculatedAt,
  });

  static double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  static int _asInt(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  factory SystemProfitSnapshot.fromMap(Map<String, dynamic> map) {
    return SystemProfitSnapshot(
      date: map['date'] ?? map['date_key'] ?? '',
      workingDays: _asInt(map['workingDays'] ?? map['working_days']),
      openingCapital: _asDouble(map['openingCapital'] ?? map['opening_capital']),
      vfNetProfit: _asDouble(map['vfNetProfit'] ?? map['vf_net_profit']),
      instaNetProfit: _asDouble(map['instaNetProfit'] ?? map['insta_net_profit']),
      totalNetProfit: _asDouble(map['totalNetProfit'] ?? map['total_net_profit']),
      vfNetPer1000: _asDouble(map['vfNetPer1000'] ?? map['vf_net_per_1000']),
      instaNetPer1000: _asDouble(map['instaNetPer1000'] ?? map['insta_net_per_1000']),
      totalFlow: _asDouble(map['totalFlow'] ?? map['total_flow']),
      totalVfDistributed: _asDouble(map['totalVfDistributed'] ?? map['total_vf_distributed']),
      totalInstaDistributed: _asDouble(map['totalInstaDistributed'] ?? map['total_insta_distributed']),
      effectiveStartingCapital: _asDouble(map['effectiveStartingCapital'] ?? map['effective_starting_capital']),
      totalOutstandingLoans: _asDouble(map['totalOutstandingLoans'] ?? map['total_outstanding_loans']),
      currentTotalAssets: _asDouble(map['currentTotalAssets'] ?? map['current_total_assets']),
      bankBalance: _asDouble(map['bankBalance'] ?? map['bank_balance']),
      vfNumberBalance: _asDouble(map['vfNumberBalance'] ?? map['vf_number_balance']),
      retailerDebt: _asDouble(map['retailerDebt'] ?? map['retailer_debt']),
      retailerInstaDebt: _asDouble(map['retailerInstaDebt'] ?? map['retailer_insta_debt']),
      collectorCash: _asDouble(map['collectorCash'] ?? map['collector_cash']),
      usdExchangeEGP: _asDouble(map['usdExchangeEGP'] ?? map['usd_exchange_egp']),
      adjustedTotalAssets: _asDouble(map['adjustedTotalAssets'] ?? map['adjusted_total_assets']),
      reconciledProfit: _asDouble(map['reconciledProfit'] ?? map['reconciled_profit']),
      globalAvgBuyPrice: _asDouble(map['globalAvgBuyPrice'] ?? map['global_avg_buy_price']),
      vfSpreadProfit: _asDouble(map['vfSpreadProfit'] ?? map['vf_spread_profit']),
      vfDepositProfit: _asDouble(map['vfDepositProfit'] ?? map['vf_deposit_profit']),
      vfDiscountCost: _asDouble(map['vfDiscountCost'] ?? map['vf_discount_cost']),
      vfFeeCost: _asDouble(map['vfFeeCost'] ?? map['vf_fee_cost']),
      instaGrossProfit: _asDouble(map['instaGrossProfit'] ?? map['insta_gross_profit']),
      instaFeeCost: _asDouble(map['instaFeeCost'] ?? map['insta_fee_cost']),
      generalExpenses: _asDouble(map['generalExpenses'] ?? map['general_expenses']),
      totalSellUsdt: _asDouble(map['totalSellUsdt'] ?? map['total_sell_usdt']),
      totalSellEgp: _asDouble(map['totalSellEgp'] ?? map['total_sell_egp']),
      sellEntriesCount: _asInt(map['sellEntriesCount'] ?? map['sell_entries_count']),
      buyEntriesRangeCount: _asInt(map['buyEntriesRangeCount'] ?? map['buy_entries_range_count']),
      calculationVersion: _asInt(map['calculationVersion'] ?? map['calculation_version']),
      calculatedAt: _asInt(map['calculatedAt'] ?? map['calculated_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'date': date,
      'workingDays': workingDays,
      'openingCapital': openingCapital,
      'vfNetProfit': vfNetProfit,
      'instaNetProfit': instaNetProfit,
      'totalNetProfit': totalNetProfit,
      'vfNetPer1000': vfNetPer1000,
      'instaNetPer1000': instaNetPer1000,
      'totalFlow': totalFlow,
      'totalVfDistributed': totalVfDistributed,
      'totalInstaDistributed': totalInstaDistributed,
      'effectiveStartingCapital': effectiveStartingCapital,
      'totalOutstandingLoans': totalOutstandingLoans,
      'currentTotalAssets': currentTotalAssets,
      'bankBalance': bankBalance,
      'vfNumberBalance': vfNumberBalance,
      'retailerDebt': retailerDebt,
      'retailerInstaDebt': retailerInstaDebt,
      'collectorCash': collectorCash,
      'usdExchangeEGP': usdExchangeEGP,
      'adjustedTotalAssets': adjustedTotalAssets,
      'reconciledProfit': reconciledProfit,
      'globalAvgBuyPrice': globalAvgBuyPrice,
      'vfSpreadProfit': vfSpreadProfit,
      'vfDepositProfit': vfDepositProfit,
      'vfDiscountCost': vfDiscountCost,
      'vfFeeCost': vfFeeCost,
      'instaGrossProfit': instaGrossProfit,
      'instaFeeCost': instaFeeCost,
      'generalExpenses': generalExpenses,
      'totalSellUsdt': totalSellUsdt,
      'totalSellEgp': totalSellEgp,
      'sellEntriesCount': sellEntriesCount,
      'buyEntriesRangeCount': buyEntriesRangeCount,
      'calculationVersion': calculationVersion,
      'calculatedAt': calculatedAt,
    };
  }
}
