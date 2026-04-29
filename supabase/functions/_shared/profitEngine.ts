import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  asNumber,
  safeDate,
  getMobileNumberBalance,
  getRetailerOutstandingDebt,
  getRetailerInstaPayOutstandingDebt,
  getTransactionTimestampMs,
  LedgerEntry,
  MobileNumber,
  Retailer
} from "./helpers.ts";

export const PROFIT_CALCULATION_VERSION = 3.1;

// ─── Interfaces ───────────────────────────────────────────────────────────────

export interface BankAccount {
  id: string;
  balance: number;
  bank_name?: string;
}

export interface UsdExchange {
  id: number;
  usdt_balance: number;
  last_price: number;
}

export interface Collector {
  id: string;
  cash_on_hand: number;
  name: string;
}

export interface Loan {
  id: string;
  principal_amount: number;
  amount_repaid: number;
  issued_at?: number | null;
  repaid_at?: number | null;
  status: string;
}

export interface Investor {
  id: string;
  name: string;
  invested_amount: number;
  profit_share_percent: number;
  investment_date?: number | string;
  capital_history?: Record<string, unknown> | null;
  total_profit_paid?: number | null;
  status: string;
}

export interface Partner {
  id: string;
  name: string;
  share_percent: number;
  status: string;
}

export interface DbData {
  openingCapital: number;
  ledger: LedgerEntry[];
  banks: BankAccount[];
  usdExchange: UsdExchange | null;
  retailers: Retailer[];
  collectors: Collector[];
  loans: Loan[];
  investors: Investor[];
  mobileNumbers: MobileNumber[];
}

export interface SystemProfitSnapshot {
  date_key: string;
  vf_net_profit: number;
  insta_net_profit: number;
  total_net_profit: number;
  vf_net_per_1000: number;
  insta_net_per_1000: number;
  total_flow: number;
  total_vf_distributed: number;
  total_insta_distributed: number;
  daily_avg_buy_price: number;
  global_avg_buy_price: number;
  vf_spread_profit: number;
  vf_deposit_profit: number;
  vf_discount_cost: number;
  vf_fee_cost: number;
  insta_gross_profit: number;
  insta_fee_cost: number;
  general_expenses: number;
  total_sell_usdt: number;
  total_sell_egp: number;
  opening_capital: number;
  effective_starting_capital: number;
  total_outstanding_loans: number;
  current_total_assets: number;
  bank_balance: number;
  vf_number_balance: number;
  retailer_debt: number;
  retailer_insta_debt: number;
  collector_cash: number;
  usd_exchange_egp: number;
  adjusted_total_assets: number;
  reconciled_profit: number;
  working_days: number;
  calculation_version: number;
  calculated_at: number;
  sell_entries_count: number;
  buy_entries_range_count: number;
}

// ─── Pure Functions ───────────────────────────────────────────────────────────

export function formatDateKey(dateInput: unknown): string {
  const parsed = safeDate(dateInput, new Date().toISOString());
  const normalized = new Date(Date.UTC(
    parsed.getUTCFullYear(),
    parsed.getUTCMonth(),
    parsed.getUTCDate()
  ));
  return normalized.toISOString().split("T")[0];
}

export function _dateKeyFromUnixMs(ts: number): string {
  const d = new Date(asNumber(ts));
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}-${String(d.getUTCDate()).padStart(2, "0")}`;
}

export function getDateKeysForRange(dateStr: string, workingDays = 1): string[] {
  const targetDate = safeDate(dateStr, new Date().toISOString());
  const normalizedTarget = new Date(Date.UTC(
    targetDate.getUTCFullYear(),
    targetDate.getUTCMonth(),
    targetDate.getUTCDate()
  ));
  const numDays = Math.max(1, asNumber(workingDays) || 1);
  const dates = [];

  for (let i = 0; i < numDays; i++) {
    const d = new Date(normalizedTarget);
    d.setUTCDate(normalizedTarget.getUTCDate() - i);
    dates.push(d.toISOString().split("T")[0]);
  }

  return dates;
}

export function isInvestorEligibleForDate(investor: Investor, dayKey: string): boolean {
  const startDateValue = investor?.investment_date;
  if (!startDateValue) return true;
  const investorStart = formatDateKey(startDateValue);
  return dayKey >= investorStart;
}

export function _sumActiveInvestorCapital(investors: Investor[]): number {
  let total = 0;
  investors.forEach((inv) => {
    if (inv.status === "active") {
      total += asNumber(inv.invested_amount);
    }
  });
  return total;
}

export function _sumOutstandingLoans(loans: Loan[]): number {
  let total = 0;
  loans.forEach((loan) => {
    total += Math.max(0, asNumber(loan.principal_amount) - asNumber(loan.amount_repaid));
  });
  return total;
}

export function _normalizeDateValueHistory(raw: unknown, fallbackValue: number) {
  const obj = (raw && typeof raw === "object") ? (raw as Record<string, unknown>) : {};
  const entries = Object.entries(obj)
    .map(([date, value]) => ({ date, value: asNumber(value) }))
    .filter((e) => !!e.date)
    .sort((a, b) => a.date.localeCompare(b.date));

  if (entries.length === 0) {
    return [{ date: "2000-01-01", value: asNumber(fallbackValue) }];
  }

  return entries;
}

export function _getHistoryValueOnDate(history: { date: string; value: number }[], dateKey: string) {
  let val = history[0]?.value ?? 0;
  for (const entry of history) {
    if (entry.date <= dateKey) val = entry.value;
    else break;
  }
  return val;
}

export function _getInvestorCapitalOnDate(investor: Investor, dateKey: string) {
  const raw = investor?.capital_history;
  const obj = (raw && typeof raw === "object") ? (raw as Record<string, unknown>) : {};
  const history = _normalizeDateValueHistory(obj, asNumber(investor?.invested_amount));
  return _getHistoryValueOnDate(history, dateKey);
}

export function _buildDailyFlowMapV6(ledger: LedgerEntry[]) {
  const dailyFlowMap: Record<string, { vf: number; insta: number }> = {};
  ledger.forEach((tx) => {
    if (tx.type !== "DISTRIBUTE_VFCASH" && tx.type !== "DISTRIBUTE_INSTAPAY") return;
    const ts = getTransactionTimestampMs(tx as any);
    const dateKey = _dateKeyFromUnixMs(ts);
    if (!dailyFlowMap[dateKey]) dailyFlowMap[dateKey] = { vf: 0, insta: 0 };
    if (tx.type === "DISTRIBUTE_VFCASH") dailyFlowMap[dateKey].vf += asNumber(tx.amount);
    if (tx.type === "DISTRIBUTE_INSTAPAY") dailyFlowMap[dateKey].insta += asNumber(tx.amount);
  });
  return dailyFlowMap;
}

export function _buildLoanTimelineV6(loans: Loan[]) {
  const events: { principal: number; issuedDate: string; repaidDate: string | null }[] = [];
  loans.forEach((loan) => {
    const issuedAt = loan.issued_at;
    if (!issuedAt) return;
    events.push({
      principal: asNumber(loan.principal_amount),
      issuedDate: _dateKeyFromUnixMs(asNumber(issuedAt)),
      repaidDate: loan.repaid_at ? _dateKeyFromUnixMs(asNumber(loan.repaid_at)) : null,
    });
  });
  return events;
}

export function _getOutstandingLoanPrincipalOnDateV6(
  loanEvents: { principal: number; issuedDate: string; repaidDate: string | null }[],
  dateKey: string
) {
  let outstanding = 0;
  loanEvents.forEach(({ principal, issuedDate, repaidDate }) => {
    if (issuedDate > dateKey) return;
    if (repaidDate && repaidDate <= dateKey) return;
    outstanding += principal;
  });
  return outstanding;
}

export function _getPrecedingHalfCapitalOnDateV6(activeInvestorsSorted: Investor[], currentInvestorId: string, dateKey: string) {
  let sum = 0;
  for (const inv of activeInvestorsSorted) {
    if (inv.id === currentInvestorId) break;
    if (formatDateKey(inv.investment_date) <= dateKey) {
      sum += _getInvestorCapitalOnDate(inv, dateKey) / 2;
    }
  }
  return sum;
}

export function _calculateInvestorDayV6(params: {
  investor: Investor;
  dateKey: string;
  vfFlow: number;
  instaFlow: number;
  activeInvestorsSorted: Investor[];
  openingCapitalHistory: { date: string; value: number }[];
  loanEvents: { principal: number; issuedDate: string; repaidDate: string | null }[];
}) {
  const { investor, dateKey, vfFlow, instaFlow, activeInvestorsSorted, openingCapitalHistory, loanEvents } = params;

  const sharePercent = asNumber(investor.profit_share_percent);
  const effectiveCap = _getHistoryValueOnDate(openingCapitalHistory, dateKey) - _getOutstandingLoanPrincipalOnDateV6(loanEvents, dateKey);
  const baseHurdle = effectiveCap / 2;
  const precedingHalfCap = _getPrecedingHalfCapitalOnDateV6(activeInvestorsSorted, investor.id, dateKey);
  const hurdle = baseHurdle + precedingHalfCap;

  const totalFlow = asNumber(vfFlow) + asNumber(instaFlow);
  const grossExcess = Math.max(0, totalFlow - hurdle);

  if (grossExcess <= 0) {
    return { hurdle, effectiveCap, excessFlow: 0, vfExcess: 0, instaExcess: 0, vfProfit: 0, instaProfit: 0, profit: 0 };
  }

  const myHalfCap = _getInvestorCapitalOnDate(investor, dateKey) / 2;
  const allowedExcess = Math.min(grossExcess, myHalfCap);

  if (allowedExcess <= 0) {
    return { hurdle, effectiveCap, excessFlow: 0, vfExcess: 0, instaExcess: 0, vfProfit: 0, instaProfit: 0, profit: 0 };
  }

  const ratio = totalFlow > 0 ? asNumber(vfFlow) / totalFlow : 0;
  const vfExcess = allowedExcess * ratio;
  const instaExcess = allowedExcess * (1 - ratio);
  
  // Use dynamic rates if provided, otherwise fallback to defaults (7 and 5)
  const vfRate = (params as any).vfRate || 7;
  const instaRate = (params as any).instaRate || 5;

  const vfProfit = (vfExcess / 1000) * vfRate * (sharePercent / 100);
  const instaProfit = (instaExcess / 1000) * instaRate * (sharePercent / 100);

  return { hurdle, effectiveCap, excessFlow: allowedExcess, vfExcess, instaExcess, vfProfit, instaProfit, profit: vfProfit + instaProfit };
}

export function _computeCurrentAssetTotal(dbData: DbData) {
  let bankBalance = 0;
  let vfNumberBalance = 0;
  let retailerDebt = 0;
  let retailerInstaDebt = 0;
  let collectorCash = 0;
  let usdExchangeEgp = 0;

  dbData.banks.forEach((bank) => {
    bankBalance += asNumber(bank.balance);
  });

  dbData.mobileNumbers.forEach((num) => {
    vfNumberBalance += getMobileNumberBalance(num);
  });

  dbData.retailers.forEach((retailer) => {
    retailerDebt += getRetailerOutstandingDebt(retailer);
    retailerInstaDebt += getRetailerInstaPayOutstandingDebt(retailer);
  });

  dbData.collectors.forEach((collector) => {
    collectorCash += asNumber(collector.cash_on_hand);
  });

  if (dbData.usdExchange) {
    const usdtBalance = asNumber(dbData.usdExchange.usdt_balance);
    const lastPrice = asNumber(dbData.usdExchange.last_price);
    if (usdtBalance > 0 && lastPrice > 0) {
      usdExchangeEgp = usdtBalance * lastPrice;
    }
  }

  return {
    bankBalance,
    vfNumberBalance,
    retailerDebt,
    retailerInstaDebt,
    collectorCash,
    usdExchangeEgp,
    currentTotalAssets: bankBalance + vfNumberBalance + retailerDebt + retailerInstaDebt + collectorCash + usdExchangeEgp
  };
}

export function _computeReconciledProfit(dbData: DbData, totalDistributions = 0) {
  const openingCapital = asNumber(dbData.openingCapital);
  const totalActiveInvestorCapital = _sumActiveInvestorCapital(dbData.investors);
  const totalOutstandingLoans = _sumOutstandingLoans(dbData.loans);
  const currentAssets = _computeCurrentAssetTotal(dbData);
  
  const effectiveStartingCapital = openingCapital + totalActiveInvestorCapital;
  const adjustedTotalAssets = currentAssets.currentTotalAssets + totalOutstandingLoans + asNumber(totalDistributions);
  const reconciledProfit = adjustedTotalAssets - effectiveStartingCapital;

  return {
    openingCapital,
    totalActiveInvestorCapital,
    totalOutstandingLoans,
    effectiveStartingCapital,
    totalDistributions: asNumber(totalDistributions),
    ...currentAssets,
    adjustedTotalAssets,
    netProfit: reconciledProfit,
    reconciledProfit
  };
}

export function _calculateInvestorEarningsFixedRate(investor: Investor, vfFlow: number, instaFlow: number, precedingCapital: number, openingCapital: number) {
  const hurdle = (asNumber(openingCapital) / 2) + asNumber(precedingCapital);
  
  const totalFlow = asNumber(vfFlow) + asNumber(instaFlow);
  const excessFlow = Math.max(0, totalFlow - hurdle);
  
  if (excessFlow <= 0) return { investorProfit: 0, vfProfit: 0, instaProfit: 0, hurdle, excessFlow: 0 };

  const vfRatio = totalFlow > 0 ? asNumber(vfFlow) / totalFlow : 0;
  const instaRatio = totalFlow > 0 ? asNumber(instaFlow) / totalFlow : 0;
  
  const vfExcess = excessFlow * vfRatio;
  const instaExcess = excessFlow * instaRatio;
  
  // Use dynamic rates if provided, otherwise fallback to defaults (7 and 5)
  const vfRate = (investor as any).vfRate || 7;
  const instaRate = (investor as any).instaRate || 5;

  const baseVfProfit = (vfExcess / 1000) * vfRate;
  const baseInstaProfit = (instaExcess / 1000) * instaRate;
  
  const shareFactor = asNumber(investor.profit_share_percent) / 100;
  const vfProfit = baseVfProfit * shareFactor;
  const instaProfit = baseInstaProfit * shareFactor;
  
  return {
    investorProfit: vfProfit + instaProfit,
    vfProfit,
    instaProfit,
    baseVfProfit,
    baseInstaProfit,
    hurdle,
    excessFlow,
    vfExcess,
    instaExcess
  };
}

export function _getDailyAvgBuyPrice(ledger: LedgerEntry[], targetTs: number): number {
  let dailyBuyEgp = 0;
  let dailyBuyUsdt = 0;
  
  const targetDate = new Date(targetTs).toISOString().split("T")[0];
  
  ledger.forEach((tx) => {
    if (tx.type === "BUY_USDT") {
      const txDate = new Date(getTransactionTimestampMs(tx as any)).toISOString().split("T")[0];
      if (txDate === targetDate) {
        dailyBuyEgp += asNumber(tx.amount);
        dailyBuyUsdt += asNumber(tx.usdt_quantity);
      }
    }
  });

  if (dailyBuyUsdt > 0) return dailyBuyEgp / dailyBuyUsdt;

  let bestTs = 0;
  let fallbackPrice = 53.52;

  ledger.forEach((tx) => {
    if (tx.type === "BUY_USDT") {
      const txTs = getTransactionTimestampMs(tx as any);
      if (txTs < targetTs && txTs > bestTs) {
        const qty = asNumber(tx.usdt_quantity);
        if (qty > 0) {
          fallbackPrice = asNumber(tx.amount) / qty;
          bestTs = txTs;
        }
      }
    }
  });
  
  return fallbackPrice;
}

export function _getPerformanceForDateRange(dbData: DbData, dateStr: string, workingDays = 1) {
  const numDays = asNumber(workingDays) || 1;
  const targetDate = safeDate(dateStr, new Date().toISOString());
  const startDate = new Date(Date.UTC(targetDate.getUTCFullYear(), targetDate.getUTCMonth(), targetDate.getUTCDate()));
  startDate.setUTCDate(startDate.getUTCDate() - (numDays - 1));
  startDate.setUTCHours(0, 0, 0, 0);

  const endThreshold = new Date(Date.UTC(targetDate.getUTCFullYear(), targetDate.getUTCMonth(), targetDate.getUTCDate()));
  endThreshold.setUTCHours(23, 59, 59, 999);

  const startTs = startDate.getTime();
  const endTs = endThreshold.getTime();

  const dailyAvgBuyPrice = _getDailyAvgBuyPrice(dbData.ledger, endTs);

  let totalVfDistributed = 0;
  let totalInstaDistributed = 0;
  let totalSellEgp = 0;
  let totalSellUsdt = 0;
  let vfDepositProfit = 0;
  let vfDiscountCost = 0;
  let vfFeeCost = 0;
  let instaGrossProfit = 0;
  let instaFeeCost = 0;
  let generalExpenses = 0;
  let sellEntriesCount = 0;
  let buyEntriesRangeCount = 0;

  dbData.ledger.forEach((tx) => {
    const txTs = getTransactionTimestampMs(tx as any);
    const isWithinRange = txTs >= startTs && txTs <= endTs;

    if (!isWithinRange) return;

    if (tx.type === "SELL_USDT") {
      totalSellEgp += asNumber(tx.amount);
      totalSellUsdt += asNumber(tx.usdt_quantity);
      sellEntriesCount++;
    } else if (tx.type === "BUY_USDT") {
      buyEntriesRangeCount++;
    } else if (tx.type === "DISTRIBUTE_VFCASH") {
      const amount = asNumber(tx.amount);
      totalVfDistributed += amount;
      const debtMatch = (tx.notes || "").match(/Debt \+([0-9.]+)/);
      const debtAmount = debtMatch ? parseFloat(debtMatch[1]) : amount;
      const discount = amount - debtAmount;
      if (discount > 0) vfDiscountCost += discount;
    } else if (tx.type === "DISTRIBUTE_INSTAPAY") {
      totalInstaDistributed += asNumber(tx.amount);
    } else if (tx.type === "INSTAPAY_DIST_PROFIT") {
      instaGrossProfit += asNumber(tx.amount);
    } else if (tx.type === "VFCASH_RETAIL_PROFIT") {
      vfDepositProfit += asNumber(tx.amount);
    } else if (tx.type === "INTERNAL_VF_TRANSFER_FEE" || tx.type === "EXPENSE_VFCASH_FEE") {
      vfFeeCost += asNumber(tx.amount);
    } else if (tx.type === "EXPENSE_INSTAPAY_FEE") {
      instaFeeCost += asNumber(tx.amount);
    } else if (tx.type === "EXPENSE_BANK") {
      generalExpenses += asNumber(tx.amount);
    }
  });

  const vfSpreadProfit = totalSellEgp - (totalSellUsdt * dailyAvgBuyPrice);
  const vfNetProfit = vfSpreadProfit + vfDepositProfit - vfDiscountCost - vfFeeCost;
  const instaNetProfit = instaGrossProfit - instaFeeCost;
  const totalNetProfit = vfNetProfit + instaNetProfit - generalExpenses;

  const vfNetPer1000 = totalVfDistributed > 0 ? (vfNetProfit / totalVfDistributed) * 1000 : 0;
  const instaNetPer1000 = totalInstaDistributed > 0 ? (instaNetProfit / totalInstaDistributed) * 1000 : 0;

  return {
    date: formatDateKey(dateStr),
    workingDays: numDays,
    vfNetProfit,
    instaNetProfit,
    totalNetProfit,
    vfNetPer1000,
    instaNetPer1000,
    totalFlow: totalVfDistributed + totalInstaDistributed,
    totalVfDistributed,
    totalInstaDistributed,
    dailyAvgBuyPrice,
    globalAvgBuyPrice: dailyAvgBuyPrice, 
    vfSpreadProfit,
    vfDepositProfit,
    vfDiscountCost,
    vfFeeCost,
    instaGrossProfit,
    instaFeeCost,
    generalExpenses,
    totalSellUsdt,
    totalSellEgp,
    sellEntriesCount,
    buyEntriesRangeCount,
    calculatedAt: Date.now()
  };
}

export function _buildSystemProfitSnapshotForDate(dbData: DbData, dateStr: string, totalDistributions = 0): SystemProfitSnapshot {
  const performance = _getPerformanceForDateRange(dbData, dateStr, 1);
  const state = _computeReconciledProfit(dbData, totalDistributions);

  return {
    date_key: performance.date,
    vf_net_profit: performance.vfNetProfit,
    insta_net_profit: performance.instaNetProfit,
    total_net_profit: performance.totalNetProfit,
    vf_net_per_1000: performance.vfNetPer1000,
    insta_net_per_1000: performance.instaNetPer1000,
    total_flow: performance.totalFlow,
    total_vf_distributed: performance.totalVfDistributed,
    total_insta_distributed: performance.totalInstaDistributed,
    daily_avg_buy_price: performance.dailyAvgBuyPrice,
    global_avg_buy_price: performance.globalAvgBuyPrice,
    vf_spread_profit: performance.vfSpreadProfit,
    vf_deposit_profit: performance.vfDepositProfit,
    vf_discount_cost: performance.vfDiscountCost,
    vf_fee_cost: performance.vfFeeCost,
    insta_gross_profit: performance.instaGrossProfit,
    insta_fee_cost: performance.instaFeeCost,
    general_expenses: performance.generalExpenses,
    total_sell_usdt: performance.totalSellUsdt,
    total_sell_egp: performance.totalSellEgp,
    opening_capital: state.openingCapital,
    effective_starting_capital: state.effectiveStartingCapital,
    total_outstanding_loans: state.totalOutstandingLoans,
    current_total_assets: state.currentTotalAssets,
    bank_balance: state.bankBalance,
    vf_number_balance: state.vfNumberBalance,
    retailer_debt: state.retailerDebt,
    retailer_insta_debt: state.retailerInstaDebt,
    collector_cash: state.collectorCash,
    usd_exchange_egp: state.usdExchangeEgp,
    adjusted_total_assets: state.adjustedTotalAssets,
    reconciled_profit: state.reconciledProfit,
    working_days: performance.workingDays,
    calculation_version: PROFIT_CALCULATION_VERSION,
    calculated_at: performance.calculatedAt,
    sell_entries_count: performance.sellEntriesCount,
    buy_entries_range_count: performance.buyEntriesRangeCount
  };
}

export async function _ensureSystemProfitSnapshots(
  supabase: SupabaseClient,
  dateStr: string,
  workingDays: number,
  dbData: DbData,
  totalDistributions = 0
) {
  const dates = getDateKeysForRange(dateStr, workingDays);
  const snapshotsArray: SystemProfitSnapshot[] = [];

  dates.forEach((dayKey) => {
    const snapshot = _buildSystemProfitSnapshotForDate(dbData, dayKey, totalDistributions);
    snapshotsArray.push(snapshot);
  });

  if (snapshotsArray.length > 0) {
    const { error } = await supabase
      .from("system_profit_snapshots")
      .upsert(snapshotsArray, { onConflict: "date_key" });
    
    if (error) throw error;
  }

  const snapshotsMap: Record<string, SystemProfitSnapshot> = {};
  snapshotsArray.forEach(s => {
    snapshotsMap[s.date_key] = s;
  });
  return snapshotsMap;
}

export function _buildProfitDistributionContext(dateKeys: string[], systemSnapshots: Record<string, SystemProfitSnapshot>, dbData: DbData, totalDistributions = 0) {
  const reconciliation = _computeReconciledProfit(dbData, totalDistributions);
  let operationalProfit = 0;
  let positiveOperationalProfit = 0;
  const distributableProfitByDate: Record<string, number> = {};

  dateKeys.forEach((dayKey) => {
    const rawNet = asNumber(systemSnapshots[dayKey]?.total_net_profit);
    operationalProfit += rawNet;
    positiveOperationalProfit += Math.max(0, rawNet);
  });

  const cappedProfit = Math.min(
    Math.max(0, operationalProfit),
    Math.max(0, reconciliation.reconciledProfit)
  );
  const allocationRatio = positiveOperationalProfit > 0 ? (cappedProfit / positiveOperationalProfit) : 0;

  dateKeys.forEach((dayKey) => {
    const rawNet = asNumber(systemSnapshots[dayKey]?.total_net_profit);
    distributableProfitByDate[dayKey] = Math.max(0, rawNet) * allocationRatio;
  });

  return {
    ...reconciliation,
    operationalProfit,
    positiveOperationalProfit,
    finalDistributableProfit: cappedProfit,
    allocationRatio,
    distributableProfitByDate
  };
}

export function _buildInvestorSnapshotForDate(
  investor: Investor,
  systemSnapshot: SystemProfitSnapshot,
  precedingCapital: number,
  openingCapital: number,
  existingSnapshot: any = null
) {
  if (existingSnapshot?.is_paid === true) {
    return existingSnapshot;
  }

  const hurdle = (asNumber(openingCapital) / 2) + asNumber(precedingCapital);
  const totalFlow = asNumber(systemSnapshot.total_flow);
  const vfFlow = asNumber(systemSnapshot.total_vf_distributed);
  const instaFlow = asNumber(systemSnapshot.total_insta_distributed);

  let investorProfit = 0;
  let vfInvestorProfit = 0;
  let instaInvestorProfit = 0;
  let excess = 0;
  let vfExcess = 0;
  let instaExcess = 0;

  if (totalFlow > hurdle) {
    const rawExcess = totalFlow - hurdle;
    excess = rawExcess;

    vfExcess = excess * (totalFlow > 0 ? (vfFlow / totalFlow) : 0);
    instaExcess = excess * (totalFlow > 0 ? (instaFlow / totalFlow) : 0);

    const shareFactor = asNumber(investor.profit_share_percent) / 100;
    const vfRate = Math.max(0, asNumber(systemSnapshot.vf_net_per_1000));
    const instaRate = Math.max(0, asNumber(systemSnapshot.insta_net_per_1000));
    vfInvestorProfit = (vfExcess / 1000) * vfRate * shareFactor;
    instaInvestorProfit = (instaExcess / 1000) * instaRate * shareFactor;
    investorProfit = vfInvestorProfit + instaInvestorProfit;
  }

  return {
    investor_id: investor.id,
    date_key: systemSnapshot.date_key,
    hurdle,
    preceding_capital: precedingCapital,
    excess,
    vf_excess: vfExcess,
    insta_excess: instaExcess,
    vf_net_per_1000: asNumber(systemSnapshot.vf_net_per_1000),
    insta_net_per_1000: asNumber(systemSnapshot.insta_net_per_1000),
    vf_investor_profit: vfInvestorProfit,
    insta_investor_profit: instaInvestorProfit,
    investor_profit: investorProfit,
    total_flow: totalFlow,
    vf_flow: vfFlow,
    insta_flow: instaFlow,
    profit_share_percent: asNumber(investor.profit_share_percent),
    opening_capital: asNumber(openingCapital),
    total_loans_outstanding: asNumber(systemSnapshot.total_outstanding_loans),
    current_total_assets: asNumber(systemSnapshot.current_total_assets),
    reconciled_profit: asNumber(systemSnapshot.reconciled_profit),
    current_bank_balance: asNumber(systemSnapshot.bank_balance),
    usd_exchange_egp: asNumber(systemSnapshot.usd_exchange_egp),
    retailer_vf_debt: asNumber(systemSnapshot.retailer_debt),
    collector_cash: asNumber(systemSnapshot.collector_cash),
    retailer_insta_debt: asNumber(systemSnapshot.retailer_insta_debt),
    global_avg_buy_price: asNumber(systemSnapshot.global_avg_buy_price),
    total_net_profit: asNumber(systemSnapshot.total_net_profit),
    working_days: 1,
    calculation_version: PROFIT_CALCULATION_VERSION,
    is_paid: existingSnapshot?.is_paid === true,
    paid_at: existingSnapshot?.paid_at ?? null,
    paid_by_uid: existingSnapshot?.paid_by_uid ?? null,
    calculated_at: Date.now()
  };
}

export function _buildPartnerSnapshotForDate(
  partner: Partner,
  systemSnapshot: SystemProfitSnapshot,
  totalInvestorProfitDeducted: number,
  existingSnapshot: any = null,
  allocationRatio = 1
) {
  const totalNetProfit = asNumber(systemSnapshot.total_net_profit);
  const reconciledPool = Math.max(0, totalNetProfit * asNumber(allocationRatio));
  const remainingForPartners = Math.max(0, reconciledPool - asNumber(totalInvestorProfitDeducted));
  const partnerProfit = remainingForPartners * (asNumber(partner.share_percent) / 100);

  return {
    partner_id: partner.id,
    date_key: systemSnapshot.date_key,
    total_net_profit: totalNetProfit,
    allocation_ratio: asNumber(allocationRatio),
    reconciled_pool: reconciledPool,
    total_investor_profit_deducted: totalInvestorProfitDeducted,
    remaining_for_partners: remainingForPartners,
    partner_profit: partnerProfit,
    share_percent: asNumber(partner.share_percent),
    vf_spread_profit: asNumber(systemSnapshot.vf_spread_profit),
    vf_deposit_profit: asNumber(systemSnapshot.vf_deposit_profit),
    vf_discount_cost: asNumber(systemSnapshot.vf_discount_cost),
    vf_fee_cost: asNumber(systemSnapshot.vf_fee_cost),
    vf_net_profit: asNumber(systemSnapshot.vf_net_profit),
    vf_net_per_1000: asNumber(systemSnapshot.vf_net_per_1000),
    insta_gross_profit: asNumber(systemSnapshot.insta_gross_profit),
    insta_fee_cost: asNumber(systemSnapshot.insta_fee_cost),
    insta_net_profit: asNumber(systemSnapshot.insta_net_profit),
    insta_net_per_1000: asNumber(systemSnapshot.insta_net_per_1000),
    general_expenses: asNumber(systemSnapshot.general_expenses),
    global_avg_buy_price: asNumber(systemSnapshot.global_avg_buy_price),
    vf_daily_flow: asNumber(systemSnapshot.total_vf_distributed),
    insta_daily_flow: asNumber(systemSnapshot.total_insta_distributed),
    total_daily_flow: asNumber(systemSnapshot.total_flow),
    total_vf_distributed: asNumber(systemSnapshot.total_vf_distributed),
    total_insta_distributed: asNumber(systemSnapshot.total_insta_distributed),
    working_days: 1,
    calculation_version: PROFIT_CALCULATION_VERSION,
    is_paid: existingSnapshot?.is_paid === true,
    paid_at: existingSnapshot?.paid_at ?? null,
    paid_by_uid: existingSnapshot?.paid_by_uid ?? null,
    paid_from_type: existingSnapshot?.paid_from_type ?? null,
    paid_from_id: existingSnapshot?.paid_from_id ?? null,
    calculated_at: Date.now()
  };
}
