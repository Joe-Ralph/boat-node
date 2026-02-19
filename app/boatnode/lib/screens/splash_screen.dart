import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../services/session_service.dart';
import '../services/auth_service.dart';
import '../services/background_service.dart';
import '../utils/ui_utils.dart';
import '../constants.dart';
import 'login_screen.dart';
import 'dashboard_screen.dart';
import 'profile_screen.dart';
import '../models/user.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    // 1. Initialize SessionService
    try {
      await SessionService.init();
    } catch (e) {
      if (mounted) {
        UiUtils.showSnackBar(
          context,
          "Error initializing SessionService: $e",
          isError: true,
        );
      }
    }

    // 2. Initialize Supabase
    try {
      const supabaseUrl = Constants.supabaseUrl;
      const supabaseAnonKey = Constants.supabaseAnonKey;

      if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
        await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
      } else {
        if (mounted) {
          UiUtils.showSnackBar(
            context,
            "Warning: Supabase keys not found.",
            isError: true,
            duration: const Duration(seconds: 10),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        UiUtils.showSnackBar(
          context,
          "Error initializing Supabase: $e",
          isError: true,
          duration: const Duration(seconds: 10),
        );
      }
    }

    // 3. Initialize BackgroundService
    try {
      await BackgroundService.initializeService().timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          if (mounted) {
            UiUtils.showSnackBar(
              context,
              "BackgroundService initialization timed out.",
              isError: true,
            );
          }
        },
      );
    } catch (e) {
      if (mounted) {
        UiUtils.showSnackBar(
          context,
          "Error initializing BackgroundService: $e",
          isError: true,
        );
      }
    }

    // 4. Check Session
    await _checkSessionAndNavigate();
  }

  Future<void> _checkSessionAndNavigate() async {
    final session = SessionService.currentSession;

    if (session == null) {
      _navigateToLogin();
      return;
    }

    try {
      final isValid = await AuthService.validateSession(session.token);
      if (!isValid) {
        await SessionService.clearSession();
        _navigateToLogin();
      } else {
        // Fetch user profile to determine routing
        final user = await AuthService.getCurrentUser();
        if (user != null && user.role == null) {
          _navigateToProfile(user);
        } else {
          _navigateToDashboard();
        }
      }
    } catch (e) {
      await SessionService.clearSession();
      if (mounted) {
        UiUtils.showSnackBar(
          context,
          "Session validation failed: $e",
          isError: true,
        );
      }
      _navigateToLogin();
    }
  }

  void _navigateToLogin() {
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  void _navigateToDashboard() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DashboardScreen()),
    );
  }

  void _navigateToProfile(User user) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => ProfileScreen(user: user)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
