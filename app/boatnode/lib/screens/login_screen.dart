import 'package:boatnode/screens/dashboard_screen.dart';
import 'package:boatnode/screens/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';

import '../services/auth_service.dart';
import '../utils/ui_utils.dart';

// Define color constants
const Color _zinc500 = Color(0xFF71717A);
const Color _zinc900 = Color(0xFF18181B);
const Color _blue600 = Color(0xFF2563EB);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  bool _isLoading = false;
  bool _showOtpField = false;
  String? _email;

  void _requestOTP() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      if (email.isEmpty || !email.contains('@')) {
        UiUtils.showSnackBar(context, 'Please enter a valid email address');
        return;
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Use AuthService to request OTP
      await AuthService.login(email);

      if (mounted) {
        setState(() {
          _isLoading = false;
          _showOtpField = true;
          _email = email;
        });

        UiUtils.showSnackBar(context, 'OTP sent to $email');
      }
    } catch (e) {
      if (mounted) {
        print(e);
        setState(() => _isLoading = false);
        UiUtils.showSnackBar(
          context,
          'Failed to send OTP. Please try again.',
          isError: true,
        );
      }
    }
  }

  void _verifyOTP() async {
    final otp = _otpController.text.trim();
    if (otp.isEmpty || _email == null) return;

    setState(() => _isLoading = true);

    try {
      // Verify OTP and create session
      await AuthService.verifyOtp(_email!, otp);

      // Check if user has completed profile
      final user = await AuthService.getCurrentUser();

      if (mounted) {
        setState(() => _isLoading = false);

        if (user != null && user.role == null) {
          // Navigate to Profile Screen
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => ProfileScreen(user: user)),
          );
        } else {
          // Navigate to dashboard on successful verification
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const DashboardScreen()),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        UiUtils.showSnackBar(context, e.toString(), isError: true);
      }
    }
  }

  void _onSubmit() {
    if (_showOtpField) {
      _verifyOTP();
    } else {
      _requestOTP();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/icon.png',
                width: 80,
                height: 80,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              AppLocalizations.of(context)!.translate('loginTitle'),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.translate('loginSubtitle'),
              style: const TextStyle(color: kZinc500, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),
            if (!_showOtpField) ...[
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autofocus: true,
                enabled: !_isLoading,
                style: const TextStyle(fontSize: 18, color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Enter your email",
                  labelText: "Email",
                  hintStyle: const TextStyle(color: _zinc500),
                  labelStyle: const TextStyle(color: _zinc500),
                  filled: true,
                  fillColor: _zinc900,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _blue600, width: 2),
                  ),
                  prefixIcon: const Icon(Icons.email, color: _zinc500),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                ),
                onSubmitted: (_) => _onSubmit(),
              ),
            ] else ...[
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                autofocus: true,
                enabled: !_isLoading,
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                style: const TextStyle(
                  fontSize: 24,
                  letterSpacing: 8,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLength: 6,
                decoration: InputDecoration(
                  hintText: '000000',
                  hintStyle: const TextStyle(color: _zinc500, letterSpacing: 8),
                  labelText: 'Verification Code',
                  labelStyle: const TextStyle(color: _zinc500),
                  filled: true,
                  fillColor: _zinc900,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _blue600, width: 2),
                  ),
                  counterText: '',
                  prefixIcon: const Icon(Icons.lock_outline, color: _zinc500),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                ),
                onSubmitted: (_) => _onSubmit(),
              ),
              const SizedBox(height: 8),
              Text(
                'OTP sent to $_email',
                style: const TextStyle(color: _zinc500, fontSize: 14),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _isLoading ? null : _requestOTP,
                child: const Text(
                  'Resend OTP',
                  style: TextStyle(color: _blue600),
                ),
              ),
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _onSubmit,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: _blue600,
                ),
                child: _isLoading
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            AppLocalizations.of(
                              context,
                            )!.translate('loggingIn'),
                            style: const TextStyle(fontSize: 16),
                          ),
                        ],
                      )
                    : Text(
                        _showOtpField
                            ? 'Verify OTP'
                            : AppLocalizations.of(
                                context,
                              )!.translate('loginButton'),
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  AppLocalizations.of(context)!.translate('dontHaveAccount'),
                ),
                TextButton(
                  onPressed: () {},
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(50, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    AppLocalizations.of(context)!.translate('signUp'),
                    style: const TextStyle(
                      color: _blue600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
