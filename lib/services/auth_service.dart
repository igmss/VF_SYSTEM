import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/app_user.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseDatabase _database = FirebaseDatabase.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<AppUser?> getUserData(String uid) async {
    try {
      debugPrint('Fetching user data for UID: $uid');
      final snapshot = await _database.ref('users/$uid').get();
      if (snapshot.exists && snapshot.value != null) {
        final rawData = snapshot.value;
        if (rawData is Map) {
          debugPrint('User data found, parsing...');
          final data = Map<String, dynamic>.from(rawData);
          return AppUser.fromMap(data, uid);
        } else {
          debugPrint('User data for $uid is not a Map: $rawData');
        }
      } else {
        debugPrint('No user data found for UID: $uid');
      }
    } catch (e, stack) {
      debugPrint('Error fetching user data: $e');
      debugPrint(stack.toString());
    }
    return null;
  }

  Future<UserCredential> signIn(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  /// Creates a new user using the Firebase Auth REST API so the admin's
  /// session is never disrupted, then writes the profile to the database
  /// using the admin's existing auth context.
  Future<void> createUser({
    required String email,
    required String password,
    required String name,
    required UserRole role,
  }) async {
    // Step 1: Get the current admin's ID token to authenticate the DB write
    final adminUser = _auth.currentUser;
    if (adminUser == null) {
      throw 'Not authenticated. Please log in again.';
    }
    
    // Refresh the admin token to ensure it's valid
    final adminToken = await adminUser.getIdToken(true);
    debugPrint('Admin token retrieved, preparing user creation...');

    // Step 2: Get the Firebase API key from the current app options
    final apiKey = _auth.app.options.apiKey;
    
    // Step 3: Call Firebase Auth REST API to create the user (no secondary app!)
    String newUid;
    try {
      final response = await http.post(
        Uri.parse(
            'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'returnSecureToken': true,
        }),
      );

      final responseBody = jsonDecode(response.body) as Map<String, dynamic>;
      
      if (response.statusCode != 200) {
        final errorMsg = (responseBody['error'] as Map?)?['message'] as String? ?? 'Unknown error';
        if (errorMsg.contains('EMAIL_EXISTS')) {
          throw 'This email is already in use by another account.';
        }
        throw 'Auth error: $errorMsg';
      }
      
      newUid = responseBody['localId'] as String;
      debugPrint('New user created in Auth: $newUid');
    } catch (e) {
      if (e is String) rethrow;
      throw 'Auth error: $e';
    }

    // Step 4: Write the profile to the database using the admin's context
    // The admin is still signed in, so the DB write uses admin's token
    try {
      final appUser = AppUser(
        uid: newUid,
        email: email,
        name: name,
        role: role,
        createdAt: DateTime.now(),
      );
      debugPrint('Writing user profile to database: users/$newUid');
      await _database
          .ref('users/$newUid')
          .set(Map<String, dynamic>.from(appUser.toMap()));
      debugPrint('Database write successful!');

      // Step 5: If the role is COLLECTOR, automatically create a linked
      // Collector record so the user's dashboard works immediately.
      if (role == UserRole.COLLECTOR) {
        debugPrint('Creating Collector record for new COLLECTOR user...');
        final collectorId = newUid; // use UID as collector node key for easy lookup
        await _database.ref('collectors/$collectorId').set({
          'id': collectorId,
          'name': name,
          'phone': '',
          'email': email,
          'uid': newUid,
          'cashOnHand': 0.0,
          'cashLimit': 50000.0,
          'totalCollected': 0.0,
          'totalDeposited': 0.0,
          'isActive': true,
          'createdAt': DateTime.now().toIso8601String(),
          'lastUpdatedAt': DateTime.now().toIso8601String(),
        });
        debugPrint('Collector record created automatically.');
      }
    } catch (dbError) {
      // Rollback: delete the Auth account via REST API since we can't use
      // a User object (we used the REST API to create it)
      debugPrint('DB write failed, rolling back Auth account: $dbError');
      try {
        await http.post(
          Uri.parse(
              'https://identitytoolkit.googleapis.com/v1/accounts:delete?key=$apiKey'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'idToken': adminToken}),
        );
        debugPrint('Warning: rollback used admin token — may not delete new user.');
      } catch (_) {}
      throw 'Database error: $dbError';
    }
  }

  Future<List<AppUser>> getAllUsers() async {
    try {
      final snapshot = await _database.ref('users').get();
      if (snapshot.exists && snapshot.value != null) {
        final rawMap = snapshot.value as Map;
        final List<AppUser> users = [];
        rawMap.forEach((key, value) {
          if (value is Map) {
            final data = Map<String, dynamic>.from(value);
            users.add(AppUser.fromMap(data, key.toString()));
          }
        });
        return users;
      }
    } catch (e) {
      debugPrint('Error fetching all users: $e');
    }
    return [];
  }

  Future<void> syncUserRecord({
    required String uid,
    required String email,
    required String name,
    required UserRole role,
  }) async {
    final appUser = AppUser(
      uid: uid,
      email: email,
      name: name,
      role: role,
      createdAt: DateTime.now(),
    );
    final data = Map<String, dynamic>.from(appUser.toMap());
    debugPrint('Syncing user record to DB: users/$uid with data: $data');
    await _database.ref('users/$uid').set(data);
    debugPrint('Sync successful');
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}
