import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import '../models/app_user.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-east1');

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

  Future<void> createUser({
    required String email,
    required String password,
    required String name,
    required UserRole role,
  }) async {
    try {
      final callable = _functions.httpsCallable('createUserAccount');
      await callable.call({
        'email': email,
        'password': password,
        'name': name,
        'role': role.toString().split('.').last,
      });
    } on FirebaseFunctionsException catch (e) {
      throw e.message ?? 'Unable to create user.';
    } catch (e) {
      throw 'Unable to create user: $e';
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
