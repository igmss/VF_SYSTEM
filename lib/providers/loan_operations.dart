part of 'distribution_provider.dart';

mixin LoanOperationsMixin on ChangeNotifier {
  FirebaseDatabase get _db;
  FirebaseFunctions get _functions;
  List<dynamic> get _loansRaw;
  String get _currentUserId;

  Future<void> issueLoan({
    required String borrowerName,
    required double principal,
    required String sourceBankId,
    String? notes,
  }) async {
    final callable = _functions.httpsCallable('issueLoan');
    await callable.call({
      'borrowerName': borrowerName,
      'principal': principal,
      'sourceBankId': sourceBankId,
      'notes': notes,
    });
  }

  Future<void> repayLoan({
    required String loanId,
    required double amount,
    required String destBankId,
    String? notes,
  }) async {
    final callable = _functions.httpsCallable('repayLoan');
    await callable.call({
      'loanId': loanId,
      'amount': amount,
      'destBankId': destBankId,
      'notes': notes,
    });
  }
}
