class PartnerProfitSnapshot {
  final int calculationVersion;
  final String date;
  final int workingDays;
  
  // Ledger-Based Flow Metrics
  final double totalVfDistributed;
  final double totalInstaDistributed;
  final double vfDailyFlow;
  final double instaDailyFlow;
  final double totalDailyFlow;
  
  // Performance Breakdown (VF)
  final double vfSpreadProfit;
  final double vfDepositProfit;
  final double vfDiscountCost;
  final double vfFeeCost;
  final double vfNetProfit;
  final double vfNetPer1000;
  
  // Performance Breakdown (Insta)
  final double instaGrossProfit;
  final double instaFeeCost;
  final double instaNetProfit;
  final double instaNetPer1000;
  
  // Global Metrics
  final double generalExpenses;
  final double globalAvgBuyPrice;
  
  // Distribution Summary
  final double totalNetProfit;
  final double totalInvestorProfitDeducted;
  final double remainingForPartners;
  final double partnerProfit;
  final double sharePercent;
  
  final bool isPaid;
  final int? paidAt;
  final String? paidByUid;
  final String? paidFromType;
  final String? paidFromId;
  final int calculatedAt;

  PartnerProfitSnapshot({
    required this.calculationVersion,
    required this.date,
    required this.workingDays,
    required this.totalVfDistributed,
    required this.totalInstaDistributed,
    required this.vfDailyFlow,
    required this.instaDailyFlow,
    required this.totalDailyFlow,
    required this.vfSpreadProfit,
    required this.vfDepositProfit,
    required this.vfDiscountCost,
    required this.vfFeeCost,
    required this.vfNetProfit,
    required this.vfNetPer1000,
    required this.instaGrossProfit,
    required this.instaFeeCost,
    required this.instaNetProfit,
    required this.instaNetPer1000,
    required this.generalExpenses,
    required this.globalAvgBuyPrice,
    required this.totalNetProfit,
    required this.totalInvestorProfitDeducted,
    required this.remainingForPartners,
    required this.partnerProfit,
    required this.sharePercent,
    required this.isPaid,
    this.paidAt,
    this.paidByUid,
    this.paidFromType,
    this.paidFromId,
    required this.calculatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'calculationVersion': calculationVersion,
      'date': date,
      'workingDays': workingDays,
      'totalVfDistributed': totalVfDistributed,
      'totalInstaDistributed': totalInstaDistributed,
      'vfDailyFlow': vfDailyFlow,
      'instaDailyFlow': instaDailyFlow,
      'totalDailyFlow': totalDailyFlow,
      'vfSpreadProfit': vfSpreadProfit,
      'vfDepositProfit': vfDepositProfit,
      'vfDiscountCost': vfDiscountCost,
      'vfFeeCost': vfFeeCost,
      'vfNetProfit': vfNetProfit,
      'vfNetPer1000': vfNetPer1000,
      'instaGrossProfit': instaGrossProfit,
      'instaFeeCost': instaFeeCost,
      'instaNetProfit': instaNetProfit,
      'instaNetPer1000': instaNetPer1000,
      'generalExpenses': generalExpenses,
      'globalAvgBuyPrice': globalAvgBuyPrice,
      'totalNetProfit': totalNetProfit,
      'totalInvestorProfitDeducted': totalInvestorProfitDeducted,
      'remainingForPartners': remainingForPartners,
      'partnerProfit': partnerProfit,
      'sharePercent': sharePercent,
      'isPaid': isPaid,
      'paidAt': paidAt,
      'paidByUid': paidByUid,
      'paidFromType': paidFromType,
      'paidFromId': paidFromId,
      'calculatedAt': calculatedAt,
    };
  }

  factory PartnerProfitSnapshot.fromMap(Map<String, dynamic> map) {
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

    return PartnerProfitSnapshot(
      calculationVersion: asInt(map['calculationVersion']),
      date: map['date'] ?? '',
      workingDays: asInt(map['workingDays']),
      totalVfDistributed: asDouble(map['totalVfDistributed'] ?? map['totalDistVf']),
      totalInstaDistributed: asDouble(map['totalInstaDistributed']),
      vfDailyFlow: asDouble(map['vfDailyFlow']),
      instaDailyFlow: asDouble(map['instaDailyFlow']),
      totalDailyFlow: asDouble(map['totalDailyFlow']),
      vfSpreadProfit: asDouble(map['vfSpreadProfit']),
      vfDepositProfit: asDouble(map['vfDepositProfit']),
      vfDiscountCost: asDouble(map['vfDiscountCost']),
      vfFeeCost: asDouble(map['vfFeeCost']),
      vfNetProfit: asDouble(map['vfNetProfit']),
      vfNetPer1000: asDouble(map['vfNetPer1000']),
      instaGrossProfit: asDouble(map['instaGrossProfit']),
      instaFeeCost: asDouble(map['instaFeeCost']),
      instaNetProfit: asDouble(map['instaNetProfit']),
      instaNetPer1000: asDouble(map['instaNetPer1000']),
      generalExpenses: asDouble(map['generalExpenses']),
      globalAvgBuyPrice: asDouble(map['globalAvgBuyPrice']),
      totalNetProfit: asDouble(map['totalNetProfit'] ?? map['businessNetProfit']),
      totalInvestorProfitDeducted: asDouble(map['totalInvestorProfitDeducted'] ?? map['totalInvestorProfitDeducted']),
      remainingForPartners: asDouble(map['remainingForPartners']),
      partnerProfit: asDouble(map['partnerProfit']),
      sharePercent: asDouble(map['sharePercent']),
      isPaid: map['isPaid'] == true,
      paidAt: map['paidAt'] != null ? asInt(map['paidAt']) : null,
      paidByUid: map['paidByUid'],
      paidFromType: map['paidFromType'],
      paidFromId: map['paidFromId'],
      calculatedAt: asInt(map['calculatedAt']),
    );
  }

  bool get isCurrentVersion => calculationVersion >= 3;
}
