import 'dart:async';
import 'dart:math';
import '../models/user.dart';

class BackendService {
  static const bool _useMock = true;

  // Mock Data
  static final List<Map<String, String>> _villages = [
    {'id': '1', 'name': 'Marina Beach', 'district': 'Chennai'},
    {'id': '2', 'name': 'Besant Nagar', 'district': 'Chennai'},
    {'id': '3', 'name': 'Kovalam', 'district': 'Kanchipuram'},
    {'id': '4', 'name': 'Mahabalipuram', 'district': 'Chengalpattu'},
  ];

  static final Map<String, String> _devicePasswords = {
    '1234': 'pairme-1234',
    '5678': 'pairme-5678',
  };

  // --- Profile & Villages ---

  static Future<List<Map<String, String>>> getVillages() async {
    await Future.delayed(const Duration(milliseconds: 500));
    return _villages;
  }

  static Future<User> updateProfile(
    User user, {
    String? displayName,
    String? role,
    String? villageId,
  }) async {
    await Future.delayed(const Duration(seconds: 1));

    // In a real app, this would update the backend
    return User(
      id: user.id,
      phoneNumber: user.phoneNumber,
      displayName: displayName ?? user.displayName,
      role: role ?? user.role,
      villageId: villageId ?? user.villageId,
      boatId: user.boatId,
    );
  }

  // --- Boat Management ---

  static Future<Map<String, dynamic>> registerBoat({
    required String name,
    required String registrationNumber,
    required String deviceId,
    required int ownerId,
    required String villageId,
  }) async {
    await Future.delayed(const Duration(seconds: 1));

    // Validate device ID (mock check)
    if (!_devicePasswords.containsKey(deviceId)) {
      throw Exception('Invalid Device ID');
    }

    final boatId = 'boat-${Random().nextInt(10000)}';
    final devicePassword = _devicePasswords[deviceId]!;

    return {'boat_id': boatId, 'device_password': devicePassword};
  }

  static Future<String> getDevicePassword(String deviceId) async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (_devicePasswords.containsKey(deviceId)) {
      return _devicePasswords[deviceId]!;
    }
    throw Exception('Device not found');
  }

  static Future<void> associateDeviceWithBoat(
    String deviceId,
    String boatId,
  ) async {
    await Future.delayed(const Duration(seconds: 1));
    // Mock association logic
    print('Associated device $deviceId with boat $boatId');
  }

  // --- Location Updates ---

  static Future<void> updateLocation({
    required double lat,
    required double lon,
    required int battery,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));
    // Mock location update
    print(
      'Backend: Location updated -> Lat: $lat, Lon: $lon, Battery: $battery%',
    );
  }

  // --- QR & Joining ---

  static Future<Map<String, dynamic>> joinBoatByQR(String qrCode) async {
    await Future.delayed(const Duration(seconds: 1));

    // Format: BOAT:<boat_id>:<device_id>:<password>
    try {
      if (!qrCode.startsWith('BOAT:')) {
        throw Exception('Invalid QR Code Format');
      }

      final parts = qrCode.split(':');
      if (parts.length < 4) throw Exception('Incomplete QR Data');

      final boatId = parts[1];
      final deviceId = parts[2];
      final password = parts[3];

      // In real app, verify signature/hash here

      return {
        'boat_id': boatId,
        'device_id': deviceId,
        'boat_name': 'Boat $boatId',
        'device_password': password,
      };
    } catch (e) {
      throw Exception('Failed to join boat: $e');
    }
  }
}
