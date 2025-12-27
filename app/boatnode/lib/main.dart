import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'l10n/app_localizations.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  // Ensure Flutter binding is initialized
  WidgetsFlutterBinding.ensureInitialized();

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
          home: const SplashScreen(),
        );
      },
    );
  }
}
