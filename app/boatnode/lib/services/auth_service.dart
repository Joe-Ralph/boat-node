import 'dart:async';
import 'package:boatnode/services/session_service.dart';
import 'package:boatnode/models/session.dart';
import 'package:boatnode/models/user.dart';

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

    // Simulate 10% chance of token being invalid (for demo purposes)
    return DateTime.now().millisecondsSinceEpoch % 10 != 0;
  }

  // Mock login that returns a session
  static Future<Session> login(String phoneNumber, String otp) async {
    // In a real app, this would make an API call to verify the OTP
    await Future.delayed(const Duration(seconds: 1));

    // For demo purposes, we'll accept any OTP that's 6 digits
    if (otp.length != 6) {
      throw Exception('Invalid OTP');
    }

    // Create a new session that expires in 7 days
    final session = Session(
      token: 'mock_jwt_${DateTime.now().millisecondsSinceEpoch}',
      userId: 'user_${phoneNumber.replaceAll(RegExp(r'[^0-9]'), '')}',
      displayName: 'User ${phoneNumber.substring(phoneNumber.length - 4)}',
      expiresAt: DateTime.now().add(const Duration(days: 7)),
    );

    await SessionService.saveSession(session);
    return session;
  }

  static Future<void> logout() async {
    await SessionService.clearSession();
  }

  static Future<User?> getCurrentUser() async {
    await Future.delayed(const Duration(milliseconds: 500));
    // Mock user
    return User(
      id: 101,
      displayName: "Captain Jack",
      phoneNumber: "+919876543210",
    );
  }
}
