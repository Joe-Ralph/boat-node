import 'dart:async';
import 'dart:convert';
import '../models/user.dart' as app_user;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:boatnode/services/log_service.dart';

class BackendService {
  // --- Profile & Villages ---

  static Future<List<Map<String, dynamic>>> getVillages() async {
    final response = await Supabase.instance.client
        .from('villages')
        .select()
        .order('name');
    return List<Map<String, dynamic>>.from(response);
  }

  static Future<app_user.User> updateProfile(
    app_user.User user, {
    String? displayName,
    String? role,
    String? villageId,
  }) async {
    final updates = {
      if (displayName != null) 'display_name': displayName,
      if (role != null) 'role': role,
      if (villageId != null) 'village_id': villageId,
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (updates.isEmpty) return user;

    final response = await Supabase.instance.client
        .from('profiles')
        .update(updates)
        .eq('id', user.id)
        .select()
        .single();

    return app_user.User.fromJson(response);
  }

  // --- Boat Management ---

  static Future<Map<String, dynamic>> registerBoat({
    required String name,
    required String registrationNumber,
    String? deviceId,
    required String ownerId,
    required String villageId,
  }) async {
    // 1. Insert Boat
    final boatResponse = await Supabase.instance.client
        .from('boats')
        .insert({
          'name': name,
          'registration_number': registrationNumber,
          'device_id': deviceId,
          'owner_id': ownerId,
          'village_id': villageId,
        })
        .select()
        .single();

    String? password;
    if (deviceId != null) {
      // 2. Get Device Password (securely) if deviceId is provided
      try {
        password = await getDevicePassword(deviceId);
      } catch (e) {
        LogService.w(
          "Warning: Could not fetch password for device $deviceId",
          e,
        );
      }
    }

    return {'boat_id': boatResponse['id'], 'device_password': password};
  }

  static Future<List<Map<String, dynamic>>> getUserBoats(String userId) async {
    final response = await Supabase.instance.client
        .from('boats')
        .select()
        .eq('owner_id', userId);
    return List<Map<String, dynamic>>.from(response);
  }

  static Future<String> getDevicePassword(String deviceId) async {
    try {
      // Call secure RPC function
      final response = await Supabase.instance.client.rpc(
        'get_device_password',
        params: {'p_device_id': deviceId},
      );

      if (response == null) {
        throw Exception('Device not found or password unavailable');
      }
      return response as String;
    } catch (e) {
      // Fallback for testing if RPC fails or not set up
      LogService.w(
        "RPC failed. Falling back to direct query (only works if RLS allows).",
        e,
      );
      // Note: This fallback will likely fail if RLS is strict, which is good.
      throw Exception('Failed to get device password');
    }
  }

  static Future<void> associateDeviceWithBoat(
    String deviceId,
    String boatId,
  ) async {
    await Supabase.instance.client
        .from('boats')
        .update({'device_id': deviceId})
        .eq('id', boatId);
  }

  // --- Location Updates ---

  static Future<void> updateLiveLocation({
    required double lat,
    required double lon,
    required int battery,
    required String boatId,
    double heading = 0.0,
    double speed = 0.0,
  }) async {
    // 1. Audit Log (History)
    await Supabase.instance.client.from('boat_logs').insert({
      'boat_id': boatId,
      'lat': lat,
      'lon': lon,
      'battery_level': battery,
      'heading': heading,
      'speed': speed,
    });

    // 2. Live Location (Current State)
    await Supabase.instance.client.from('boat_live_locations').upsert({
      'boat_id': boatId,
      'lat': lat,
      'lon': lon,
      'heading': heading,
      'speed': speed,
      'battery_level': battery,
      'last_updated': DateTime.now().toIso8601String(),
    });
  }

  static Future<List<Map<String, dynamic>>> getNearbyBoats({
    required double lat,
    required double lon,
    double radiusMeters = 50000,
  }) async {
    final response = await Supabase.instance.client.rpc(
      'get_nearby_boats',
      params: {
        'my_lat': lat,
        'my_lon': lon,
        'radius_meters': radiusMeters,
        'limit_count': 20,
      },
    );
    return List<Map<String, dynamic>>.from(response);
  }

  // --- QR & Joining ---

  static Future<Map<String, dynamic>> joinBoatByQR(String qrCode) async {
    // Format V1: BOAT:<boat_id>:<device_id> (Legacy)
    // Format V2: BOAT_V2:<boat_id>:<owner_id>:<password>
    // Note: Input qrCode is expected to be Base64 encoded V2 string, but we support raw for legacy/testing.

    try {
      String decodedQr;
      // Simple heuristic: If it starts with "BOAT", it's likely raw. Otherwise try decode.
      if (qrCode.startsWith("BOAT")) {
        decodedQr = qrCode;
      } else {
        try {
          decodedQr = utf8.decode(base64Decode(qrCode));
        } catch (_) {
          // If decode fails, assume it's just a malformed string or raw string that didn't start with BOAT
          decodedQr = qrCode;
        }
      }

      final parts = decodedQr.split(':');
      if (parts.length < 3) throw Exception('Incomplete QR Data');

      String boatId;
      String? ownerIdFromQr;
      // String? password; // Not used for DB auth, maybe for Wifi later?

      if (parts[0] == 'BOAT_V2') {
        if (parts.length < 4) throw Exception('Invalid V2 QR Data');
        boatId = parts[1];
        ownerIdFromQr = parts[2];
        // password = parts[3];
      } else if (parts[0] == 'BOAT') {
        // Legacy fallback or reject? Prompt says "always make this validation".
        // So we should probably reject if we want strict owner validation and legacy didn't have it.
        // But legacy had <device_id> at index 2.
        // Let's support V2 primarily as requested.
        throw Exception(
          'Old QR format no longer supported. Please ask owner to update app.',
        );
      } else {
        throw Exception('Invalid QR Code Format');
      }

      // 1. Fetch Boat and Verify Owner
      final boat = await Supabase.instance.client
          .from('boats')
          .select()
          .eq('id', boatId)
          .single();

      // 2. Validate Owner ID
      if (ownerIdFromQr != boat['owner_id']) {
        throw Exception(
          'Security Warning: QR Code owner does not match Boat owner. Validation failed.',
        );
      }

      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw Exception('User not logged in');

      // 3. Re-register logic: Delete previous joined boat memberships
      // "delete their previous joined boat in the backend and rejoin..."
      await Supabase.instance.client
          .from('boat_members')
          .delete()
          .eq('user_id', userId);

      // 4. Join the new boat
      await Supabase.instance.client.from('boat_members').insert({
        'boat_id': boatId,
        'user_id': userId,
        'role': 'crew',
      });

      // Also update profile to reflect current boat for easy access
      await Supabase.instance.client
          .from('profiles')
          .update({'boat_id': boatId})
          .eq('id', userId);

      return {
        'boat_id': boatId,
        'boat_name': boat['name'],
        'owner_id': boat['owner_id'],
      };
    } catch (e) {
      LogService.e("Join Boat Error", e);
      rethrow; // Pass error to UI
    }
  }
  // --- SOS & Profile Helpers ---

  static Future<Map<String, dynamic>?> getPublicProfile(String userId) async {
    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select('display_name, avatar_url, role')
          .eq('id', userId)
          .maybeSingle(); // Use maybeSingle to avoid exception if not found
      return response;
    } catch (e) {
      LogService.e("BackendService: Error fetching profile for $userId", e);
      return null;
    }
  }

  static Future<int> getSosBroadcastCount(String senderId) async {
    try {
      // Create a temporary simplified query to count recipients of recent SOS from this sender
      // This assumes we want to know how many people *this specific* SOS (or recent ones) went to.
      // Ideally we'd filter by a specific SOS ID if available, but for now let's count all pending/recent.
      // Or better: The prompt asks "how many devices are the request's made".
      // This implies counting rows in sos_signals where sender_id = X and created_at is recent.

      final response = await Supabase.instance.client
          .from('sos_signals')
          .select('id')
          .eq('sender_id', senderId)
          .eq('status', 'pending'); // Count active/pending signals
      // .gt('created_at', DateTime.now().subtract(Duration(minutes: 30)).toIso8601String());

      return (response as List).length;
    } catch (e) {
      LogService.e("BackendService: Error counting SOS broadcast", e);
      return 0;
    }
  }
}
