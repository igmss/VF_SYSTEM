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
      date: map['date'] ?? '',
      workingDays: _asInt(map['workingDays']),
      openingCapital: _asDouble(map['openingCapital']),
      vfNetProfit: _asDouble(map['vfNetProfit']),
      instaNetProfit: _asDouble(map['instaNetProfit']),
      totalNetProfit: _asDouble(map['totalNetProfit']),
      vfNetPer1000: _asDouble(map['vfNetPer1000']),
      instaNetPer1000: _asDouble(map['instaNetPer1000']),
      totalFlow: _asDouble(map['totalFlow']),
      totalVfDistributed: _asDouble(map['totalVfDistributed']),
      totalInstaDistributed: _asDouble(map['totalInstaDistributed']),
      effectiveStartingCapital: _asDouble(map['effectiveStartingCapital']),
      totalOutstandingLoans: _asDouble(map['totalOutstandingLoans']),
      currentTotalAssets: _asDouble(map['currentTotalAssets']),
      bankBalance: _asDouble(map['bankBalance']),
      vfNumberBalance: _asDouble(map['vfNumberBalance']),
      retailerDebt: _asDouble(map['retailerDebt']),
      retailerInstaDebt: _asDouble(map['retailerInstaDebt']),
      collectorCash: _asDouble(map['collectorCash']),
      usdExchangeEGP: _asDouble(map['usdExchangeEGP']),
      adjustedTotalAssets: _asDouble(map['adjustedTotalAssets']),
      reconciledProfit: _asDouble(map['reconciledProfit']),
      globalAvgBuyPrice: _asDouble(map['globalAvgBuyPrice']),
      vfSpreadProfit: _asDouble(map['vfSpreadProfit']),
      vfDepositProfit: _asDouble(map['vfDepositProfit']),
      vfDiscountCost: _asDouble(map['vfDiscountCost']),
      vfFeeCost: _asDouble(map['vfFeeCost']),
      instaGrossProfit: _asDouble(map['instaGrossProfit']),
      instaFeeCost: _asDouble(map['instaFeeCost']),
      generalExpenses: _asDouble(map['generalExpenses']),
      totalSellUsdt: _asDouble(map['totalSellUsdt']),
      totalSellEgp: _asDouble(map['totalSellEgp']),
      sellEntriesCount: _asInt(map['sellEntriesCount']),
      buyEntriesRangeCount: _asInt(map['buyEntriesRangeCount']),
      calculationVersion: _asInt(map['calculationVersion']),
      calculatedAt: _asInt(map['calculatedAt']),
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
