part of 'distribution_provider.dart';

mixin InvestorOperationsMixin on ChangeNotifier {
  FirebaseDatabase get _db;
  List<dynamic> get _investorsRaw;
  String get _currentUserId;

  double get totalBankBalance;
  double get totalUsdExchangeBalance;
  List<Retailer> get retailers;
  List<Collector> get collectors;

  Future<void> addInvestor({
    required String name,
    required double investmentAmount,
    required int priority,
    required double profitSharePercentage,
  }) async {
    final inv = Investor(
      name: name,
      investmentAmount: investmentAmount,
      priority: priority,
      profitSharePercentage: profitSharePercentage,
      createdByUid: _currentUserId,
    );

    await _db.ref('investors').child(inv.id).set(inv.toMap());
  }

  Future<void> updateInvestor(Investor inv) async {
     await _db.ref('investors').child(inv.id).update(inv.toMap());
  }

  Future<void> deleteInvestor(String id) async {
    await _db.ref('investors').child(id).remove();
  }

  Map<String, dynamic> calculateWaterfall(List<Investor> investors, double avgBuy, double avgSell) {
    if (investors.isEmpty || avgBuy <= 0 || avgSell <= 0) {
      return {'dailyFlow': 0.0, 'profitPer1000': 0.0, 'allocations': <String, double>{}, 'profits': <String, double>{}};
    }

    // Profit Calculation: ProfitPer1000 = floor((1000 / AvgBuy) * AvgSell - 1000) - 1
    double profitPer1000 = ((1000 / avgBuy) * avgSell - 1000).floorToDouble() - 1;
    if (profitPer1000 < 0) profitPer1000 = 0;

    // DailyFlow (DF) = TotalCollected - Bank - USDExchange - OwnedByRetailers - HeldByCollectors.
    // Assuming 'TotalCollected' means total working capital in the system right now?
    // Let's actually sum up the current system state.
    // Wait, the formula in the prompt is: DF = TotalCollected - Bank - USDExchange - OwnedByRetailers - HeldByCollectors
    // This looks like we need a 'TotalCollected' value, but we might just use the *total* main capital.
    // Main Capital = Sum of all Investments.

    double totalInvestment = investors.fold(0.0, (sum, i) => sum + i.investmentAmount);
    double mainCapitalHalf = totalInvestment / 2;

    double bank = totalBankBalance;
    double usd = totalUsdExchangeBalance;
    double retailersDebt = retailers.fold(0.0, (sum, r) => sum + r.debt);
    double collectorsHand = collectors.fold(0.0, (sum, c) => sum + c.cashOnHand);

    // The prompt says DF = TotalCollected - ...
    // Usually, Daily Flow is the money *currently active* in Vodafone Cash.
    // So Total Working Capital = Total Investment.
    // Active in VF Cash (DF) = Total Investment - (Bank + USD + Retailers + Collectors)
    double dailyFlow = totalInvestment - bank - usd - retailersDebt - collectorsHand;
    if (dailyFlow < 0) dailyFlow = 0;

    Map<String, double> allocations = {};
    Map<String, double> profits = {};

    if (dailyFlow > mainCapitalHalf) {
      double remainingFlow = dailyFlow;

      // Sort investors by priority ascending (1 is highest priority)
      List<Investor> sortedInvestors = List.from(investors)..sort((a, b) => a.priority.compareTo(b.priority));

      for (var inv in sortedInvestors) {
        if (remainingFlow <= 0) break;

        double baseCalculation = inv.investmentAmount / 2;
        double allocated = 0;
        if (remainingFlow >= baseCalculation) {
            allocated = baseCalculation;
            remainingFlow -= baseCalculation;
        } else {
            allocated = remainingFlow;
            remainingFlow = 0;
        }

        allocations[inv.id] = allocated;

        // Final profit calculation
        double grossProfit = (allocated / 1000) * profitPer1000;
        double netProfit = grossProfit * (inv.profitSharePercentage / 100.0);
        profits[inv.id] = netProfit;
      }
    }

    return {
      'dailyFlow': dailyFlow,
      'profitPer1000': profitPer1000,
      'allocations': allocations,
      'profits': profits,
    };
  }
}
