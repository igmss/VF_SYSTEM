class InvestorProfitSnapshot {
  final int calculationVersion;
  final String date;
  final int workingDays;
  final double openingCapital;
  final double totalLoansOutstanding;
  final double currentTotalCapital;
  final double capitalShortfall;
  final double totalVfCollected;
  final double totalInstaCollected;
  final double currentBankBalance;
  final double usdExchangeEGP;
  final double retailerVfDebt;
  final double collectorCash;
  final double retailerInstaDebt;
  final double vfRawFlow;
  final double instaRawFlow;
  final double vfDailyFlow;
  final double instaDailyFlow;
  final double totalDailyFlow;
  final double halfCumulativeCapital;
  final double eligibleTotal;
  final double vfShare;
  final double instaShare;
  final double avgBuyPrice;
  final double avgSellPrice;
  final int buyEntriesCount;
  final int sellEntriesCount;
  final double vfProfitPer1000;
  final double instaProfitPer1000;
  final double totalInstaPayProfit;
  final double totalInstaPayVolume;
  final double vfProfit;
  final double instaProfit;
  final double totalGrossProfit;
  final double investorProfit;
  final bool isPaid;
  final int? paidAt;
  final String? paidByUid;
  final int calculatedAt;

  InvestorProfitSnapshot({
    this.calculationVersion = 0,
    required this.date,
    required this.workingDays,
    required this.openingCapital,
    required this.totalLoansOutstanding,
    required this.currentTotalCapital,
    required this.capitalShortfall,
    required this.totalVfCollected,
    required this.totalInstaCollected,
    required this.currentBankBalance,
    required this.usdExchangeEGP,
    required this.retailerVfDebt,
    required this.collectorCash,
    required this.retailerInstaDebt,
    required this.vfRawFlow,
    required this.instaRawFlow,
    required this.vfDailyFlow,
    required this.instaDailyFlow,
    required this.totalDailyFlow,
    required this.halfCumulativeCapital,
    required this.eligibleTotal,
    required this.vfShare,
    required this.instaShare,
    required this.avgBuyPrice,
    required this.avgSellPrice,
    required this.buyEntriesCount,
    required this.sellEntriesCount,
    required this.vfProfitPer1000,
    required this.instaProfitPer1000,
    required this.totalInstaPayProfit,
    required this.totalInstaPayVolume,
    required this.vfProfit,
    required this.instaProfit,
    required this.totalGrossProfit,
    required this.investorProfit,
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
      'openingCapital': openingCapital,
      'totalLoansOutstanding': totalLoansOutstanding,
      'currentTotalCapital': currentTotalCapital,
      'capitalShortfall': capitalShortfall,
      'totalVfCollected': totalVfCollected,
      'totalInstaCollected': totalInstaCollected,
      'currentBankBalance': currentBankBalance,
      'usdExchangeEGP': usdExchangeEGP,
      'retailerVfDebt': retailerVfDebt,
      'collectorCash': collectorCash,
      'retailerInstaDebt': retailerInstaDebt,
      'vfRawFlow': vfRawFlow,
      'instaRawFlow': instaRawFlow,
      'vfDailyFlow': vfDailyFlow,
      'instaDailyFlow': instaDailyFlow,
      'totalDailyFlow': totalDailyFlow,
      'halfCumulativeCapital': halfCumulativeCapital,
      'eligibleTotal': eligibleTotal,
      'vfShare': vfShare,
      'instaShare': instaShare,
      'avgBuyPrice': avgBuyPrice,
      'avgSellPrice': avgSellPrice,
      'buyEntriesCount': buyEntriesCount,
      'sellEntriesCount': sellEntriesCount,
      'vfProfitPer1000': vfProfitPer1000,
      'instaProfitPer1000': instaProfitPer1000,
      'totalInstaPayProfit': totalInstaPayProfit,
      'totalInstaPayVolume': totalInstaPayVolume,
      'vfProfit': vfProfit,
      'instaProfit': instaProfit,
      'totalGrossProfit': totalGrossProfit,
      'investorProfit': investorProfit,
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
      openingCapital: asDouble(map['openingCapital']),
      totalLoansOutstanding: asDouble(map['totalLoansOutstanding']),
      currentTotalCapital: asDouble(map['currentTotalCapital']),
      capitalShortfall: asDouble(map['capitalShortfall']),
      totalVfCollected: asDouble(map['totalVfCollected']),
      totalInstaCollected: asDouble(map['totalInstaCollected']),
      currentBankBalance: asDouble(map['currentBankBalance']),
      usdExchangeEGP: asDouble(map['usdExchangeEGP']),
      retailerVfDebt: asDouble(map['retailerVfDebt']),
      collectorCash: asDouble(map['collectorCash']),
      retailerInstaDebt: asDouble(map['retailerInstaDebt']),
      vfRawFlow: asDouble(map['vfRawFlow']),
      instaRawFlow: asDouble(map['instaRawFlow']),
      vfDailyFlow: asDouble(map['vfDailyFlow']),
      instaDailyFlow: asDouble(map['instaDailyFlow']),
      totalDailyFlow: asDouble(map['totalDailyFlow']),
      halfCumulativeCapital: asDouble(map['halfCumulativeCapital']),
      eligibleTotal: asDouble(map['eligibleTotal']),
      vfShare: asDouble(map['vfShare']),
      instaShare: asDouble(map['instaShare']),
      avgBuyPrice: asDouble(map['avgBuyPrice']),
      avgSellPrice: asDouble(map['avgSellPrice']),
      buyEntriesCount: asInt(map['buyEntriesCount']),
      sellEntriesCount: asInt(map['sellEntriesCount']),
      vfProfitPer1000: asDouble(map['vfProfitPer1000']),
      instaProfitPer1000: asDouble(map['instaProfitPer1000']),
      totalInstaPayProfit: asDouble(map['totalInstaPayProfit']),
      totalInstaPayVolume: asDouble(map['totalInstaPayVolume']),
      vfProfit: asDouble(map['vfProfit']),
      instaProfit: asDouble(map['instaProfit']),
      totalGrossProfit: asDouble(map['totalGrossProfit']),
      investorProfit: asDouble(map['investorProfit']),
      isPaid: map['isPaid'] == true,
      paidAt: map['paidAt'] != null ? asInt(map['paidAt']) : null,
      paidByUid: map['paidByUid'],
      calculatedAt: asInt(map['calculatedAt']),
    );
  }

  bool get isCurrentVersion => calculationVersion >= 2;
}
