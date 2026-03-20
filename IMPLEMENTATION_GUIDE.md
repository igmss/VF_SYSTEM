# Implementation Guide

## Current Product Model

Treat this application as a role-based distribution and accounting app with a built-in Vodafone Cash tracking module.

That means implementation work usually falls into one of these areas:

- authentication and role routing
- Vodafone-number tracking
- Bybit synchronization
- distribution operations
- ledger and balance consistency

## Provider Responsibilities

### AuthProvider

Use `AuthProvider` when work involves:

- login flow
- current user state
- role checks
- user creation
- sign-out flow

### AppProvider

Use `AppProvider` when work involves:

- mobile number CRUD
- transaction history for Vodafone Cash numbers
- Bybit API credential handling
- live sync state
- duplicate prevention for synced orders
- usage recalculation for numbers

### DistributionProvider

Use `DistributionProvider` when work involves:

- bank accounts
- retailers
- collectors
- assigning retailers to collectors
- collector collection and deposit workflows
- financial ledger records
- USD exchange balance and price

## Key Models

### AppUser

- stored under `users/`
- owns the runtime role
- drives dashboard routing

### MobileNumber

- stores phone number identity
- stores initial balance
- stores in/out daily, monthly, and total limits and usage
- computes current balance from initial balance and cumulative movement

### CashTransaction

- stores the Vodafone-number-side transaction history
- links Bybit orders to phone-number activity
- uses `bybitOrderId` for duplicate prevention

### FinancialTransaction

This is the distribution-side ledger record.

Important flow types currently include:

- `FUND_BANK`
- `BUY_USDT`
- `SELL_USDT`
- `DISTRIBUTE_VFCASH`
- `COLLECT_CASH`
- `DEPOSIT_TO_BANK`
- `EXPENSE_VFCASH_FEE`

### BankAccount / Retailer / Collector

These models hold the operational state for the distribution business.

## Main Implementation Patterns

### 1. Role-Based Routing

The role check is centralized in `main.dart`.

Implementation guidance:

- collector-specific features should live in the collector flow unless intentionally shared
- admin and finance screens should be exposed through the admin dashboard shell
- changes to role semantics must be reflected in both model helpers and screen access rules

### 2. Bybit Sync And Duplicate Prevention

Use the existing `bybitOrderId` duplicate strategy instead of inventing a second sync identity.

Current pattern:

1. fetch completed orders from Bybit
2. check whether the order already exists in `transactions`
3. skip if found
4. otherwise create a new `CashTransaction`
5. recalculate usage and persist latest sync metadata

If a change touches sync behavior, validate both:

- the mobile-number transaction history
- the distribution-side effects triggered via callbacks

### 3. Distribution-Side Effects

`AppProvider` and `DistributionProvider` are intentionally linked.

When a buy or sell order is synced:

- the Vodafone-number module records the transaction
- the distribution layer may update exchange balance, bank state, or ledger state

Implementation guidance:

- do not treat the two providers as unrelated
- watch for double-recording or mismatched value movement
- keep naming clear about whether a change belongs to tracking data or ledger data

### 4. Collector Consistency

Collector user accounts and collector business records are related but not identical.

The code already supports:

- auto-creating collector records for collector-role users
- syncing missing collector records from the `users` node

If you change collector onboarding, keep both records in sync.

### 5. Mobile-Number Usage Calculation

Usage is recalculated from stored transactions rather than relying only on incremental counters.

This is important because it makes the UI recoverable after:

- transaction deletion
- older data imports
- repeated reloads
- sync interruptions

## Data Areas To Keep Straight

### Vodafone Tracking Nodes

- `mobile_numbers`
- `transactions`
- `sync_data`

### Distribution Nodes

- `bank_accounts`
- `retailers`
- `collectors`
- `financial_ledger`
- `usd_exchange`

### Shared / System Nodes

- `users`
- `system`

## Cloud Function

The Firebase scheduled function in `functions/index.js` resets:

- `mobile_numbers/*/inDailyUsed`
- `mobile_numbers/*/outDailyUsed`

It should be treated as a narrow maintenance job, not a general accounting reset.

## Practical Guidance For Future Changes

- If a task mentions phone numbers, usage, sync, or Bybit matching, start in `AppProvider`, `DatabaseService`, and `BybitService`.
- If a task mentions banks, retailers, collectors, exchange balances, or ledger records, start in `DistributionProvider` and the related admin or collector screen.
- If a task changes who can access something, start in `AuthProvider`, `AppUser`, and the dashboard tab configuration.
- If a task changes business totals, verify both the dashboard aggregate calculations and the underlying per-entity balances.

## What Not To Assume

- Do not assume the README-era description of the app is sufficient.
- Do not assume the Vodafone-number module is deprecated; it is still active in the UI.
- Do not assume only admins use the app; collector workflows are first-class.
