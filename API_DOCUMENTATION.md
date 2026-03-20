# API Documentation

## Bybit P2P API Integration

### Overview

The app integrates with Bybit's P2P API to fetch completed orders and track them against mobile numbers.

### Base URL

```
https://api2.bybit.com
```

### Authentication

All requests require the API key in headers:

```
X-BYBIT-API-KEY: your_api_key
Content-Type: application/json
```

### Endpoints Used

#### 1. Get Completed Orders

**Endpoint:** `GET /v5/otc/order-list`

**Parameters:**
- `status` (string): Filter by status - `completed`
- `limit` (integer): Number of orders to fetch (default: 50, max: 50)
- `offset` (integer): Pagination offset (default: 0)

**Example Request:**
```bash
curl -X GET "https://api2.bybit.com/v5/otc/order-list?status=completed&limit=50&offset=0" \
  -H "X-BYBIT-API-KEY: your_api_key"
```

**Response:**
```json
{
  "retCode": 0,
  "retMsg": "success",
  "result": {
    "items": [
      {
        "orderId": "order_123456",
        "amount": "250",
        "fiatCurrency": "USD",
        "orderStatus": "completed",
        "createTime": "2024-01-15T10:30:00Z"
      }
    ],
    "count": 1
  }
}
```

**Response Fields:**
- `orderId` (string): Unique order identifier
- `amount` (string): Order amount
- `fiatCurrency` (string): Currency code (USD, EUR, etc.)
- `orderStatus` (string): Order status
- `createTime` (string): ISO 8601 timestamp

#### 2. Get Order Details

**Endpoint:** `GET /v5/otc/order-detail`

**Parameters:**
- `orderId` (string): Order ID to fetch

**Example Request:**
```bash
curl -X GET "https://api2.bybit.com/v5/otc/order-detail?orderId=order_123456" \
  -H "X-BYBIT-API-KEY: your_api_key"
```

**Response:**
```json
{
  "retCode": 0,
  "retMsg": "success",
  "result": {
    "orderId": "order_123456",
    "amount": "250",
    "fiatCurrency": "USD",
    "orderStatus": "completed",
    "createTime": "2024-01-15T10:30:00Z"
  }
}
```

### Error Handling

**Common Error Codes:**

| Code | Message | Solution |
|------|---------|----------|
| 0 | Success | No action needed |
| 10001 | Invalid API key | Verify API key is correct |
| 10002 | API key expired | Generate new API key |
| 10003 | Insufficient permissions | Enable P2P permissions |
| 10004 | Rate limit exceeded | Wait before retrying |
| 10005 | Invalid parameters | Check request parameters |

**Error Response:**
```json
{
  "retCode": 10001,
  "retMsg": "Invalid API key",
  "result": null
}
```

### Rate Limiting

- **Limit:** 10 requests per second
- **Burst:** 20 requests per minute
- **Retry:** Implement exponential backoff

### Implementation in App

```dart
class BybitService {
  Future<List<BybitOrder>> getCompletedOrders({
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final url = Uri.parse(
        '$baseUrl/v5/otc/order-list?status=completed&limit=$limit&offset=$offset',
      );

      final response = await http.get(
        url,
        headers: {
          'X-BYBIT-API-KEY': apiKey,
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['retCode'] == 0 && data['result'] != null) {
          final orders = (data['result']['items'] as List)
              .map((order) => BybitOrder.fromJson(order))
              .toList();
          return orders;
        } else {
          throw Exception('API Error: ${data['retMsg']}');
        }
      } else {
        throw Exception('Failed to fetch orders: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching Bybit orders: $e');
    }
  }
}
```

---

## Firebase Realtime Database API

### Overview

The app uses Firebase Realtime Database to store mobile numbers, transactions, and sync data.

### Database Structure

```
{
  "mobile_numbers": {
    "number_id_1": { ... }
  },
  "transactions": {
    "tx_id_1": { ... }
  },
  "sync_data": {
    "lastSync": 1705318200000
  }
}
```

### Collections

#### 1. Mobile Numbers

**Path:** `/mobile_numbers/{numberId}`

**Schema:**
```json
{
  "id": "uuid",
  "phoneNumber": "+20123456789",
  "dailyLimit": 1000,
  "monthlyLimit": 30000,
  "dailyUsed": 250,
  "monthlyUsed": 5000,
  "isDefault": true,
  "createdAt": "2024-01-15T10:30:00Z"
}
```

**Operations:**

Create:
```dart
await _database
    .ref('mobile_numbers/$numberId')
    .set(number.toMap());
```

Read:
```dart
final snapshot = await _database.ref('mobile_numbers').get();
```

Update:
```dart
await _database
    .ref('mobile_numbers/$numberId/dailyUsed')
    .set(250);
```

Delete:
```dart
await _database.ref('mobile_numbers/$numberId').remove();
```

#### 2. Transactions

**Path:** `/transactions/{transactionId}`

**Schema:**
```json
{
  "id": "uuid",
  "phoneNumber": "+20123456789",
  "amount": 250,
  "currency": "USD",
  "timestamp": "2024-01-15T10:30:00Z",
  "bybitOrderId": "order_123456",
  "status": "completed"
}
```

**Indexes Required:**
```json
{
  "transactions": {
    ".indexOn": ["phoneNumber", "bybitOrderId", "timestamp"]
  }
}
```

**Query Examples:**

Get all transactions for a number:
```dart
final snapshot = await _database
    .ref('transactions')
    .orderByChild('phoneNumber')
    .equalTo('+20123456789')
    .get();
```

Get transaction by Bybit Order ID:
```dart
final snapshot = await _database
    .ref('transactions')
    .orderByChild('bybitOrderId')
    .equalTo('order_123456')
    .limitToFirst(1)
    .get();
```

#### 3. Sync Data

**Path:** `/sync_data/lastSync`

**Schema:**
```json
{
  "lastSync": 1705318200000
}
```

**Operations:**

Get last sync:
```dart
final snapshot = await _database.ref('sync_data/lastSync').get();
final timestamp = snapshot.value as int? ?? 0;
```

Update last sync:
```dart
await _database.ref('sync_data/lastSync').set(
  DateTime.now().millisecondsSinceEpoch
);
```

### Security Rules

```json
{
  "rules": {
    ".read": "auth != null",
    ".write": "auth != null",
    "mobile_numbers": {
      ".indexOn": ["phoneNumber", "isDefault"],
      ".validate": "newData.hasChildren(['phoneNumber', 'dailyLimit', 'monthlyLimit'])"
    },
    "transactions": {
      ".indexOn": ["phoneNumber", "bybitOrderId", "timestamp"],
      ".validate": "newData.hasChildren(['phoneNumber', 'amount', 'bybitOrderId'])"
    }
  }
}
```

### Implementation in App

```dart
class DatabaseService {
  final FirebaseDatabase _database = FirebaseDatabase.instance;

  // Add mobile number
  Future<void> addMobileNumber(MobileNumber number) async {
    await _database
        .ref('mobile_numbers/${number.id}')
        .set(number.toMap());
  }

  // Get all mobile numbers
  Future<List<MobileNumber>> getMobileNumbers() async {
    final snapshot = await _database.ref('mobile_numbers').get();
    
    if (snapshot.exists) {
      final data = snapshot.value as Map;
      return data.entries
          .map((e) => MobileNumber.fromMap(Map<String, dynamic>.from(e.value)))
          .toList();
    }
    return [];
  }

  // Add transaction with duplicate prevention
  Future<bool> addTransaction(Transaction transaction) async {
    // Check if exists
    final existingTx = await _getTransactionByBybitOrderId(transaction.bybitOrderId);
    
    if (existingTx != null) {
      return false; // Duplicate
    }

    // Add new
    await _database
        .ref('transactions/${transaction.id}')
        .set(transaction.toMap());
    
    return true; // Added
  }

  // Get transaction by Bybit Order ID
  Future<Transaction?> _getTransactionByBybitOrderId(String bybitOrderId) async {
    final snapshot = await _database
        .ref('transactions')
        .orderByChild('bybitOrderId')
        .equalTo(bybitOrderId)
        .get();

    if (snapshot.exists) {
      final data = snapshot.value as Map;
      final firstEntry = data.entries.first;
      return Transaction.fromMap(Map<String, dynamic>.from(firstEntry.value));
    }
    return null;
  }
}
```

---

## Data Models

### MobileNumber

```dart
class MobileNumber {
  final String id;
  final String phoneNumber;
  final double dailyLimit;
  final double monthlyLimit;
  final bool isDefault;
  final DateTime createdAt;
  double dailyUsed;
  double monthlyUsed;
}
```

### Transaction

```dart
class Transaction {
  final String id;
  final String phoneNumber;
  final double amount;
  final String currency;
  final DateTime timestamp;
  final String bybitOrderId;
  final String status;
}
```

### BybitOrder

```dart
class BybitOrder {
  final String orderId;
  final double amount;
  final String currency;
  final String status;
  final DateTime createTime;
}
```

---

## Error Handling

### Exception Types

```dart
// Network error
throw NetworkException(message: 'Connection failed');

// API error
throw ApiException(
  message: 'API request failed',
  statusCode: 401,
);

// Database error
throw DatabaseException(message: 'Database operation failed');

// Validation error
throw ValidationException(message: 'Invalid input');
```

### Retry Logic

```dart
Future<T> retryWithBackoff<T>(
  Future<T> Function() operation, {
  int maxRetries = 3,
}) async {
  for (int i = 0; i < maxRetries; i++) {
    try {
      return await operation();
    } catch (e) {
      if (i == maxRetries - 1) rethrow;
      
      // Exponential backoff
      await Future.delayed(Duration(seconds: 2 ^ i));
    }
  }
  throw Exception('Max retries exceeded');
}
```

---

## Best Practices

### 1. API Calls

✅ Always use timeout
✅ Implement retry logic
✅ Log requests/responses
✅ Handle errors gracefully

### 2. Database Operations

✅ Use indexes for queries
✅ Validate data before writing
✅ Implement duplicate prevention
✅ Monitor database size

### 3. Security

✅ Never hardcode API keys
✅ Use environment variables
✅ Validate all inputs
✅ Implement proper authentication

### 4. Performance

✅ Batch operations
✅ Use pagination
✅ Cache results
✅ Optimize queries

---

## Troubleshooting

### API Issues

**Problem:** 401 Unauthorized
- Check API key is correct
- Verify API key has P2P permissions
- Check API key is not expired

**Problem:** 429 Rate Limited
- Implement exponential backoff
- Reduce request frequency
- Batch requests

**Problem:** Timeout
- Check internet connection
- Increase timeout duration
- Retry with backoff

### Database Issues

**Problem:** Data not appearing
- Check Firebase rules
- Verify authentication
- Check database path
- Review indexes

**Problem:** Slow queries
- Add indexes
- Limit query results
- Use pagination
- Optimize data structure

---

**Last Updated:** February 2026
**API Version:** v5
**Database:** Firebase Realtime DB
