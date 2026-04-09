part of 'distribution_provider.dart';

mixin ExpenseOperationsMixin on ChangeNotifier {
  FirebaseDatabase get _db;
  FirebaseFunctions get _functions;
  List<dynamic> get _expensesRaw;
  String get _currentUserId;

  Future<void> addExpense({
    required double amount,
    required String category,
    required ExpenseSource source,
    required String sourceId,
    required String sourceLabel,
    String? notes,
  }) async {
    final callable = _functions.httpsCallable('addExpense');
    await callable.call({
      'amount': amount,
      'category': category,
      'source': source.toString().split('.').last,
      'sourceId': sourceId,
      'sourceLabel': sourceLabel,
      'notes': notes,
    });
  }
}
