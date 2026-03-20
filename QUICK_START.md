# Quick Start Guide

Get the Vodafone Distribution System running quickly for local development and first-use testing.

## Before You Start

You will need:

- Flutter 3.x
- A Firebase project with Realtime Database and Email/Password Authentication
- Bybit API credentials with the required P2P read access
- An Android emulator, iOS simulator, or physical device

## Fast Setup

### 1. Install Dependencies

```bash
flutter pub get
```

### 2. Confirm Firebase Configuration

This workspace is already configured for the Firebase project `vodatracking`.

Files already present in the repo:

- `lib/firebase_options.dart`
- `firebase.json`
- `.firebaserc`

If you are using the same Firebase project, you can continue directly.

If you want to bind the app to a different Firebase project:

```bash
flutterfire configure --project=<your-project-id>
```

Then review the generated Firebase files before running the app.

### 3. Enable Firebase Services

In Firebase Console, make sure these are enabled:

- Realtime Database
- Authentication -> Email/Password

### 4. Run The App

```bash
flutter run
```

## First Login Setup

This app is role-based, so start by creating or using a Firebase Auth user that also has a matching record in the `users/` node.

Minimum fields in `users/{uid}`:

```json
{
  "uid": "firebase-auth-uid",
  "email": "admin@example.com",
  "name": "Admin User",
  "role": "ADMIN",
  "isActive": true,
  "createdAt": "2026-03-19T00:00:00.000Z"
}
```

Recommended first role:

- `ADMIN`

That gives access to the full admin dashboard, user management, financial tabs, and settings.

## First-Time In-App Setup

### 1. Sign In

- Open the app
- Log in with your Firebase Email/Password account

### 2. Add Vodafone Cash Numbers

From the Vodafone Cash numbers tab:

- add at least one mobile number
- set an initial balance if needed
- define inbound and outbound daily/monthly limits

### 3. Add A Bank Account

From the banks tab:

- create at least one bank account
- optionally give it an opening balance

The first bank account becomes the default buy-side bank if none exists.

### 4. Configure Bybit Credentials

Bybit credentials are entered inside the app, not in `main.dart`.

Go to settings and save:

- Bybit API key
- Bybit API secret

These are stored locally on the device using app preferences.

### 5. Test Sync

After credentials are saved:

- trigger a manual Bybit sync
- verify that transactions appear under Vodafone Cash numbers
- verify related business balances update as expected

## Suggested First Data Setup

For a meaningful first test, create:

- 1 admin user
- 1 Vodafone Cash number
- 1 bank account
- 1 retailer
- 1 collector

Then:

- assign the retailer to the collector
- run a Bybit sync if completed P2P orders exist

## Common Navigation

### Admin / Finance

Use the bottom navigation shell to reach:

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

### Collector

Collectors see a dedicated dashboard focused on:

- assigned retailers
- cash on hand
- deposits into bank accounts

## Troubleshooting

### App Opens But Login Does Not Reach The Right Dashboard

Check:

- the Firebase Auth account exists
- the user also has a matching record under `users/{uid}`
- the `role` field is one of `ADMIN`, `FINANCE`, `COLLECTOR`, or `OPERATOR`

### Firebase Connection Problems

Try:

```bash
flutter clean
flutter pub get
flutter run
```

Also verify:

- the project id matches your Firebase environment
- Realtime Database is enabled
- Authentication is enabled
- database rules allow authenticated access

### Bybit Sync Does Not Add Transactions

Check:

- the API key and secret are correct
- the key has the required P2P access
- the account has completed P2P orders
- there is at least one Vodafone Cash number in the app

### Duplicate Transactions

The app is designed to prevent duplicates using `bybitOrderId`.

If duplicates appear, inspect the `transactions` node and confirm whether the source data has inconsistent order IDs.

## What This App Actually Covers

This is not only a Vodafone-number tracker.

The current app includes:

- Vodafone Cash number tracking
- Bybit P2P synchronization
- bank balances
- retailer debt
- collector cash handling
- financial ledger tracking
- role-based access

## Where To Read Next

- `README.md` for the product overview
- `SETUP_GUIDE.md` for fuller environment setup
- `ARCHITECTURE.md` for how the app is wired
- `IMPLEMENTATION_GUIDE.md` for coding guidance
