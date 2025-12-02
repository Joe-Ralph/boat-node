import 'dart:async';
import 'package:boatnode/services/session_service.dart';
import 'package:boatnode/models/session.dart';
import 'package:boatnode/models/user.dart' as app_user;
import 'package:boatnode/services/backend_service.dart';

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

  // Mock login that returns a session
  static Future<Session> login(String email, String otp) async {
    // In a real app, this would make an API call to verify the OTP
    await Future.delayed(const Duration(seconds: 1));

    // For demo purposes, we'll accept any OTP that's 6 digits
    if (otp.length != 6) {
      throw Exception('Invalid OTP');
    }

    // Create a new session that expires in 7 days
    final session = Session(
      token: 'mock_jwt_${DateTime.now().millisecondsSinceEpoch}',
      userId: 'user_${email.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')}',
      displayName: email.split('@')[0],
      expiresAt: DateTime.now().add(const Duration(days: 7)),
    );

    // Initialize mock user for this session (Fresh login -> No role)
    final user = app_user.User(
      id: "101", // Mock String ID
      displayName: session.displayName,
      email: email,
      role: null, // Force null role to trigger profile screen
      villageId: null,
    );

    await SessionService.saveSession(session);
    await SessionService.saveUser(user);

    return session;
  }

  static Future<void> logout() async {
    await SessionService.clearSession();
  }

  static Future<app_user.User> updateProfile(
    app_user.User user, {
    String? displayName,
    String? role,
    String? villageId,
  }) async {
    final updatedUser = await BackendService.updateProfile(
      user,
      displayName: displayName,
      role: role,
      villageId: villageId,
    );

    // Update local mock user
    await SessionService.saveUser(updatedUser);

    return updatedUser;
  }

  static Future<void> joinBoat(String qrCode) async {
    final result = await BackendService.joinBoatByQR(qrCode);
    // In a real app, we would update the user's session/profile on the server
    // and refresh the local user object.
    // For mock, we assume the backend update happened.
    print("Joined boat: ${result['boat_name']}");
  }

  static Future<app_user.User?> getCurrentUser() async {
    await Future.delayed(const Duration(milliseconds: 500));

    // Return persisted user from SessionService
    if (SessionService.currentUser != null) {
      return SessionService.currentUser;
    }

    // Fallback if session exists but user not found (shouldn't happen with new logic)
    final session = SessionService.currentSession;
    if (session != null) {
      final user = app_user.User(
        id: "101",
        displayName: session.displayName,
        email: "user@example.com", // Fallback email
        role: null,
        villageId: null,
      );
      // Save this fallback so we don't create it again
      await SessionService.saveUser(user);
      return user;
    }

    return null;
  }
}
