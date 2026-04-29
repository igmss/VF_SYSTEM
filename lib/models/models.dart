// Models for the app

class MobileNumber {
  final String id;
  final String phoneNumber;
  final String? name;
  final bool isDefault;
  final DateTime createdAt;
  final DateTime lastUpdatedAt;
  final double initialBalance;

  // Limits
  final double inDailyLimit;
  final double inMonthlyLimit;
  final double outDailyLimit;
  final double outMonthlyLimit;

  // Usage (Now final for better safety)
  final double inDailyUsed;
  final double inMonthlyUsed;
  final double outDailyUsed;
  final double outMonthlyUsed;
  final double inTotalUsed;
  final double outTotalUsed;

  MobileNumber({
    required this.id,
    required this.phoneNumber,
    this.name,
    required this.isDefault,
    required this.createdAt,
    DateTime? lastUpdatedAt,
    this.initialBalance = 0.0,
    this.inDailyLimit = 0.0,
    this.inMonthlyLimit = 0.0,
    this.outDailyLimit = 0.0,
    this.outMonthlyLimit = 0.0,
    this.inDailyUsed = 0.0,
    this.inMonthlyUsed = 0.0,
    this.outDailyUsed = 0.0,
    this.outMonthlyUsed = 0.0,
    this.inTotalUsed = 0.0,
    this.outTotalUsed = 0.0,
  }) : lastUpdatedAt = lastUpdatedAt ?? createdAt;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'phoneNumber': phoneNumber,
      'name': name,
      'isDefault': isDefault,
      'createdAt': createdAt.toIso8601String(),
      'lastUpdatedAt': lastUpdatedAt.toIso8601String(),
      'initialBalance': initialBalance,
      'inDailyLimit': inDailyLimit,
      'inMonthlyLimit': inMonthlyLimit,
      'outDailyLimit': outDailyLimit,
      'outMonthlyLimit': outMonthlyLimit,
      'inDailyUsed': inDailyUsed,
      'inMonthlyUsed': inMonthlyUsed,
      'outDailyUsed': outDailyUsed,
      'outMonthlyUsed': outMonthlyUsed,
      'inTotalUsed': inTotalUsed,
      'outTotalUsed': outTotalUsed,
    };
  }

  factory MobileNumber.fromMap(Map<String, dynamic> map) {
    // Helper to safely get a double from dynamic value
    double asDouble(dynamic val) {
      if (val == null) return 0.0;
      if (val is num) return val.toDouble();
      if (val is String) return double.tryParse(val.replaceAll(',', '')) ?? 0.0;
      return 0.0;
    }

    return MobileNumber(
      id: map['id']?.toString() ?? '',
      phoneNumber: (map['phone_number'] ?? map['phoneNumber'])?.toString() ?? '',
      name: map['name']?.toString(),
      isDefault: (map['is_default'] ?? map['isDefault']) == true,
      createdAt: DateTime.tryParse((map['created_at'] ?? map['createdAt'])?.toString() ?? '') ?? DateTime.now(),
      lastUpdatedAt: (map['last_updated_at'] ?? map['lastUpdatedAt']) != null 
          ? DateTime.tryParse((map['last_updated_at'] ?? map['lastUpdatedAt']).toString()) 
          : null,
      initialBalance: asDouble(map['initial_balance'] ?? map['initialBalance']),
      inDailyLimit: asDouble(map['in_daily_limit'] ?? map['inDailyLimit'] ?? map['dailyLimit']),
      inMonthlyLimit: asDouble(map['in_monthly_limit'] ?? map['inMonthlyLimit'] ?? map['monthlyLimit']),
      outDailyLimit: asDouble(map['out_daily_limit'] ?? map['outDailyLimit'] ?? map['dailyLimit']),
      outMonthlyLimit: asDouble(map['out_monthly_limit'] ?? map['outMonthlyLimit'] ?? map['monthlyLimit']),
      inDailyUsed: asDouble(map['in_daily_used'] ?? map['inDailyUsed'] ?? map['dailyUsed']),
      inMonthlyUsed: asDouble(map['in_monthly_used'] ?? map['inMonthlyUsed'] ?? map['monthlyUsed']),
      outDailyUsed: asDouble(map['out_daily_used'] ?? map['outDailyUsed']),
      outMonthlyUsed: asDouble(map['out_monthly_used'] ?? map['outMonthlyUsed']),
      inTotalUsed: asDouble(map['in_total_used'] ?? map['inTotalUsed']),
      outTotalUsed: asDouble(map['out_total_used'] ?? map['outTotalUsed']),
    );
  }

  double get netDailyUsage => inDailyUsed - outDailyUsed;
  double get netMonthlyUsage => inMonthlyUsed - outMonthlyUsed;
  double get netTotalUsage => inTotalUsed - outTotalUsed;

  // Note: This accounts for ALL movements synced in the app!
  double get currentBalance => initialBalance + (inTotalUsed - outTotalUsed);

  MobileNumber copyWith({
    String? id,
    String? phoneNumber,
    String? name,
    bool? isDefault,
    DateTime? createdAt,
    DateTime? lastUpdatedAt,
    double? initialBalance,
    double? inDailyLimit,
    double? inMonthlyLimit,
    double? outDailyLimit,
    double? outMonthlyLimit,
    double? inDailyUsed,
    double? inMonthlyUsed,
    double? outDailyUsed,
    double? outMonthlyUsed,
    double? inTotalUsed,
    double? outTotalUsed,
  }) {
    return MobileNumber(
      id: id ?? this.id,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      name: name ?? this.name,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      initialBalance: initialBalance ?? this.initialBalance,
      inDailyLimit: inDailyLimit ?? this.inDailyLimit,
      inMonthlyLimit: inMonthlyLimit ?? this.inMonthlyLimit,
      outDailyLimit: outDailyLimit ?? this.outDailyLimit,
      outMonthlyLimit: outMonthlyLimit ?? this.outMonthlyLimit,
      inDailyUsed: inDailyUsed ?? this.inDailyUsed,
      inMonthlyUsed: inMonthlyUsed ?? this.inMonthlyUsed,
      outDailyUsed: outDailyUsed ?? this.outDailyUsed,
      outMonthlyUsed: outMonthlyUsed ?? this.outMonthlyUsed,
      inTotalUsed: inTotalUsed ?? this.inTotalUsed,
      outTotalUsed: outTotalUsed ?? this.outTotalUsed,
    );
  }
}

class CashTransaction {
  final String id;
  final String? phoneNumber;
  final double amount;
  final String currency;
  final DateTime timestamp;
  final String bybitOrderId;
  final String status;
  final String paymentMethod;
  final int side; // 0: Buy, 1: Sell
  final String chatHistory; // Summary of chat messages
  final double price;
  final double quantity;
  final String token; // e.g. USDT

  CashTransaction({
    required this.id,
    this.phoneNumber,
    required this.amount,
    required this.currency,
    required this.timestamp,
    required this.bybitOrderId,
    required this.status,
    required this.paymentMethod,
    required this.side,
    this.chatHistory = '',
    this.price = 0,
    this.quantity = 0,
    this.token = 'USDT',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'phoneNumber': phoneNumber,
      'amount': amount,
      'currency': currency,
      'timestamp': timestamp.toIso8601String(),
      'bybitOrderId': bybitOrderId,
      'status': status,
      'paymentMethod': paymentMethod,
      'side': side,
      'chatHistory': chatHistory,
      'price': price,
      'quantity': quantity,
      'token': token,
    };
  }

  factory CashTransaction.fromMap(Map<String, dynamic> map) {
    double asDouble(dynamic value) {
      if (value == null) return 0;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString().replaceAll(',', '')) ?? 0;
    }

    int asInt(dynamic value, {int fallback = 0}) {
      if (value == null) return fallback;
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString()) ?? fallback;
    }

    DateTime asDateTime(dynamic value) {
      if (value == null) return DateTime.now();
      if (value is DateTime) return value;
      final text = value.toString();
      final parsedDate = DateTime.tryParse(text);
      if (parsedDate != null) return parsedDate;
      final millis = int.tryParse(text);
      if (millis != null && millis > 0) {
        return DateTime.fromMillisecondsSinceEpoch(millis);
      }
      return DateTime.now();
    }

    return CashTransaction(
      id: map['id']?.toString() ?? '',
      phoneNumber: (map['phone_number'] ?? map['phoneNumber'])?.toString(),
      amount: asDouble(map['amount']),
      currency: map['currency']?.toString() ?? 'EGP',
      timestamp: asDateTime(map['timestamp']),
      bybitOrderId: (map['bybit_order_id'] ?? map['bybitOrderId'])?.toString() ?? '',
      status: map['status']?.toString() ?? 'pending',
      paymentMethod: (map['payment_method'] ?? map['paymentMethod'])?.toString() ?? 'Unknown',
      side: asInt(map['side'], fallback: 1),
      chatHistory: (map['chat_history'] ?? map['chatHistory'])?.toString() ?? '',
      price: asDouble(map['price']),
      quantity: asDouble(map['quantity']),
      token: map['token']?.toString() ?? 'USDT',
    );
  }
}

class BybitOrder {
  final String orderId;
  final double amount;
  final String currency;
  final String status;
  final DateTime createTime;
  final String paymentMethod;
  final int paymentType;
  final int side; // 0: Buy, 1: Sell
  final double price;
  final double quantity;
  final String token;

  BybitOrder({
    required this.orderId,
    required this.amount,
    required this.currency,
    required this.status,
    required this.createTime,
    required this.paymentMethod,
    required this.paymentType,
    required this.side,
    required this.price,
    required this.quantity,
    required this.token,
  });

  factory BybitOrder.fromJson(Map<String, dynamic> json) {
    final orderId = json['id']?.toString() ?? json['orderId']?.toString() ?? '';

    final amount = double.tryParse((json['amount'] ?? 0).toString()) ?? 0;
    final price = double.tryParse((json['price'] ?? 0).toString()) ?? 0;
    final quantity = double.tryParse((json['quantity'] ?? 0).toString()) ?? 0;
    final token = json['tokenId']?.toString() ?? json['tokenName']?.toString() ?? 'USDT';

    final currency = json['currencyId']?.toString() ?? 'EGP';
    final status = json['status']?.toString() ?? '';
    final side = int.tryParse(json['side']?.toString() ?? '1') ?? 1;

    final rawDate = json['createTime'] ?? 
                    json['createDate'] ?? 
                    json['updateTime'] ?? 
                    json['time'] ?? 
                    json['createdAt'];
                    
    DateTime createTime;
    if (rawDate == null) {
      createTime = DateTime.now();
    } else if (rawDate is int) {
      createTime = DateTime.fromMillisecondsSinceEpoch(rawDate);
    } else {
      final ms = int.tryParse(rawDate.toString()) ?? 0;
      createTime = ms > 0
          ? DateTime.fromMillisecondsSinceEpoch(ms)
          : DateTime.now();
    }

    String pmName = 'Unknown';
    int pmType = -1;

    final confirmed = json['confirmedPayTerm'];
    if (confirmed is Map) {
      pmType = confirmed['paymentType'] as int? ?? -1;
      final config = confirmed['paymentConfigVo'];
      if (config is Map) {
        pmName = config['paymentName']?.toString() ?? pmName;
      }
      final acc = confirmed['accountNo']?.toString() ?? confirmed['mobile']?.toString() ?? '';
      if (acc.isNotEmpty) pmName = '$pmName ($acc)';
    }

    if (pmName == 'Unknown') {
      pmName = json['paymentName']?.toString() ?? 
               json['paymentMethodName']?.toString() ?? 
               json['paymentMethod']?.toString() ?? 
               'Unknown';
    }
    if (pmType == -1) {
      pmType = int.tryParse(json['paymentType']?.toString() ?? '') ?? -1;
    }

    if (pmName == 'Unknown' && json['paymentTermList'] is List && (json['paymentTermList'] as List).isNotEmpty) {
      final first = json['paymentTermList'][0];
      if (first is Map) {
        pmType = first['paymentType'] as int? ?? pmType;
        final config = first['paymentConfigVo'];
        if (config is Map) {
          pmName = config['paymentName']?.toString() ?? pmName;
        }
        final acc = first['accountNo']?.toString() ?? first['mobile']?.toString() ?? '';
        if (acc.isNotEmpty) pmName = '$pmName ($acc)';
      }
    }

    return BybitOrder(
      orderId: orderId,
      amount: amount,
      currency: currency,
      status: status,
      createTime: createTime,
      paymentMethod: pmName,
      paymentType: pmType,
      side: side,
      price: price,
      quantity: quantity,
      token: token,
    );
  }
}
