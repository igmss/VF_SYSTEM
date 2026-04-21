class InvestorProfitSnapshot {
  final int calculationVersion;
  final String date;
  final int workingDays;
  
  // Waterfall Hurdle Logic
  final double hurdle;
  final double precedingCapital;
  final double excess;
  final double vfExcess;
  final double instaExcess;
  
  // Flow & Performance
  final double totalFlow; // totalVf + totalInsta
  final double vfFlow;
  final double instaFlow;
  final double vfNetPer1000;
  final double instaNetPer1000;
  final double profitSharePercent;
  
  // Final Distribution
  final double vfInvestorProfit;
  final double instaInvestorProfit;
  final double investorProfit;
  
  // Business State (Audit)
  final double openingCapital;
  final double totalLoansOutstanding;
  final double currentTotalAssets;
  final double reconciledProfit;
  final double currentBankBalance;
  final double usdExchangeEGP;
  final double retailerVfDebt;
  final double collectorCash;
  final double retailerInstaDebt;
  
  // Ledger Activity / Profit Breakdown (Audit)
  final double globalAvgBuyPrice;
  final double totalNetProfit;
  final double vfNetProfit;
  final double instaNetProfit;
  
  final bool isPaid;
  final int? paidAt;
  final String? paidByUid;
  final int calculatedAt;

  InvestorProfitSnapshot({
    required this.calculationVersion,
    required this.date,
    required this.workingDays,
    required this.hurdle,
    required this.precedingCapital,
    required this.excess,
    required this.vfExcess,
    required this.instaExcess,
    required this.totalFlow,
    required this.vfFlow,
    required this.instaFlow,
    required this.vfNetPer1000,
    required this.instaNetPer1000,
    required this.profitSharePercent,
    required this.vfInvestorProfit,
    required this.instaInvestorProfit,
    required this.investorProfit,
    required this.openingCapital,
    required this.totalLoansOutstanding,
    required this.currentTotalAssets,
    required this.reconciledProfit,
    required this.currentBankBalance,
    required this.usdExchangeEGP,
    required this.retailerVfDebt,
    required this.collectorCash,
    required this.retailerInstaDebt,
    required this.globalAvgBuyPrice,
    required this.totalNetProfit,
    required this.vfNetProfit,
    required this.instaNetProfit,
    required this.isPaid,
    this.paidAt,
    this.paidByUid,
    required this.calculatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'calculationVersion': calculationVersion,
      'date': date,
      'workingDays': workingDays,
      'hurdle': hurdle,
      'precedingCapital': precedingCapital,
      'excess': excess,
      'vfExcess': vfExcess,
      'instaExcess': instaExcess,
      'totalFlow': totalFlow,
      'vfFlow': vfFlow,
      'instaFlow': instaFlow,
      'vfNetPer1000': vfNetPer1000,
      'instaNetPer1000': instaNetPer1000,
      'profitSharePercent': profitSharePercent,
      'vfInvestorProfit': vfInvestorProfit,
      'instaInvestorProfit': instaInvestorProfit,
      'investorProfit': investorProfit,
      'openingCapital': openingCapital,
      'totalLoansOutstanding': totalLoansOutstanding,
      'currentTotalAssets': currentTotalAssets,
      'reconciledProfit': reconciledProfit,
      'currentBankBalance': currentBankBalance,
      'usdExchangeEGP': usdExchangeEGP,
      'retailerVfDebt': retailerVfDebt,
      'collectorCash': collectorCash,
      'retailerInstaDebt': retailerInstaDebt,
      'globalAvgBuyPrice': globalAvgBuyPrice,
      'totalNetProfit': totalNetProfit,
      'vfNetProfit': vfNetProfit,
      'instaNetProfit': instaNetProfit,
      'isPaid': isPaid,
      'paidAt': paidAt,
      'paidByUid': paidByUid,
      'calculatedAt': calculatedAt,
    };
  }

  factory InvestorProfitSnapshot.fromMap(Map<String, dynamic> map) {
    double asDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }
    
    int asInt(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? 0;
    }

    return InvestorProfitSnapshot(
      calculationVersion: asInt(map['calculationVersion']),
      date: map['date'] ?? '',
      workingDays: asInt(map['workingDays']),
      hurdle: asDouble(map['hurdle']),
      precedingCapital: asDouble(map['precedingCapital']),
      excess: asDouble(map['excess']),
      vfExcess: asDouble(map['vfExcess']),
      instaExcess: asDouble(map['instaExcess']),
      totalFlow: asDouble(map['totalFlow']),
      vfFlow: asDouble(map['vfFlow'] ?? map['vfDailyFlow']),
      instaFlow: asDouble(map['instaFlow'] ?? map['instaDailyFlow']),
      vfNetPer1000: asDouble(map['vfNetPer1000']),
      instaNetPer1000: asDouble(map['instaNetPer1000']),
      profitSharePercent: asDouble(map['profitSharePercent']),
      vfInvestorProfit: asDouble(map['vfInvestorProfit']),
      instaInvestorProfit: asDouble(map['instaInvestorProfit']),
      investorProfit: asDouble(map['investorProfit']),
      openingCapital: asDouble(map['openingCapital']),
      totalLoansOutstanding: asDouble(map['totalLoansOutstanding']),
      currentTotalAssets: asDouble(map['currentTotalAssets'] ?? map['currentTotalCapital']),
      reconciledProfit: asDouble(map['reconciledProfit']),
      currentBankBalance: asDouble(map['currentBankBalance']),
      usdExchangeEGP: asDouble(map['usdExchangeEGP']),
      retailerVfDebt: asDouble(map['retailerVfDebt']),
      collectorCash: asDouble(map['collectorCash']),
      retailerInstaDebt: asDouble(map['retailerInstaDebt']),
      globalAvgBuyPrice: asDouble(map['globalAvgBuyPrice']),
      totalNetProfit: asDouble(map['totalNetProfit'] ?? map['totalGrossProfit']),
      vfNetProfit: asDouble(map['vfNetProfit']),
      instaNetProfit: asDouble(map['instaNetProfit']),
      isPaid: map['isPaid'] == true,
      paidAt: map['paidAt'] != null ? asInt(map['paidAt']) : null,
      paidByUid: map['paidByUid'],
      calculatedAt: asInt(map['calculatedAt']),
    );
  }

  bool get isCurrentVersion => calculationVersion >= 3;
}
