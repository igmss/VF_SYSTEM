import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';

class DatabaseService {
  static const String _dbUrl =
      'https://vodatracking-default-rtdb.firebaseio.com';
  static const Duration _timeout = Duration(seconds: 15);

  // Use instance to avoid multiple initializations on Web
  final FirebaseDatabase _database = FirebaseDatabase.instance;

  static const String _numbersPath = 'mobile_numbers';
  static const String _transactionsPath = 'transactions';
  static const String _syncPath = 'sync_data';

  /// Add or update a mobile number
  Future<void> addMobileNumber(MobileNumber number) async {
    try {
      await _database
          .ref('$_numbersPath/${number.id}')
          .set(number.toMap())
          .timeout(_timeout, onTimeout: () {
        throw Exception(
            'Timeout: Could not write to Firebase. Check your internet connection and database security rules.');
      });
    } on Exception {
      rethrow;
    } catch (e) {
      throw Exception('Error adding mobile number: $e');
    }
  }

  /// Stream all mobile numbers
  Stream<List<MobileNumber>> streamMobileNumbers() {
    return _database.ref(_numbersPath).onValue.map((event) {
      final snapshot = event.snapshot;
      if (snapshot.exists && snapshot.value != null && snapshot.value is Map) {
        final data = snapshot.value as Map;
        final List<MobileNumber> numbers = [];
        data.forEach((key, value) {
          if (value is Map) {
            numbers.add(MobileNumber.fromMap(Map<String, dynamic>.from(value)));
          }
        });
        return numbers;
      }
      return [];
    });
  }

  /// Get all mobile numbers
  Future<List<MobileNumber>> getMobileNumbers() async {
    try {
      final snapshot =
          await _database.ref(_numbersPath).get().timeout(_timeout);

      if (snapshot.exists && snapshot.value != null && snapshot.value is Map) {
        final data = snapshot.value as Map;
        final List<MobileNumber> numbers = [];
        data.forEach((key, value) {
          if (value is Map) {
            numbers.add(MobileNumber.fromMap(
                Map<String, dynamic>.from(value)));
          }
        });
        return numbers;
      }
      return [];
    } catch (e) {
      // Non-fatal: return empty list so the app still loads
      print('Warning: could not load mobile numbers: $e');
      return [];
    }
  }

  /// Get default mobile number
  Future<MobileNumber?> getDefaultNumber() async {
    try {
      final numbers = await getMobileNumbers();
      if (numbers.isEmpty) return null;

      final defaultNumbers = numbers.where((n) => n.isDefault).toList();
      if (defaultNumbers.isNotEmpty) return defaultNumbers.first;

      return numbers.first;
    } catch (e) {
      return null;
    }
  }

  /// Set default mobile number
  Future<void> setDefaultNumber(String numberId) async {
    try {
      final numbers = await getMobileNumbers();

      for (var number in numbers) {
        await _database
            .ref('$_numbersPath/${number.id}/isDefault')
            .set(number.id == numberId)
            .timeout(_timeout);
      }
    } catch (e) {
      throw Exception('Error setting default number: $e');
    }
  }

  /// Delete mobile number
  Future<void> deleteMobileNumber(String numberId) async {
    try {
      await _database
          .ref('$_numbersPath/$numberId')
          .remove()
          .timeout(_timeout);
    } catch (e) {
      throw Exception('Error deleting mobile number: $e');
    }
  }

  /// Add transaction (with duplicate prevention)
  Future<bool> addTransaction(CashTransaction transaction) async {
    try {
      // Check if transaction already exists (by bybitOrderId)
      final existingTx =
          await _getTransactionByBybitOrderId(transaction.bybitOrderId);

      if (existingTx != null) {
        print('Transaction already exists: ${transaction.bybitOrderId}');
        return false; // Duplicate prevented
      }

      // Add new transaction
      await _database
          .ref('$_transactionsPath/${transaction.id}')
          .set(transaction.toMap())
          .timeout(_timeout);

      // Update mobile number usage if assigned
      if (transaction.phoneNumber != null) {
        await _updateNumberUsage(transaction.phoneNumber!);
      }

      return true; // New transaction added
    } catch (e) {
      throw Exception('Error adding transaction: $e');
    }
  }

  /// Get transaction by Bybit Order ID
  Future<CashTransaction?> _getTransactionByBybitOrderId(
      String bybitOrderId) async {
    try {
      final snapshot = await _database
          .ref(_transactionsPath)
          .orderByChild('bybitOrderId')
          .equalTo(bybitOrderId)
          .get()
          .timeout(_timeout);

      if (snapshot.exists && snapshot.value != null && snapshot.value is Map) {
        final data = snapshot.value as Map;
        final firstEntryValue = data.values.first;
        if (firstEntryValue is Map) {
          return CashTransaction.fromMap(
              Map<String, dynamic>.from(firstEntryValue));
        }
      }
      return null;
    } catch (e) {
      print('Error checking duplicate: $e');
      return null;
    }
  }

  /// Stream all transactions for a number
  Stream<List<CashTransaction>> streamTransactionsForNumber(String phoneNumber) {
    return _database
        .ref(_transactionsPath)
        .orderByChild('phoneNumber')
        .equalTo(phoneNumber)
        .onValue
        .map((event) {
      final snapshot = event.snapshot;
      if (snapshot.exists && snapshot.value != null && snapshot.value is Map) {
        final data = snapshot.value as Map;
        final List<CashTransaction> results = [];
        data.forEach((key, value) {
          if (value is Map) {
            results.add(CashTransaction.fromMap(Map<String, dynamic>.from(value)));
          }
        });
        return results..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      }
      return [];
    });
  }

  /// Get all transactions for a number
  Future<List<CashTransaction>> getTransactionsForNumber(
      String phoneNumber) async {
    try {
      final snapshot = await _database
          .ref(_transactionsPath)
          .orderByChild('phoneNumber')
          .equalTo(phoneNumber)
          .get()
          .timeout(_timeout);

      if (snapshot.exists && snapshot.value != null && snapshot.value is Map) {
        final data = snapshot.value as Map;
        final List<CashTransaction> results = [];
        data.forEach((key, value) {
          if (value is Map) {
            results.add(CashTransaction.fromMap(
                Map<String, dynamic>.from(value)));
          }
        });
        return results..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      }
      return [];
    } catch (e) {
      throw Exception('Error fetching transactions: $e');
    }
  }

  /// Stream all transactions
  Stream<List<CashTransaction>> streamAllTransactions() {
    return _database.ref(_transactionsPath).onValue.map((event) {
      final snapshot = event.snapshot;
      if (snapshot.exists && snapshot.value != null && snapshot.value is Map) {
        final data = snapshot.value as Map;
        final List<CashTransaction> results = [];
        data.forEach((key, value) {
          if (value is Map) {
            results.add(CashTransaction.fromMap(Map<String, dynamic>.from(value)));
          }
        });
        return results..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      }
      return [];
    });
  }

  /// Get all transactions
  Future<List<CashTransaction>> getAllTransactions() async {
    try {
      final snapshot = await _database
          .ref(_transactionsPath)
          .get()
          .timeout(_timeout);

      if (snapshot.exists && snapshot.value != null && snapshot.value is Map) {
        final data = snapshot.value as Map;
        final List<CashTransaction> results = [];
        data.forEach((key, value) {
          if (value is Map) {
            results.add(CashTransaction.fromMap(
                Map<String, dynamic>.from(value)));
          }
        });
        return results..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      }
      return [];
    } catch (e) {
      print('Warning: could not load transactions: $e');
      return [];
    }
  }

  /// Public: recalculate dailyUsed/monthlyUsed for a number from stored
  /// transactions. Call after reload or deleting transactions.
  Future<void> recalculateUsageForNumber(String phoneNumber) =>
      _updateNumberUsage(phoneNumber);

  /// Recalculate dailyUsed and monthlyUsed for a number by summing
  /// actual stored transactions filtered by their real timestamp.
  Future<void> _updateNumberUsage(String phoneNumber) async {
    try {
      final numbers = await getMobileNumbers();
      final matching = numbers.where((n) => n.phoneNumber == phoneNumber).toList();
      if (matching.isEmpty) return;
      final number = matching.first;

      // Load all transactions for this number
      final allTx = await getTransactionsForNumber(phoneNumber);

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final monthStart = DateTime(now.year, now.month, 1);

      double inDailyUsed = 0;
      double outDailyUsed = 0;
      double inMonthlyUsed = 0;
      double outMonthlyUsed = 0;
      double inTotalUsed = 0;
      double outTotalUsed = 0;

      for (final tx in allTx) {
        if (tx.status != 'completed') continue;

        final pmLow = tx.paymentMethod.toLowerCase();
        final isValidVoda = pmLow.contains('vodafone') || pmLow.contains('voda') || pmLow.contains('vf ');
        if (!isValidVoda) continue;

        // side 1: SELL (Incoming), side 0: BUY (Outgoing)
        final isIncoming = tx.side == 1;
        final amount = tx.amount;

        // All-Time
        if (isIncoming) {
          inTotalUsed += amount;
        } else {
          outTotalUsed += amount;
        }

        // Daily
        if (!tx.timestamp.isBefore(todayStart)) {
          if (isIncoming) {
            inDailyUsed += amount;
          } else {
            outDailyUsed += amount;
          }
        }
        // Monthly
        if (!tx.timestamp.isBefore(monthStart)) {
          if (isIncoming) {
            inMonthlyUsed += amount;
          } else {
            outMonthlyUsed += amount;
          }
        }
      }

      final updated = number.copyWith(
        inDailyUsed: inDailyUsed,
        outDailyUsed: outDailyUsed,
        inMonthlyUsed: inMonthlyUsed,
        outMonthlyUsed: outMonthlyUsed,
        inTotalUsed: inTotalUsed,
        outTotalUsed: outTotalUsed,
        lastUpdatedAt: now,
      );

      await _database
          .ref('$_numbersPath/${number.id}')
          .set(updated.toMap())
          .timeout(_timeout);
    } catch (e) {
      print('Error recalculating number usage: $e');
    }
  }


  /// Get the createTime (ms) of the newest order that has been synced.
  /// This is used as `beginTime` for the next incremental sync.
  Future<int> getLastSyncedOrderTimestamp() async {
    try {
      final snapshot = await _database
          .ref('$_syncPath/lastSyncedOrderTs')
          .get()
          .timeout(_timeout);
      return (snapshot.value as int?) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// Persist the createTime of the newest synced order.
  Future<void> saveLastSyncedOrderTimestamp(int ts) async {
    try {
      await _database
          .ref('$_syncPath/lastSyncedOrderTs')
          .set(ts)
          .timeout(_timeout);
    } catch (e) {
      print('Error saving lastSyncedOrderTs: $e');
    }
  }

  /// Get when the last sync ran (wall-clock DateTime, for UI display).
  Future<DateTime?> getLastSyncTime() async {
    try {
      final snapshot = await _database
          .ref('$_syncPath/lastSyncTime')
          .get()
          .timeout(_timeout);
      final ms = snapshot.value as int?;
      return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
    } catch (e) {
      return null;
    }
  }

  /// Persist the wall-clock time of the last sync.
  Future<void> saveLastSyncTime(int ms) async {
    try {
      await _database
          .ref('$_syncPath/lastSyncTime')
          .set(ms)
          .timeout(_timeout);
    } catch (e) {
      print('Error saving lastSyncTime: $e');
    }
  }

  // Backward-compat aliases
  Future<int> getLastSyncTimestamp() => getLastSyncedOrderTimestamp();
  Future<void> updateLastSyncTimestamp(int ts) =>
      saveLastSyncedOrderTimestamp(ts);


  /// Reset daily usage for all numbers
  Future<void> resetDailyUsage() async {
    try {
      final numbers = await getMobileNumbers();
      for (var number in numbers) {
        await _database
            .ref('$_numbersPath/${number.id}/dailyUsed')
            .set(0)
            .timeout(_timeout);
      }
    } catch (e) {
      print('Error resetting daily usage: $e');
    }
  }

  /// Reset monthly usage for all numbers
  Future<void> resetMonthlyUsage() async {
    try {
      final numbers = await getMobileNumbers();
      for (var number in numbers) {
        await _database
            .ref('$_numbersPath/${number.id}/monthlyUsed')
            .set(0)
            .timeout(_timeout);
      }
    } catch (e) {
      print('Error resetting monthly usage: $e');
    }
  }

  /// Wipe all transactions and reset sync markers
  Future<void> deleteAllTransactions() async {
    try {
      await _database.ref(_transactionsPath).remove().timeout(_timeout);
      await resetSyncMarkers();
    } catch (e) {
      throw Exception('Error deleting all transactions: $e');
    }
  }

  /// Reset sync markers (so next sync starts fresh)
  Future<void> resetSyncMarkers() async {
    try {
      await _database.ref(_syncPath).remove().timeout(_timeout);
    } catch (e) {
      print('Error resetting sync markers: $e');
    }
  }
}
