import 'dart:async';
import 'package:boatnode/services/session_service.dart';
import 'package:boatnode/models/session.dart' as app_session;
import 'package:boatnode/models/user.dart' as app_user;
import 'package:boatnode/services/backend_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:boatnode/services/log_service.dart';

class AuthService {
  // Mock method to validate session with a server
  static Future<bool> validateSession(String token) async {
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 1));

    // In a real app, this would make an API call to validate the token
    // For demo purposes, we'll consider a token valid if it exists and isn't expired
    final session = SessionService.currentSession;
    if (session == null || session.isExpired) {
      return false;
    }

    return true;
  }

  // Login with Email OTP
  static Future<void> login(String email) async {
    await Supabase.instance.client.auth.signInWithOtp(email: email);
  }

  // Verify OTP and create session
  static Future<app_session.Session> verifyOtp(String email, String otp) async {
    final response = await Supabase.instance.client.auth.verifyOTP(
      type: OtpType.email,
      token: otp,
      email: email,
    );

    if (response.session == null) {
      throw Exception('Login failed: No session created');
    }

    final sbSession = response.session!;
    final sbUser = response.user!;

    // Create a local session object
    final session = app_session.Session(
      token: sbSession.accessToken,
      userId: sbUser.id,
      displayName: sbUser.userMetadata?['display_name'] ?? email.split('@')[0],
      expiresAt: DateTime.now().add(
        Duration(seconds: sbSession.expiresIn ?? 3600),
      ),
    );

    // Fetch or Create User Profile
    app_user.User? user = await _fetchUserProfile(sbUser.id);

    user ??= app_user.User(
        id: sbUser.id,
        displayName: session.displayName,
        email: email,
        role: null,
        villageId: null,
      );

    await SessionService.saveSession(session);
    await SessionService.saveUser(user);

    return session;
  }

  static Future<void> logout() async {
    await Supabase.instance.client.auth.signOut();
    await SessionService.clearSession();
  }

  static Future<app_user.User> updateProfile(
    app_user.User user, {
    String? displayName,
    String? role,
    String? villageId,
    String? boatRegistrationNumber,
  }) async {
    // Update Supabase Auth Metadata (optional, but good for quick access)
    await Supabase.instance.client.auth.updateUser(
      UserAttributes(
        data: {if (displayName != null) 'display_name': displayName},
      ),
    );

    // Update Profiles Table via BackendService
    var updatedUser = await BackendService.updateProfile(
      user,
      displayName: displayName,
      role: role,
      villageId: villageId,
    );

    // If role is owner and registration number is provided, register the boat
    if (role == 'owner' &&
        boatRegistrationNumber != null &&
        boatRegistrationNumber.isNotEmpty) {
      try {
        final result = await BackendService.registerBoat(
          name: "${updatedUser.displayName}'s Boat",
          registrationNumber: boatRegistrationNumber,
          ownerId: updatedUser.id,
          villageId: villageId ?? updatedUser.villageId ?? '',
        );

        final boatId = result['boat_id'] as String;

        // Update local user object with boatId
        // Note: We might need to update the profile with boat_id if the backend doesn't do it automatically
        // But typically the boat table has owner_id, so we can query it.
        // However, the User model has boatId, so let's update it locally and persist.

        // Also update profile with current active boat_id
        await Supabase.instance.client
            .from('profiles')
            .update({'boat_id': boatId})
            .eq('id', updatedUser.id);

        updatedUser = app_user.User(
          id: updatedUser.id,
          displayName: updatedUser.displayName,
          email: updatedUser.email,
          role: updatedUser.role,
          villageId: updatedUser.villageId,
          boatId: boatId,
        );
      } catch (e) {
        LogService.e("Error registering boat", e);
        // We might want to rethrow or handle this gracefully
        // For now, we proceed but log the error
      }
    }

    // Update local mock user
    await SessionService.saveUser(updatedUser);

    return updatedUser;
  }

  static Future<void> joinBoat(String qrCode) async {
    final result = await BackendService.joinBoatByQR(qrCode);
    LogService.i("Joined boat: ${result['boat_name']}");
  }

  static Future<app_user.User?> getCurrentUser() async {
    // Check Supabase Session
    final sbUser = Supabase.instance.client.auth.currentUser;
    if (sbUser == null) {
      return null;
    }

    // Try to get from local storage first for speed
    if (SessionService.currentUser != null &&
        SessionService.currentUser!.id == sbUser.id) {
      // Optionally verify if session is expired? Supabase SDK handles token refresh.
      return SessionService.currentUser;
    }

    // Fetch from Backend
    final user = await _fetchUserProfile(sbUser.id);
    if (user != null) {
      await SessionService.saveUser(user);
    }
    return user;
  }

  static Future<app_user.User?> _fetchUserProfile(String userId) async {
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();

      return app_user.User.fromJson(data);
    } catch (e) {
      LogService.e('Error fetching profile', e);
      return null;
    }
  }
}
