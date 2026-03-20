# Architecture & Technical Documentation

## System Shape

The application is a Flutter client backed by Firebase Realtime Database and Firebase Authentication.

At runtime it is organized around three main providers:

- `AuthProvider`: authentication state and role-aware routing
- `AppProvider`: Vodafone-number tracking and Bybit synchronization
- `DistributionProvider`: banks, retailers, collectors, exchange balance, and ledger

`main.dart` creates these providers together and connects Bybit sync callbacks from `AppProvider` into `DistributionProvider`.

## Runtime Routing

The app entry point initializes:

- Flutter bindings
- Easy Localization with English and Arabic
- Firebase
- Provider state

Routing is role-driven:

- unauthenticated users -> login screen
- `COLLECTOR` -> collector dashboard
- all other authenticated roles -> admin dashboard shell

## High-Level Layers

```text
UI Screens
  -> Providers
    -> Services
      -> Firebase / Bybit / local preferences
```

### UI Layer

Main screen groups:

- `screens/auth`: login
- `screens/admin`: admin and finance workflows
- `screens/collector`: collector workflow
- root screens such as `home_screen` and `settings_screen`

### Provider Layer

#### AuthProvider

Responsibilities:

- listen to Firebase auth state changes
- load the current app user record from `users/`
- expose role helpers such as `isAdmin`, `isFinance`, and `isCollector`
- create users through `AuthService`

#### AppProvider

Responsibilities:

- load and mutate `mobile_numbers`
- load and mutate `transactions`
- save and load Bybit API credentials from `shared_preferences`
- run manual and live Bybit sync
- recalculate mobile-number usage counters
- emit buy/sell callbacks into the distribution layer

#### DistributionProvider

Responsibilities:

- load bank accounts, retailers, collectors, ledger, and USD exchange data
- compute aggregate balances for dashboards
- create and update entities in the financial operation layer
- keep collector records aligned with collector-role users
- record and expose ledger data

### Service Layer

#### AuthService

- wraps Firebase Auth sign-in and sign-out
- creates new users through the Firebase Auth REST API
- writes matching user profiles into Realtime Database
- auto-creates collector records for collector-role users

#### DatabaseService

- contains the Firebase logic for the Vodafone-number module
- manages `mobile_numbers`, `transactions`, and `sync_data`
- performs duplicate checks by `bybitOrderId`
- recalculates per-number usage based on stored transaction history

#### BybitService

- signs Bybit V5 requests with HMAC-SHA256
- syncs server time to reduce timestamp drift
- fetches completed P2P orders page by page
- fetches per-order details and chat messages
- searches chats and payment metadata for phone-number matches

## Main Data Domains

### Authentication Domain

- `users/{uid}`
- app roles defined in `app_user.dart`

### Vodafone Cash Domain

- `mobile_numbers`
- `transactions`
- `sync_data`

This is the original core module and still powers the Vodafone Cash tab and parts of the asset summary.

### Distribution Domain

- `bank_accounts`
- `retailers`
- `collectors`
- `financial_ledger`
- `usd_exchange`

This is the newer business-operations layer that powers most admin and collector workflows.

## Important Data Flow

### Login And Role Resolution

1. Firebase Auth emits auth state
2. `AuthProvider` loads `users/{uid}`
3. fallback user data is created in memory if the database record is missing
4. UI routes by role

### Bybit Sync Flow

1. `AppProvider` starts sync
2. `BybitService` fetches completed orders after the stored sync timestamp
3. each order is checked against `transactions` by `bybitOrderId`
4. new transactions are stored in Realtime Database
5. mobile-number usage counters are recalculated
6. buy/sell callbacks notify `DistributionProvider`
7. distribution-side balances and ledger effects can be applied

### Collector Workflow

1. collector logs in
2. collector dashboard loads assigned retailers from `DistributionProvider`
3. collection actions affect retailer debt and collector cash on hand
4. deposit actions move value from collector cash on hand into a bank account
5. financial ledger entries capture those movements

## Database Areas

Main Firebase nodes used by the current app:

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

## Scheduled Backend Logic

The `functions/` folder contains a Firebase scheduled function:

- `resetDailyLimits`

It resets `inDailyUsed` and `outDailyUsed` for all `mobile_numbers` records on an `Africa/Cairo` schedule and stores an audit entry under `system/lastDailyReset`.

## Current Architectural Reality

The most important architectural fact is that this codebase is a hybrid:

- the original Vodafone-number and Bybit tracker still exists
- the app shell now centers a wider distribution and accounting workflow

Any new changes should assume both layers are active and must stay consistent.
