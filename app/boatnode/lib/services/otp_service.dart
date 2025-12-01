import 'dart:async';
import 'dart:math';

class OTPService {
  // In-memory storage for OTPs (in a real app, this would be a server)
  static final Map<String, String> _otpStore = {};
  
  // Generate and store OTP for a phone number
  static Future<Map<String, dynamic>> requestOTP(String phoneNumber) async {
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 1));
    
    // Generate a 6-digit OTP
    final otp = (100000 + Random().nextInt(900000)).toString();
    
    // Store OTP (in a real app, this would be sent via SMS)
    _otpStore[phoneNumber] = otp;
    
    // In a real app, you would make an HTTP request here
    // For demo purposes, we'll return the OTP directly
    return {
      'success': true,
      'message': 'OTP sent successfully',
      'otp': otp, // In production, don't return OTP in response
    };
  }
  
  // Verify OTP for a phone number
  static Future<Map<String, dynamic>> verifyOTP(String phoneNumber, String otp) async {
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 1));
    
    // In a real app, you would make an HTTP request to verify the OTP
    final storedOTP = _otpStore[phoneNumber];
    
    if (storedOTP == otp) {
      // Clear the OTP after successful verification
      _otpStore.remove(phoneNumber);
      return {
        'success': true,
        'message': 'OTP verified successfully',
        'token': 'mock_jwt_token_${DateTime.now().millisecondsSinceEpoch}',
      };
    } else {
      return {
        'success': false,
        'message': 'Invalid OTP',
      };
    }
  }
}
