import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:flutter/foundation.dart';
import '../models/app_user.dart';

class AuthService {
  final sb.SupabaseClient _supabase = sb.Supabase.instance.client;

  Stream<sb.User?> get authStateChanges => _supabase.auth.onAuthStateChange.map((event) => event.session?.user);
  sb.User? get currentUser => _supabase.auth.currentUser;

  Future<AppUser?> getUserData(String uid) async {
    try {
      debugPrint('Fetching user data from Supabase for UID: $uid');
      // Try by ID first, then by firebase_uid
      final response = await _supabase
          .from('users')
          .select()
          .or('id.eq.$uid,firebase_uid.eq.$uid')
          .maybeSingle();

      if (response != null) {
        debugPrint('User data found in Supabase, parsing...');
        // Map snake_case from DB to camelCase for the model
        final data = {
          'email': response['email'],
          'name': response['name'],
          'role': response['role'],
          'isActive': response['is_active'],
          'createdAt': response['created_at'],
          'retailerId': response['retailer_id'],
        };
        return AppUser.fromMap(data, (response['firebase_uid'] ?? response['id']).toString());
      } else {
        debugPrint('No user data found in Supabase for UID: $uid');
      }
    } catch (e, stack) {
      debugPrint('Error fetching user data from Supabase: $e');
      debugPrint(stack.toString());
    }
    return null;
  }

  Future<sb.AuthResponse> signIn(String email, String password) async {
    return await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> createUser({
    required String email,
    required String password,
    required String name,
    required UserRole role,
    String? retailerId,
  }) async {
    try {
      // Call Supabase Edge Function
      await _supabase.functions.invoke('create-user-account', body: {
        'email': email,
        'password': password,
        'name': name,
        'role': role.toString().split('.').last,
        if (retailerId != null && retailerId.isNotEmpty) 'retailerId': retailerId,
      });
    } catch (e) {
      throw 'Unable to create user: $e';
    }
  }

  Future<List<AppUser>> getAllUsers() async {
    try {
      final List<dynamic> data = await _supabase.from('users').select();
      return data.map((item) {
        final mapped = {
          'email': item['email'],
          'name': item['name'],
          'role': item['role'],
          'isActive': item['is_active'],
          'createdAt': item['created_at'],
          'retailerId': item['retailer_id'],
        };
        return AppUser.fromMap(mapped, (item['firebase_uid'] ?? item['id']).toString());
      }).toList();
    } catch (e) {
      debugPrint('Error fetching all users from Supabase: $e');
    }
    return [];
  }

  Future<void> syncUserRecord({
    required String uid,
    required String email,
    required String name,
    required UserRole role,
    String? retailerId,
  }) async {
    // In Supabase, the create-user-account function handles synchronization.
    // If we need manual sync:
    try {
      final nowIso = DateTime.now().toIso8601String();
      await _supabase.from('users').upsert({
        'id': uid,
        'email': email,
        'name': name,
        'role': role.toString().split('.').last,
        'is_active': true,
        'retailer_id': role == UserRole.RETAILER ? retailerId : null,
      });
      
      if (role == UserRole.COLLECTOR) {
        await _supabase.from('collectors').upsert({
          'id': uid,
          'name': name,
          'email': email,
          'is_active': true,
          'last_updated_at': nowIso,
        });
      }
    } catch (e) {
      debugPrint('Error syncing user record to Supabase: $e');
    }
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }
}
