# Vodafone Distribution System - Project Summary

## Overview

This project is a Flutter application for managing a Vodafone Cash distribution operation.

It started as a Vodafone-number and Bybit sync tracker, and that module still exists, but the active app now also includes:

- role-based authentication
- bank account management
- retailer debt tracking
- collector cash workflows
- USDT exchange balance tracking
- financial ledger recording

The entry point in `lib/main.dart` routes users into either:

- an admin/finance dashboard
- or a dedicated collector dashboard

## What The App Does Today

### Vodafone Cash Module

- Store multiple Vodafone Cash numbers
- Track initial balance plus inbound and outbound usage
- Keep daily, monthly, and total usage counters
- Mark one number as the default for new matched transactions
- View transaction history per number

### Bybit Module

- Store Bybit API credentials locally on device
- Fetch completed P2P orders
- Prevent duplicates using `bybitOrderId`
- Parse order metadata such as payment method, quantity, price, and side
- Support live monitoring on a timer

### Distribution Module

- Manage bank accounts and balances
- Maintain a default bank account for buy-side flows
- Manage retailers and their outstanding debt
- Manage collectors and their cash-on-hand limits
- Assign retailers to collectors
- Record ledger events for funding, buy orders, sell orders, distribution, collection, deposit, and transfer fees
- Track USDT held in the exchange plus the last known EGP/USDT price

### Access Control

- `ADMIN`: full access
- `FINANCE`: financial and operational access
- `COLLECTOR`: collector workflow only
- `OPERATOR`: fallback role in the app model

## Core Technical Pieces

### Providers

- `AuthProvider`: sign-in state, current user, role checks
- `AppProvider`: Vodafone-number tracking and Bybit sync
- `DistributionProvider`: banks, retailers, collectors, ledger, and exchange balance

### Services

- `AuthService`: Firebase Auth plus user-record creation and sync
- `BybitService`: signed Bybit API requests and chat lookup helpers
- `DatabaseService`: Firebase reads and writes for the Vodafone-number module

### Firebase

The app uses Firebase Realtime Database for operational data and Firebase Auth for user login.

Main data groups:

- `users`
- `mobile_numbers`
- `transactions`
- `sync_data`
- `bank_accounts`
- `retailers`
- `collectors`
- `financial_ledger`
- `usd_exchange`
- `system`

## Primary Screens

### Admin / Finance Shell

The admin dashboard currently exposes tabs for:

- overview
- Vodafone Cash numbers
- banks
- USD exchange
- EGP/USDT rate
- retailers
- collectors
- ledger
- users
- settings

### Collector Shell

The collector dashboard focuses on:

- assigned retailers
- collection status
- cash on hand
- depositing back into bank accounts

## Important Implementation Notes

- The codebase is not just a tracking app anymore; it is a role-based business operations app.
- The Vodafone-number module is still important because it feeds balances and sync data into the larger business picture.
- `main.dart` connects `AppProvider` callbacks into `DistributionProvider`, so Bybit activity can affect both the tracking side and the accounting side.
- A Firebase Cloud Function resets daily mobile-number usage counters on a Cairo-based schedule.

## Current Status

The current architecture is best understood as a hybrid system:

1. Vodafone Cash number and Bybit sync tracking
2. Distribution operations and financial accounting
3. Role-based access and localized UI

That is the model we should use going forward when making changes, writing docs, or planning features.
