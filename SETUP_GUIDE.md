# Setup Guide

## Purpose

This guide covers a fuller setup for the current Vodafone Distribution System, including Firebase, app login, Bybit credentials, and the initial business records needed to make the app useful.

## 1. Local Tooling

Install or verify:

```bash
flutter --version
dart --version
```

Recommended local tools:

- Flutter SDK
- Android Studio or Xcode
- Firebase CLI
- FlutterFire CLI if you want to regenerate Firebase bindings

## 2. Firebase Project Setup

### 2.1 Use The Existing Project Or Rebind

This repo is currently configured for:

- Firebase project id: `vodatracking`

You can see that in:

- `.firebaserc`
- `firebase.json`
- `lib/firebase_options.dart`

If you plan to use a different project, regenerate the Firebase bindings and review all generated outputs.

### 2.2 Enable Authentication

In Firebase Console:

1. Open Authentication
2. Enable Email/Password sign-in

### 2.3 Enable Realtime Database

In Firebase Console:

1. Open Realtime Database
2. Create the database if needed
3. Choose your region

### 2.4 Apply Database Rules

This repo stores database rules in:

- `database.rules.json`

Deploy or paste rules from that file instead of using the older sample rules from previous docs.

If you want to deploy from the CLI:

```bash
firebase deploy --only database
```

## 3. Optional Firebase Functions Setup

The repo includes a scheduled Cloud Function in `functions/index.js` that resets daily Vodafone-number usage counters.

To work with the functions project:

```bash
cd functions
npm install
```

Useful commands:

```bash
npm run serve
npm run deploy
```

Function requirements:

- Node.js 20
- Firebase project with billing/features required for scheduled functions

## 4. Flutter App Setup

### 4.1 Install Dependencies

From the project root:

```bash
flutter pub get
```

### 4.2 Regenerate Firebase Bindings If Needed

Only do this if you are changing Firebase projects or refreshing generated config:

```bash
flutterfire configure --project=<your-project-id>
```

### 4.3 Run On A Device

```bash
flutter devices
flutter run
```

## 5. Create Your First Login

The app needs both:

- a Firebase Authentication user
- a matching profile under the Realtime Database `users/` node

### Option A: Create A User Directly In Firebase Console

1. Create an Email/Password user in Authentication
2. Copy that user's UID
3. Create `users/{uid}` in Realtime Database with a payload like:

```json
{
  "uid": "your-auth-uid",
  "email": "admin@example.com",
  "name": "Admin User",
  "role": "ADMIN",
  "isActive": true,
  "createdAt": "2026-03-19T00:00:00.000Z"
}
```

### Option B: Use An Existing Admin From The App

Once one admin exists, additional users can be created from the app's user-management screen. The code writes both the auth account and the matching database record.

## 6. First Business Data To Seed

After your first admin login, create these records from the UI:

### 6.1 Vodafone Cash Number

Add at least one mobile number with:

- phone number
- initial balance
- inbound daily/monthly limits
- outbound daily/monthly limits

### 6.2 Bank Account

Create at least one bank account with:

- bank name
- account holder
- account number
- optional opening balance

### 6.3 Retailer

Create at least one retailer so distribution and collection flows can be tested.

### 6.4 Collector

Create a collector user or collector record so collector workflows can be tested.

Assign at least one retailer to that collector.

## 7. Bybit API Setup

### 7.1 Create API Credentials

In Bybit:

1. Open API management
2. Create a key with the required P2P read access
3. Save the API key and secret securely

### 7.2 Save Credentials In The App

Do not hardcode Bybit credentials in `main.dart`.

The current app stores them through the settings UI using local device storage.

Open the app settings and save:

- API key
- API secret

## 8. Verify The Main Flows

### 8.1 Admin Verification

Confirm you can access:

- overview
- Vodafone Cash numbers
- banks
- USD exchange
- retailers
- collectors
- ledger
- users
- settings

### 8.2 Collector Verification

Create or sign in as a collector-role user and confirm access to:

- assigned retailers
- cash on hand
- deposit workflow

### 8.3 Bybit Sync Verification

After saving credentials:

1. run a manual sync
2. verify new Vodafone transactions appear
3. verify duplicate sync attempts do not create duplicate rows

## 9. Production Considerations

### Secrets

Current behavior:

- Bybit credentials are stored locally with app preferences

If you harden the app for production later, consider migrating secrets to a more secure client-side storage approach and reviewing your overall secret-handling strategy.

### Roles

Before production, decide:

- who should be `ADMIN`
- who should be `FINANCE`
- who should be `COLLECTOR`
- whether `OPERATOR` should have its own distinct shell or tighter tab restrictions

### Database Safety

Verify:

- rules in `database.rules.json` are appropriate for your environment
- only authorized users can read and write required nodes
- indexes support your frequently used queries

## 10. Troubleshooting

### Login Works But Features Look Empty

Possible causes:

- missing `users/{uid}` profile
- no seeded business data yet
- collector has no assigned retailers

### Firebase Errors On Startup

Check:

- Firebase project configuration matches the environment
- Realtime Database is enabled
- Authentication is enabled
- rules are deployed

### Bybit Errors

Check:

- credentials entered in settings are correct
- Bybit account has the required permissions
- network access from the device works

### Daily Usage Does Not Reset

Check:

- the Cloud Function is deployed if you rely on server-side reset
- or the client-side fallback behavior in the app

The scheduled function uses the `Africa/Cairo` timezone.

## 11. Useful Project Files

- `README.md`
- `ARCHITECTURE.md`
- `IMPLEMENTATION_GUIDE.md`
- `database.rules.json`
- `firebase.json`
- `.firebaserc`
- `functions/index.js`

## 12. Recommended Next Step

After setup is complete, walk through the app in this order:

1. login as admin
2. add a Vodafone Cash number
3. add a bank account
4. add a retailer
5. add a collector
6. assign retailer to collector
7. save Bybit credentials
8. run sync
9. review ledger and balances
