import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
// import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'l10n/app_localizations.dart';
// import 'l10n/locale_provider.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'services/session_service.dart';
import 'services/auth_service.dart';
import 'screens/profile_screen.dart';
import 'models/user.dart';
import 'theme/app_theme.dart';

void main() async {
  // Ensure Flutter binding is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize session service
  await SessionService.init();

  runApp(
    ChangeNotifierProvider(
      create: (context) => LocaleProvider(),
      child: const BoatNodeApp(),
    ),
  );
}

class LocaleProvider with ChangeNotifier {
  Locale _locale = const Locale('en');

  Locale get locale => _locale;

  void setLocale(Locale locale) {
    if (!['en', 'ta', 'ml', 'hi'].contains(locale.languageCode)) return;
    _locale = locale;
    notifyListeners();
  }
}

class BoatNodeApp extends StatelessWidget {
  const BoatNodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<LocaleProvider>(
      builder: (context, localeProvider, _) {
        return MaterialApp(
          title: 'Neduvaai',
          debugShowCheckedModeBanner: false,
          theme: appTheme,
          locale: localeProvider.locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('en', ''), // English
            Locale('ta', ''), // Tamil
            Locale('ml', ''), // Malayalam
            Locale('hi', ''), // Hindi
          ],
          home: FutureBuilder<bool>(
            future: _checkSession(),
            builder: (context, snapshot) {
              // Show a loading indicator while checking session
              if (snapshot.connectionState != ConnectionState.done) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              // If we have a valid session, check user profile
              if (snapshot.data == true) {
                return FutureBuilder<User?>(
                  future: AuthService.getCurrentUser(),
                  builder: (context, userSnapshot) {
                    if (userSnapshot.connectionState != ConnectionState.done) {
                      return const Scaffold(
                        body: Center(child: CircularProgressIndicator()),
                      );
                    }

                    final user = userSnapshot.data;
                    if (user != null && user.role == null) {
                      return ProfileScreen(user: user);
                    }
                    return const DashboardScreen();
                  },
                );
              }

              return const LoginScreen();
            },
          ),
        );
      },
    );
  }

  // Check if we have a valid session
  Future<bool> _checkSession() async {
    final session = SessionService.currentSession;
    if (session == null) return false;

    try {
      // Validate the session with the server
      final isValid = await AuthService.validateSession(session.token);
      if (!isValid) {
        await SessionService.clearSession();
      }
      return isValid;
    } catch (e) {
      // If there's an error, assume invalid session
      await SessionService.clearSession();
      return false;
    }
  }
}
