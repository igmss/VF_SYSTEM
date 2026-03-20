import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../models/models.dart';

class BybitService {
  // Bybit V5 unified API base URL
  static const String _baseUrl = 'https://api.bybit.com';
  static const int _pageSize = 20;

  final String apiKey;
  final String apiSecret;

  BybitService({required this.apiKey, required this.apiSecret});

  // ── Time Synchronization ──────────────────────────────────────────────────
  static int _timeOffsetMs = 0;

  /// Fetches Bybit's true server time and calculates the offset to our local clock.
  /// Must be called before initiating any API requests if the local clock is drifting.
  Future<void> syncServerTime() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/v5/market/time')).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final nanoStr = data['result']?['timeNano'] as String?;
        if (nanoStr != null) {
          final serverMs = int.parse(nanoStr) ~/ 1000000;
          _timeOffsetMs = serverMs - DateTime.now().millisecondsSinceEpoch;
          print('Bybit: Synced server time. Offset is $_timeOffsetMs ms.');
        }
      }
    } catch (e) {
      print('Bybit: Failed to sync server time: $e');
    }
  }

  // ── HMAC-SHA256 signing ───────────────────────────────────────────────────
  //
  // For POST requests Bybit V5 signs:
  //   timestamp + apiKey + recvWindow + rawJsonBody
  //
  String _sign(String payload) {
    final hmac = Hmac(sha256, utf8.encode(apiSecret));
    return hmac.convert(utf8.encode(payload)).toString();
  }

  Map<String, String> _postHeaders(String jsonBody) {
    // Apply the offset synchronously
    final nowMs = DateTime.now().millisecondsSinceEpoch + _timeOffsetMs;
    final ts = nowMs.toString();
    const recv = '30000'; // Increased recv window to 30s
    final sig = _sign('$ts$apiKey$recv$jsonBody');
    return {
      'X-BAPI-API-KEY': apiKey,
      'X-BAPI-TIMESTAMP': ts,
      'X-BAPI-SIGN': sig,
      'X-BAPI-RECV-WINDOW': recv,
      'Content-Type': 'application/json',
    };
  }

  // ── Fetch a single page of completed P2P orders ───────────────────────────

  Future<_PageResult> _fetchPage({
    required int page,
    int? beginTime,
    int? endTime,
  }) async {
    // Bybit P2P uses POST with JSON body
    final body = <String, dynamic>{
      'page': page,
      'size': _pageSize,
      'status': '50', // 50 = completed
    };
    if (beginTime != null) {
      body['beginTime'] = beginTime.toString();
      body['startTime'] = beginTime.toString(); // Standard V5 name
    }
    if (endTime != null) {
      body['endTime'] = endTime.toString();
    }

    final jsonBody = jsonEncode(body);
    final uri = Uri.parse('$_baseUrl/v5/p2p/order/simplifyList');

    print('Bybit API Request: $uri Body: $jsonBody');

    http.Response response;
    try {
      response = await http
          .post(uri, headers: _postHeaders(jsonBody), body: jsonBody)
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      throw Exception('Network error contacting Bybit: $e');
    }

    if (response.statusCode != 200) {
      throw Exception(
          'HTTP ${response.statusCode} from Bybit. Body: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final retCode = data['ret_code'] ?? data['retCode'] ?? -1;

    if (retCode != 0) {
      final msg = data['ret_msg'] ?? data['retMsg'] ?? 'Unknown Bybit error';
      throw Exception('Bybit API error ($retCode): $msg');
    }

    final result = data['result'] as Map<String, dynamic>? ?? {};

    // Response items may be under 'items', 'list', or 'result' directly
    List<dynamic> rawItems = [];
    if (result['items'] is List) rawItems = result['items'] as List;
    else if (result['list'] is List) rawItems = result['list'] as List;
    else if (result['result'] is List) rawItems = result['result'] as List;

    final orders = rawItems
        .map((e) => BybitOrder.fromJson(e as Map<String, dynamic>))
        .toList();

    final count = int.tryParse('${result['count'] ?? result['total'] ?? 0}') ?? 0;
    return _PageResult(orders: orders, total: count);
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Fetch completed P2P orders, then filter client-side to only those at or
  /// after [beginTime] (unix ms).
  Future<List<BybitOrder>> getAllOrdersSince({
    int? beginTime,
    void Function(int page, int fetched)? onProgress,
  }) async {
    final all = <BybitOrder>[];
    int page = 1;

    while (true) {
      // Pass beginTime to Bybit API for server-side filtering
      final result = await _fetchPage(page: page, beginTime: beginTime);
      
      if (result.orders.isEmpty) {
        print('Bybit: Page $page is empty. Breaking.');
        break;
      }

      all.addAll(result.orders);
      onProgress?.call(page, all.length);

      // Bybit returns orders sorted descending (newest first).
      // If the last order on this page is already older than our beginTime,
      // we can stop fetching further pages.
      if (beginTime != null && result.orders.isNotEmpty) {
        final lastOrderTs = result.orders.last.createTime.millisecondsSinceEpoch;
        if (lastOrderTs < beginTime) {
          print('Bybit: Last order on page $page ($lastOrderTs) is older than beginTime ($beginTime). Early exit.');
          break;
        }
      }

      if (result.orders.length < _pageSize) break; // last page
      page++;
      if (page > 100) break; // safety cap
    }

    print('Bybit: Fetched ${all.length} total raw orders. Applying client-side filter...');

    // Client-side date filter — reliable regardless of Bybit's sort order
    final filtered = beginTime == null
        ? all
        : all.where((o) {
            final pass = o.createTime.millisecondsSinceEpoch >= beginTime;
            if (!pass) {
               print('Bybit: Filtering out old order ${o.orderId} (TS: ${o.createTime.millisecondsSinceEpoch} < $beginTime)');
            }
            return pass;
          }).toList();

    // Sort oldest-first so timestamps are written in order
    filtered.sort((a, b) => a.createTime.compareTo(b.createTime));
    return filtered;
  }

  /// Fetch details of a single order by ID.
  Future<BybitOrder?> getOrderById(String orderId) async {
    final jsonBody = jsonEncode({'orderId': orderId});
    final uri = Uri.parse('$_baseUrl/v5/p2p/order/info');
    try {
      final response = await http
          .post(uri, headers: _postHeaders(jsonBody), body: jsonBody)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if ((data['ret_code'] ?? data['retCode']) == 0 &&
            data['result'] != null) {
          return BybitOrder.fromJson(data['result'] as Map<String, dynamic>);
        }
      }
    } catch (e) {
      print('Error fetching order $orderId: $e');
    }
    return null;
  }

  // ── Chat messages ─────────────────────────────────────────────────────────

  /// Fetch one page of chat messages for an order.
  Future<List<BybitChatMessage>> getChatMessages(
    String orderId, {
    int page = 1,
    int size = 30,
  }) async {
    final jsonBody = jsonEncode({
      'orderId': orderId,
      'currentPage': page.toString(),
      'size': size.toString(),
    });
    final uri = Uri.parse('$_baseUrl/v5/p2p/order/message/listpage');
    try {
      final response = await http
          .post(uri, headers: _postHeaders(jsonBody), body: jsonBody)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final retCode = data['ret_code'] ?? data['retCode'] ?? -1;
        if (retCode == 0) {
          // Result is nested: result.result (per Bybit docs)
          final outer = data['result'];
          // print('Bybit: Chat API response for $orderId: ${jsonEncode(data)}');
          
          List<dynamic> items = [];
          if (outer is Map && outer['result'] is List) {
            items = outer['result'] as List;
          } else if (outer is List) {
            items = outer;
          }
          return items
              .map((e) =>
                  BybitChatMessage.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (e) {
      print('Error fetching chat for order $orderId: $e');
    }
    return [];
  }

  /// Scan all chat messages for an order and return the first Egyptian
  /// phone number found that matches one of [knownNumbers].
  /// Also checks the order's payment details as a fallback.
  Future<String?> findPhoneNumberInChat(
    BybitOrder order,
    List<String> knownNumbers,
  ) async {
    if (knownNumbers.isEmpty) return null;
    final orderId = order.orderId;

    // 1. Scan Chat Messages
    try {
      final messages = await getChatMessages(orderId, size: 30);
      for (final msg in messages) {
        if (!msg.isText) continue;
        final match = PhoneExtractor.findMatch(msg.message, knownNumbers);
        if (match != null) {
          print('Sync: Match found in chat for $orderId: $match');
          return match;
        }
      }
    } catch (e) {
      print('Sync: Chat scan error for $orderId: $e');
    }

    // 2. Fallback: Scan Order Payment Terms (safer for Sell orders)
    print('Sync: No match in chat for $orderId. Checking payment terms...');
    
    // Check confirmedPayTerm accountNo
    // The accountNo or mobile field might be in the root or config
    final termsToCheck = <String>[];
    termsToCheck.add(order.paymentMethod); // Could be the number itself
    
    // We don't have the raw JSON here, but BybitOrder already parsed some.
    // Let's add more fields to BybitOrder if needed, or just search the method name.
    
    final match = PhoneExtractor.findMatch(order.paymentMethod, knownNumbers);
    if (match != null) {
      print('Sync: Match found in payment method name for $orderId: $match');
      return match;
    }

    return null;
  }

  /// Get a concatenated string of all text messages for an order.
  Future<String> getChatSummary(String orderId) async {
    try {
      final messages = await getChatMessages(orderId, size: 50);
      return messages
          .where((m) => m.isText)
          .map((m) => '${m.nickName}: ${m.message}')
          .join('\n');
    } catch (e) {
      return '';
    }
  }
}

// ── Internal helper ───────────────────────────────────────────────────────

class _PageResult {
  final List<BybitOrder> orders;
  final int total;
  _PageResult({required this.orders, required this.total});
}

// ── Chat message model ────────────────────────────────────────────────────

class BybitChatMessage {
  final String id;
  final String message;
  final int msgType;
  final String contentType;
  final String createDate;
  final String orderId;
  final String nickName;

  const BybitChatMessage({
    required this.id,
    required this.message,
    required this.msgType,
    required this.contentType,
    required this.createDate,
    required this.orderId,
    required this.nickName,
  });

  factory BybitChatMessage.fromJson(Map<String, dynamic> json) {
    return BybitChatMessage(
      id: json['id']?.toString() ?? '',
      message: json['message']?.toString() ?? json['content']?.toString() ?? '',
      msgType: json['msgType'] as int? ?? 0,
      contentType: json['contentType']?.toString() ?? 'str',
      createDate: json['createDate']?.toString() ?? '',
      orderId: json['orderId']?.toString() ?? '',
      nickName: json['nickName']?.toString() ?? '',
    );
  }

  bool get isText => contentType == 'str' || msgType == 0 || msgType == 1 || msgType == 5;
}

// ── Phone number extraction ───────────────────────────────────────────────

class PhoneExtractor {
  // Egyptian mobile: 010, 011, 012, 015 followed by 8 digits
  // Removed \b to handle Arabic/English boundaries better
  static final _egyptRegex = RegExp(r'(01[0125][\d\s-]{8,15})');

  /// Universal normaliser: strips all non-digits and ensures '01x' format
  static String normalise(String n) {
    final digits = n.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('20')) return '0${digits.substring(2)}';
    return digits;
  }

  static List<String> extract(String text) {
    final matches = _egyptRegex.allMatches(text).map((m) => m.group(1)!).toList();
    // Clean each match to get pure digits for lookup
    return matches.map((m) => normalise(m)).where((m) => m.length == 11).toList();
  }

  /// Return the first candidate that appears in text, or null.
  static String? findMatch(String text, List<String> candidates) {
    final found = extract(text);
    if (found.isEmpty) return null;
    
    print('Extractor: Found numbers in chat: $found. Matching against known: $candidates');
    
    final normalisedCandidates = candidates.map((c) => normalise(c)).toList();
    
    for (int i = 0; i < normalisedCandidates.length; i++) {
        if (found.contains(normalisedCandidates[i])) {
            return candidates[i]; // Return the original un-normalised candidate
        }
    }
    return null;
  }
}
