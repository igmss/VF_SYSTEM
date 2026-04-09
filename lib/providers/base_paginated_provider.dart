import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

mixin PaginatedProviderMixin<T> on ChangeNotifier {
  FirebaseDatabase get db;
  String get collectionPath;
  String get orderByField;
  int get pageSize => 50;

  List<T> _items = [];
  bool _isLoading = false;
  bool _hasMore = true;
  dynamic _lastCursor;

  List<T> get paginatedItems => _items;
  bool get isPaginationLoading => _isLoading;
  bool get hasMoreItems => _hasMore;

  T Function(Map<String, dynamic> data) get fromMap;

  Future<void> loadInitialPage() async {
    _items = [];
    _lastCursor = null;
    _hasMore = true;
    await loadNextPage();
  }

  Future<void> loadNextPage() async {
    if (_isLoading || !_hasMore) return;

    _isLoading = true;
    notifyListeners();

    try {
      Query query = db.ref(collectionPath).orderByChild(orderByField);

      if (_lastCursor != null) {
        query = query.endAt(_lastCursor).limitToLast(pageSize + 1);
      } else {
        query = query.limitToLast(pageSize);
      }

      final snap = await query.get();

      if (!snap.exists || snap.value == null) {
        _hasMore = false;
        _isLoading = false;
        notifyListeners();
        return;
      }

      final map = snap.value as Map;
      final newItemsRaw = map.values.toList();

      List<T> newItems = [];
      dynamic nextCursor;

      List<Map<String, dynamic>> parsedList = newItemsRaw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      // Ensure proper sorting. For timestamp it's usually num.
      parsedList.sort((a, b) {
        num valA = a[orderByField] is num ? a[orderByField] : num.tryParse(a[orderByField].toString()) ?? 0;
        num valB = b[orderByField] is num ? b[orderByField] : num.tryParse(b[orderByField].toString()) ?? 0;
        return valB.compareTo(valA);
      });

      if (_lastCursor != null && parsedList.isNotEmpty) {
        // Compare dynamically
        if (parsedList.first[orderByField].toString() == _lastCursor.toString()) {
          parsedList.removeAt(0);
        }
      }

      for (var p in parsedList) {
        newItems.add(fromMap(p));
      }

      if (parsedList.isNotEmpty) {
        nextCursor = parsedList.last[orderByField];
      }

      if (newItems.length < pageSize && _lastCursor != null) {
         _hasMore = false;
      } else if (parsedList.length < pageSize && _lastCursor == null) {
         _hasMore = false;
      }

      _lastCursor = nextCursor;
      _items.addAll(newItems);

    } catch (e) {
      debugPrint('Error loading paginated items: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void insertItemToTop(T item) {
    _items.insert(0, item);
    notifyListeners();
  }
}
