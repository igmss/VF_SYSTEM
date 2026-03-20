import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  AppUser? _currentUser;
  bool _isLoading = true; // Start true — we don't know auth state yet
  String? _error;

  // Guard to prevent signIn's catch from firing on successful auth state change
  bool _signingIn = false;

  AppUser? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isLoggedIn => _currentUser != null;
  bool get isAdmin => _currentUser?.isAdmin ?? false;
  bool get isFinance => _currentUser?.isFinance ?? false;
  bool get isCollector => _currentUser?.isCollector ?? false;

  AuthProvider() {
    // Listen to auth changes — this fires immediately with current state
    _authService.authStateChanges.listen(_onAuthStateChanged);
  }

  Future<void> _onAuthStateChanged(User? firebaseUser) async {
    if (firebaseUser == null) {
      _currentUser = null;
      _isLoading = false;
      _error = null;
      _signingIn = false;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null; // Clear any previous error on new state change
    notifyListeners();

    try {
      _currentUser = await _authService.getUserData(firebaseUser.uid);

      // If no user profile in DB yet, create a default one (fallback)
      if (_currentUser == null) {
        _currentUser = AppUser(
          uid: firebaseUser.uid,
          email: firebaseUser.email ?? '',
          name: firebaseUser.displayName ?? 'User',
          role: UserRole.OPERATOR,
          createdAt: DateTime.now(),
        );
      }
    } catch (_) {
      // DB read failed — still allow login with fallback profile
      _currentUser = AppUser(
        uid: firebaseUser.uid,
        email: firebaseUser.email ?? '',
        name: 'User',
        role: UserRole.OPERATOR,
        createdAt: DateTime.now(),
      );
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
      // Success will be handled by the authStateChanges stream
      return true;
    } on FirebaseAuthException catch (e) {
      _error = _friendlyError(e.code);
      _isLoading = false;
      _signingIn = false;
      notifyListeners();
      return false;
    } catch (e, stackTrace) {
      print('Sign in Exception: $e');
      print('Stack Trace: $stackTrace');
      // Only show error if this wasn't a successful sign-in triggering the stream
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
  }) async {
    await _authService.createUser(
      email: email,
      password: password,
      name: name,
      role: role,
    );
  }

  Future<void> syncUserRecord({
    required String uid,
    required String email,
    required String name,
    required UserRole role,
  }) async {
    await _authService.syncUserRecord(
      uid: uid,
      email: email,
      name: name,
      role: role,
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
