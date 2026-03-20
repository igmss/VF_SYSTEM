# Vodafone Distribution System

A Flutter application for operating a Vodafone Cash distribution business with Firebase and Bybit integration.

The current product is broader than a simple phone-number tracker. It combines:

- Role-based access for admins, finance users, collectors, and operators
- Vodafone Cash number tracking with separate inbound and outbound limits
- Bybit P2P sync for buy and sell orders
- Bank account balance management
- Retailer debt tracking
- Collector cash collection and bank deposit workflows
- A financial ledger that records business flows across the system
- Arabic and English localization

## Main Workflows

### Admin / Finance

- Manage Vodafone Cash numbers and monitor balances
- Sync Bybit P2P orders into the system
- Manage bank accounts and default bank used for buy orders
- Track USDT held in the exchange and the last known EGP/USDT rate
- Create and manage retailers and collectors
- Assign retailers to collectors
- Review the financial ledger and user accounts

### Collector

- View assigned retailers
- Record cash collection from retailers
- Track personal cash on hand against a limit
- Deposit collected cash into bank accounts

## App Structure

```text
lib/
|-- main.dart                         # App bootstrap, localization, routing
|-- models/
|   |-- app_user.dart                # Auth user and role model
|   |-- bank_account.dart            # Bank account entity
|   |-- collector.dart               # Collector entity
|   |-- financial_transaction.dart   # Ledger transaction model
|   |-- models.dart                  # Mobile numbers, cash tx, Bybit order models
|   `-- retailer.dart                # Retailer entity
|-- providers/
|   |-- app_provider.dart            # Vodafone number + Bybit sync state
|   |-- auth_provider.dart           # Login state and user role state
|   `-- distribution_provider.dart   # Banks, retailers, collectors, ledger, exchange
|-- screens/
|   |-- admin/                       # Admin and finance dashboards
|   |-- auth/                        # Login screen
|   |-- collector/                   # Collector dashboard
|   |-- home_screen.dart             # Vodafone number tracking UI
|   `-- settings_screen.dart         # App and sync settings
|-- services/
|   |-- auth_service.dart            # Firebase auth and user creation helpers
|   |-- bybit_service.dart           # Bybit P2P API integration
|   `-- database_service.dart        # Firebase operations for number tracking
`-- utils/                           # Shared helpers and constants
```

## Architecture Overview

The app has two cooperating business layers:

1. `AppProvider`
   Handles the Vodafone-number module:
   - mobile numbers
   - Bybit order sync
   - duplicate prevention by `bybitOrderId`
   - live sync and transaction history

2. `DistributionProvider`
   Handles the wider distribution operation:
   - bank accounts
   - retailers
   - collectors
   - ledger entries
   - USD exchange balance

`main.dart` wires those providers together so Bybit sync events can also create business-side ledger effects.

## Authentication And Roles

Firebase Authentication is used for sign-in. The app routes users by role:

- `ADMIN`: full access including user management
- `FINANCE`: financial operations without user-management access
- `COLLECTOR`: collector-only dashboard
- `OPERATOR`: currently routed to the admin shell with limited feature exposure in code

User records are stored in the Realtime Database under `users/`.

## Firebase Realtime Database Areas

The app currently works with these main nodes:

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

## Bybit Integration

Bybit P2P orders are synced through the V5 API.

The app uses this data to:

- create or skip Vodafone Cash transactions based on duplicate checks
- update mobile-number usage counters
- trigger buy and sell side business logic
- capture payment-method details and chat summaries when useful

API credentials are stored locally with `shared_preferences` from inside the app settings flow.

## Daily Reset Automation

The `functions/` folder contains a Firebase scheduled Cloud Function:

- `resetDailyLimits`

It resets `inDailyUsed` and `outDailyUsed` for all records in `mobile_numbers` on an `Africa/Cairo` schedule and writes an audit entry under `system/lastDailyReset`.

## Setup

### Prerequisites

- Flutter 3.x
- Dart 3.x
- Firebase project with Realtime Database and Authentication enabled
- Bybit API credentials with the required P2P permissions

### Install

```bash
flutter pub get
```

### Firebase

This project already includes Firebase config files in the Flutter app. If you need to rebind it to a different Firebase project, update the generated Firebase configuration and project settings accordingly.

### Run

```bash
flutter run
```

## Notes About The Current Codebase

- The codebase still contains the original Vodafone Cash tracker module.
- Some older docs referred only to that module, but the app has since evolved into a larger distribution and accounting system.
- The current documentation reflects the code that is actually wired into `main.dart`.

## Key Dependencies

- `firebase_core`
- `firebase_auth`
- `firebase_database`
- `provider`
- `http`
- `crypto`
- `shared_preferences`
- `easy_localization`
- `intl`
- `uuid`
