import 'package:boatnode/screens/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../services/otp_service.dart';
import '../services/auth_service.dart';

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
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  bool _isLoading = false;
  bool _showOtpField = false;
  String? _phoneNumber;
  String? _verificationId;

  void _requestOTP() async {
    final phoneNumber = _phoneController.text.trim();
    if (phoneNumber.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final response = await OTPService.requestOTP(phoneNumber);

      if (mounted) {
        setState(() {
          _isLoading = false;
          _showOtpField = true;
          _phoneNumber = phoneNumber;
          // In a real app, you wouldn't show the OTP in the UI
          // This is just for demo purposes
          _otpController.text = response['otp'];
        });

        // Show a snackbar with success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              response['message'],
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: _zinc900,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.0),
            ),
            margin: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 16.0,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Failed to send OTP. Please try again.',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red[800],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.0),
            ),
            margin: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 16.0,
            ),
          ),
        );
      }
    }
  }

  void _verifyOTP() async {
    final otp = _otpController.text.trim();
    if (otp.isEmpty || _phoneNumber == null) return;

    setState(() => _isLoading = true);

    try {
      // Use AuthService to handle login and session creation
      await AuthService.login(_phoneNumber!, otp);

      if (mounted) {
        setState(() => _isLoading = false);
        // Navigate to dashboard on successful verification
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const DashboardScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString(),
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red[800],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.0),
            ),
            margin: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 16.0,
            ),
          ),
        );
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
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: _blue600,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.sailing, size: 40, color: Colors.white),
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
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                autofocus: true,
                enabled: !_isLoading,
                style: const TextStyle(fontSize: 18, color: Colors.white),
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(
                    context,
                  )!.translate('enterPhoneNumber'),
                  labelText: AppLocalizations.of(
                    context,
                  )!.translate('phoneNumber'),
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
                  prefixIcon: const Icon(Icons.phone, color: _zinc500),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                ),
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
                'OTP sent to $_phoneNumber',
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
