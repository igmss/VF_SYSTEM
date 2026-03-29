import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  AppUser? _currentUser;
  bool _isLoading = true;
  String? _error;

  bool _signingIn = false;

  AppUser? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isLoggedIn => _currentUser != null;
  bool get isAdmin => _currentUser?.isAdmin ?? false;
  bool get isFinance => _currentUser?.isFinance ?? false;
  bool get isCollector => _currentUser?.isCollector ?? false;
  bool get isRetailer => _currentUser?.isRetailer ?? false;

  AuthProvider() {
    _authService.authStateChanges.listen(_onAuthStateChanged);
  }

  Future<void> _onAuthStateChanged(User? firebaseUser) async {
    if (firebaseUser == null) {
      _currentUser = null;
      _isLoading = false;
      if (!_signingIn) {
        _error = null;
      }
      _signingIn = false;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final user = await _authService.getUserData(firebaseUser.uid);
      if (user == null) {
        _currentUser = null;
        _error =
            'This account is missing its access profile. Contact an administrator.';
        await _authService.signOut();
      } else if (!user.isActive) {
        _currentUser = null;
        _error = 'This account has been deactivated.';
        await _authService.signOut();
      } else {
        _currentUser = user;
      }
    } catch (_) {
      _currentUser = null;
      _error = 'Could not verify your account permissions. Please try again.';
      await _authService.signOut();
    }

    _isLoading = false;
    _signingIn = false;
    notifyListeners();
  }

  Future<bool> signIn(String email, String password) async {
    _signingIn = true;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _authService.signIn(email, password);
      return true;
    } on FirebaseAuthException catch (e) {
      _error = _friendlyError(e.code);
      _isLoading = false;
      _signingIn = false;
      notifyListeners();
      return false;
    } catch (e, stackTrace) {
      debugPrint('Sign in Exception: $e');
      debugPrint('Stack Trace: $stackTrace');
      if (_signingIn) {
        _error = 'Login failed: $e';
        _isLoading = false;
        _signingIn = false;
        notifyListeners();
      }
      return false;
    }
  }

  Future<void> signOut() async {
    _currentUser = null;
    notifyListeners();
    await _authService.signOut();
  }

  Future<void> createUser({
    required String email,
    required String password,
    required String name,
    required UserRole role,
    String? retailerId,
  }) async {
    await _authService.createUser(
      email: email,
      password: password,
      name: name,
      role: role,
      retailerId: retailerId,
    );
  }

  Future<void> syncUserRecord({
    required String uid,
    required String email,
    required String name,
    required UserRole role,
    String? retailerId,
  }) async {
    await _authService.syncUserRecord(
      uid: uid,
      email: email,
      name: name,
      role: role,
      retailerId: retailerId,
    );
  }

  Future<List<AppUser>> getAllUsers() async {
    return await _authService.getAllUsers();
  }

  String _friendlyError(String code) {
    switch (code) {
      case 'user-not-found':
      case 'invalid-credential':
        return 'Invalid email or password.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'invalid-email':
        return 'The email address is invalid.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Try again later.';
      default:
        return 'Login failed. Please try again.';
    }
  }
}
