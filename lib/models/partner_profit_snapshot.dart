class PartnerProfitSnapshot {
  final int calculationVersion;
  final String date;
  final int workingDays;
  final double vfDailyFlow;
  final double instaDailyFlow;
  final double totalDistVf;
  final double outstandingRetailerVfDebt;
  final double effectiveVfDist;
  final double systemAvgBuyPrice;
  final double systemAvgSellPrice;
  final double systemVfProfitPer1000;
  final double systemInstaProfitPer1000;
  final double businessGrossProfit;
  final double totalFees;
  final double internalVfFees;
  final double externalVfFees;
  final double instaFees;
  final double totalInvestorProfitDeducted;
  final double businessNetProfitBeforeInvestors;
  final double businessNetProfitAfterInvestors;
  final double businessNetProfit;
  final double sharePercent;
  final double partnerProfit;
  final bool isPaid;
  final int? paidAt;
  final String? paidByUid;
  final String? paidFromType;
  final String? paidFromId;
  final int calculatedAt;

  PartnerProfitSnapshot({
    this.calculationVersion = 0,
    required this.date,
    required this.workingDays,
    required this.vfDailyFlow,
    required this.instaDailyFlow,
    this.totalDistVf = 0,
    this.outstandingRetailerVfDebt = 0,
    this.effectiveVfDist = 0,
    required this.systemAvgBuyPrice,
    required this.systemAvgSellPrice,
    required this.systemVfProfitPer1000,
    required this.systemInstaProfitPer1000,
    required this.businessGrossProfit,
    this.totalFees = 0,
    this.internalVfFees = 0,
    this.externalVfFees = 0,
    this.instaFees = 0,
    required this.totalInvestorProfitDeducted,
    required this.businessNetProfitBeforeInvestors,
    required this.businessNetProfitAfterInvestors,
    required this.businessNetProfit,
    required this.sharePercent,
    required this.partnerProfit,
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
      'vfDailyFlow': vfDailyFlow,
      'instaDailyFlow': instaDailyFlow,
      'totalDistVf': totalDistVf,
      'outstandingRetailerVfDebt': outstandingRetailerVfDebt,
      'effectiveVfDist': effectiveVfDist,
      'systemAvgBuyPrice': systemAvgBuyPrice,
      'systemAvgSellPrice': systemAvgSellPrice,
      'systemVfProfitPer1000': systemVfProfitPer1000,
      'systemInstaProfitPer1000': systemInstaProfitPer1000,
      'businessGrossProfit': businessGrossProfit,
      'totalFees': totalFees,
      'internalVfFees': internalVfFees,
      'externalVfFees': externalVfFees,
      'instaFees': instaFees,
      'totalInvestorProfitDeducted': totalInvestorProfitDeducted,
      'businessNetProfitBeforeInvestors': businessNetProfitBeforeInvestors,
      'businessNetProfitAfterInvestors': businessNetProfitAfterInvestors,
      'businessNetProfit': businessNetProfit,
      'sharePercent': sharePercent,
      'partnerProfit': partnerProfit,
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
      vfDailyFlow: asDouble(map['vfDailyFlow']),
      instaDailyFlow: asDouble(map['instaDailyFlow']),
      totalDistVf: asDouble(map['totalDistVf']),
      outstandingRetailerVfDebt: asDouble(map['outstandingRetailerVfDebt']),
      effectiveVfDist: asDouble(map['effectiveVfDist']),
      systemAvgBuyPrice: asDouble(map['systemAvgBuyPrice']),
      systemAvgSellPrice: asDouble(map['systemAvgSellPrice']),
      systemVfProfitPer1000: asDouble(map['systemVfProfitPer1000']),
      systemInstaProfitPer1000: asDouble(map['systemInstaProfitPer1000']),
      businessGrossProfit: asDouble(map['businessGrossProfit']),
      totalFees: asDouble(map['totalFees']),
      internalVfFees: asDouble(map['internalVfFees']),
      externalVfFees: asDouble(map['externalVfFees']),
      instaFees: asDouble(map['instaFees']),
      totalInvestorProfitDeducted: asDouble(map['totalInvestorProfitDeducted']),
      businessNetProfitBeforeInvestors: asDouble(map['businessNetProfitBeforeInvestors']),
      businessNetProfitAfterInvestors: asDouble(
        map['businessNetProfitAfterInvestors'] ?? map['businessNetProfit'],
      ),
      businessNetProfit: asDouble(map['businessNetProfit']),
      sharePercent: asDouble(map['sharePercent']),
      partnerProfit: asDouble(map['partnerProfit']),
      isPaid: map['isPaid'] == true,
      paidAt: map['paidAt'] != null ? asInt(map['paidAt']) : null,
      paidByUid: map['paidByUid'],
      paidFromType: map['paidFromType'],
      paidFromId: map['paidFromId'],
      calculatedAt: asInt(map['calculatedAt']),
    );
  }

  bool get isCurrentVersion => calculationVersion >= 2;
}
