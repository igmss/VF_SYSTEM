class SystemProfitSnapshot {
  final String date;
  final int workingDays;
  final double openingCapital;
  // totalSellAmount now represents total DISTRIBUTE_VFCASH (not SELL_USDT)
  final double totalSellAmount;
  final double vfDailyFlow;
  final double totalInstaAmount;
  final double instaDailyFlow;
  final double totalDailyFlow;
  final double totalBuyEgp;
  final double totalBuyUsdt;
  final double totalSellEgp;
  final double totalSellUsdt;
  final double totalDistVf;
  final double totalDistVfDebt;
  final double outstandingRetailerVfDebt;
  final double effectiveVfDist;
  final double avgBuy;
  final double avgSell;
  final double systemVfProfitPer1000;
  final double systemInstaProfitPer1000;
  final double vfProfit;
  final double instaProfit;
  final double internalVfFees;
  final double externalVfFees;
  final double instaFees;
  final double expenses;
  final double totalFees;
  final double businessGrossProfit;
  final double businessNetProfit;
  final int buyEntriesCount;
  final int sellEntriesCount;
  final int calculatedAt;

  SystemProfitSnapshot({
    required this.date,
    required this.workingDays,
    required this.openingCapital,
    required this.totalSellAmount,
    required this.vfDailyFlow,
    required this.totalInstaAmount,
    required this.instaDailyFlow,
    required this.totalDailyFlow,
    required this.totalBuyEgp,
    required this.totalBuyUsdt,
    required this.totalSellEgp,
    required this.totalSellUsdt,
    this.totalDistVf = 0,
    this.totalDistVfDebt = 0,
    this.outstandingRetailerVfDebt = 0,
    this.effectiveVfDist = 0,
    required this.avgBuy,
    required this.avgSell,
    required this.systemVfProfitPer1000,
    required this.systemInstaProfitPer1000,
    required this.vfProfit,
    required this.instaProfit,
    required this.internalVfFees,
    required this.externalVfFees,
    required this.instaFees,
    this.expenses = 0,
    required this.totalFees,
    required this.businessGrossProfit,
    required this.businessNetProfit,
    required this.buyEntriesCount,
    required this.sellEntriesCount,
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
      totalSellAmount: _asDouble(map['totalSellAmount']),
      vfDailyFlow: _asDouble(map['vfDailyFlow']),
      totalInstaAmount: _asDouble(map['totalInstaAmount']),
      instaDailyFlow: _asDouble(map['instaDailyFlow']),
      totalDailyFlow: _asDouble(map['totalDailyFlow']),
      totalBuyEgp: _asDouble(map['totalBuyEgp']),
      totalBuyUsdt: _asDouble(map['totalBuyUsdt']),
      totalSellEgp: _asDouble(map['totalSellEgp']),
      totalSellUsdt: _asDouble(map['totalSellUsdt']),
      totalDistVf: _asDouble(map['totalDistVf']),
      totalDistVfDebt: _asDouble(map['totalDistVfDebt']),
      outstandingRetailerVfDebt: _asDouble(map['outstandingRetailerVfDebt']),
      effectiveVfDist: _asDouble(map['effectiveVfDist']),
      avgBuy: _asDouble(map['avgBuy']),
      avgSell: _asDouble(map['avgSell']),
      systemVfProfitPer1000: _asDouble(map['spread'] ?? map['systemVfProfitPer1000']),
      systemInstaProfitPer1000: _asDouble(map['systemInstaProfitPer1000']),
      vfProfit: _asDouble(map['vfProfit']),
      instaProfit: _asDouble(map['instaProfit']),
      internalVfFees: _asDouble(map['internalVfFees']),
      externalVfFees: _asDouble(map['externalVfFees']),
      instaFees: _asDouble(map['instaFees']),
      expenses: _asDouble(map['expenses']),
      totalFees: _asDouble(map['totalFees']),
      businessGrossProfit: _asDouble(map['businessGrossProfit']),
      businessNetProfit: _asDouble(map['businessNetProfit']),
      buyEntriesCount: _asInt(map['buyEntriesCount']),
      sellEntriesCount: _asInt(map['sellEntriesCount']),
      calculatedAt: _asInt(map['calculatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'date': date,
      'workingDays': workingDays,
      'openingCapital': openingCapital,
      'totalSellAmount': totalSellAmount,
      'vfDailyFlow': vfDailyFlow,
      'totalInstaAmount': totalInstaAmount,
      'instaDailyFlow': instaDailyFlow,
      'totalDailyFlow': totalDailyFlow,
      'totalBuyEgp': totalBuyEgp,
      'totalBuyUsdt': totalBuyUsdt,
      'totalSellEgp': totalSellEgp,
      'totalSellUsdt': totalSellUsdt,
      'totalDistVf': totalDistVf,
      'totalDistVfDebt': totalDistVfDebt,
      'outstandingRetailerVfDebt': outstandingRetailerVfDebt,
      'effectiveVfDist': effectiveVfDist,
      'avgBuy': avgBuy,
      'avgSell': avgSell,
      'systemVfProfitPer1000': systemVfProfitPer1000,
      'systemInstaProfitPer1000': systemInstaProfitPer1000,
      'vfProfit': vfProfit,
      'instaProfit': instaProfit,
      'internalVfFees': internalVfFees,
      'externalVfFees': externalVfFees,
      'instaFees': instaFees,
      'expenses': expenses,
      'totalFees': totalFees,
      'businessGrossProfit': businessGrossProfit,
      'businessNetProfit': businessNetProfit,
      'buyEntriesCount': buyEntriesCount,
      'sellEntriesCount': sellEntriesCount,
      'calculatedAt': calculatedAt,
    };
  }
}
