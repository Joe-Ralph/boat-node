import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:wifi_iot/wifi_iot.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'package:geolocator/geolocator.dart';
import '../models/boat.dart';
import '../models/nearby_boat.dart';
import 'dart:async';

class HardwareService {
  static bool _useMockService = true; // Default to true for development
  static int _mockBatteryLevel = 85;
  static Position? _mockPosition;

  static void setMockBatteryLevel(int level) {
    _mockBatteryLevel = level;
  }

  static void setMockPosition(double lat, double lng) {
    _mockPosition = Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: 0,
      altitude: 0,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
      altitudeAccuracy: 0,
      headingAccuracy: 0,
    );
  }

  static void clearMockPosition() {
    _mockPosition = null;
  }

  static void setUseMockService(bool value) {
    _useMockService = value;
  }

  static bool get isMockService => _useMockService;

  static const String _baseUrl = "http://192.168.4.1";

  static Future<bool> checkInternetConnection() async {
    if (_useMockService) {
      // Mock internet connection (randomly fail sometimes if we wanted, but let's say true for now)
      return true;
    }
    try {
      return await InternetConnectionChecker().hasConnection;
    } catch (e) {
      print("Error checking internet connection: $e");
      return false;
    }
  }

  static Future<Position?> getCurrentLocation() async {
    if (_useMockService && _mockPosition != null) return _mockPosition;

    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled don't continue
      // accessing the position and request users of the
      // App to enable the location services.
      return null;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Permissions are denied, next time you could try
        // requesting permissions again (this is also where
        // Android's shouldShowRequestPermissionRationale
        // returned true. According to Android guidelines
        // your App should show an explanatory UI now.
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Permissions are denied forever, handle appropriately.
      return null;
    }

    // When we reach here, permissions are granted and we can
    // continue accessing the position of the device.
    return await Geolocator.getCurrentPosition();
  }

  static Future<Boat> getBoatStatus(String id) async {
    if (_useMockService) {
      await Future.delayed(const Duration(milliseconds: 800));
      return Boat(
        id: id,
        name: "Raja's Boat",
        batteryLevel: _mockBatteryLevel,
        connection: {'wifi': true, 'lora': false, 'mesh': 3},
        lastFix: _mockPosition != null
            ? {'lat': _mockPosition!.latitude, 'lng': _mockPosition!.longitude}
            : {'lat': 13.0827, 'lng': 80.2707},
        gpsStatus: "LOCKED",
      );
    } else {
      try {
        final response = await http
            .get(Uri.parse('$_baseUrl/status'))
            .timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          return Boat(
            id: data['id'] ?? id,
            name: data['name'] ?? "Unknown Boat",
            batteryLevel: data['battery'] ?? 0,
            connection: data['connection'] ?? {},
            lastFix: data['lastFix'] ?? {},
            gpsStatus: data['gpsStatus'] ?? "UNKNOWN",
          );
        }
      } catch (e) {
        print("Error getting boat status: $e");
      }
      // Return a default/error boat if failed
      return Boat(
        id: id,
        name: "Connection Failed",
        batteryLevel: 0,
        connection: {'wifi': false, 'lora': false, 'mesh': 0},
        lastFix: {},
        gpsStatus: "UNKNOWN",
      );
    }
  }

  static Future<List<NearbyBoat>> scanMesh() async {
    if (_useMockService) {
      await Future.delayed(const Duration(milliseconds: 2000));

      // Mock response from GET /nearby
      final mockResponse = {
        "boats": [
          {
            "boat_id": "101",
            "user_id": 55,
            "display_name": "Kumar",
            "lat": 13.0850,
            "lon": 80.2700,
            "age_sec": 15,
            "battery": 85,
            "speed_cms": 0,
            "heading_cdeg": 0,
          },
          {
            "boat_id": "102",
            "user_id": 0,
            "display_name": "Joe",
            "lat": 13.0800,
            "lon": 80.2750,
            "age_sec": 120,
            "battery": 60,
            "speed_cms": 150,
            "heading_cdeg": 18000,
          },
        ],
      };
      // Mock current location (Chennai)
      final myLat = 13.0827;
      final myLon = 80.2707;

      final List<dynamic> boatsJson = mockResponse['boats'] as List;
      return boatsJson
          .map((json) => NearbyBoat.fromJson(json, myLat, myLon))
          .toList();
    } else {
      try {
        final response = await http
            .get(Uri.parse('$_baseUrl/nearby'))
            .timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final List<dynamic> boatsJson = data['boats'] as List;
          // For real implementation, we need real current location.
          // For now, hardcoding Chennai as per mock to keep it simple or we need LocationService.
          // Let's use the same hardcoded location for consistency.
          final myLat = 13.0827;
          final myLon = 80.2707;
          return boatsJson
              .map((json) => NearbyBoat.fromJson(json, myLat, myLon))
              .toList();
        }
      } catch (e) {
        print("Error scanning mesh: $e");
      }
      return [];
    }
  }

  // --- Pairing Flow Mocks ---

  static Future<String> getBoatId() async {
    // This is usually a backend call, so we keep it mock/simulated for now even in "Real" mode
    // unless there is a specific backend endpoint.
    await Future.delayed(const Duration(milliseconds: 500));
    return "1234";
  }

  static Future<bool> scanForPairingDevices() async {
    if (_useMockService) {
      await Future.delayed(const Duration(seconds: 2));
      return true;
    } else {
      try {
        // 1. Check Location Service
        final canScan = await WiFiScan.instance.canStartScan();
        if (canScan == CanStartScan.noLocationServiceDisabled) {
          throw Exception("Location Service is disabled");
        } else if (canScan == CanStartScan.noLocationPermissionDenied ||
            canScan == CanStartScan.noLocationPermissionUpgradeAccuracy) {
          throw Exception("Location Permission denied");
        }

        // 2. Check WiFi
        // wifi_iot's isEnabled is still useful for a quick check, but wifi_scan's canStartScan is authoritative for scanning.
        // However, canStartScan might return 'yes' even if wifi is off on some devices if "Always allow scanning" is on.
        // But if we need to connect later, we definitely need WiFi on.
        bool isEnabled = await WiFiForIoTPlugin.isEnabled();
        if (!isEnabled) {
          // Try to enable
          await WiFiForIoTPlugin.setEnabled(true);
          // Recheck
          isEnabled = await WiFiForIoTPlugin.isEnabled();
          if (!isEnabled) {
            throw Exception("WiFi is disabled");
          }
        }

        // 3. Start Scan
        // We re-check canScan just to be safe or if state changed
        final canScanFinal = await WiFiScan.instance.canStartScan();
        if (canScanFinal == CanStartScan.yes) {
          await WiFiScan.instance.startScan();
        } else {
          // If we can't scan for other reasons (e.g. throttling), we might still try to get results
          // but let's log it.
          print("Cannot start scan: $canScanFinal");
        }

        // Get scanned results
        final List<WiFiAccessPoint> networks = await WiFiScan.instance
            .getScannedResults();

        // Look for our specific AP SSID pattern
        // The mock firmware uses "BOAT-PAIR-1234"
        return networks.any((network) => network.ssid.startsWith("BOAT-PAIR-"));
      } catch (e) {
        // Re-throw known exceptions so UI can handle them
        if (e.toString().contains("Location Service") ||
            e.toString().contains("Location Permission") ||
            e.toString().contains("WiFi is disabled")) {
          rethrow;
        }
        print("Error scanning for devices: $e");
        return false;
      }
    }
  }

  static Future<void> connectToDeviceWifi(String password) async {
    if (_useMockService) {
      await Future.delayed(const Duration(seconds: 2));
      debugPrint("Connected to device WiFi with password: $password");
    } else {
      try {
        // We need to find the SSID again or pass it.
        // For simplicity, we'll scan and find the first matching one.
        // Using wifi_scan for scanning
        final canScan = await WiFiScan.instance.canStartScan();
        if (canScan == CanStartScan.yes) {
          await WiFiScan.instance.startScan();
        }
        final List<WiFiAccessPoint> networks = await WiFiScan.instance
            .getScannedResults();

        WiFiAccessPoint? targetNetwork;
        try {
          targetNetwork = networks.firstWhere(
            (network) => network.ssid.startsWith("BOAT-PAIR-"),
          );
        } catch (e) {
          // Not found
          targetNetwork = null;
        }

        if (targetNetwork != null && targetNetwork.ssid.isNotEmpty) {
          await WiFiForIoTPlugin.connect(
            targetNetwork.ssid,
            password: password,
            security: NetworkSecurity.WPA,
            joinOnce: true,
          );

          // Force traffic to go through WiFi since it has no internet
          await WiFiForIoTPlugin.forceWifiUsage(true);

          print("Connected to ${targetNetwork.ssid}");
          // Wait a bit for connection to stabilize
          await Future.delayed(const Duration(seconds: 3));
        } else {
          print("Target network not found for connection");
        }
      } catch (e) {
        print("Error connecting to WiFi: $e");
      }
    }
  }

  static Future<bool> pairDevice({
    required String boatId,
    required int userId,
    required String displayName,
  }) async {
    if (_useMockService) {
      await Future.delayed(const Duration(seconds: 1));
      print(
        "Pairing request sent: boat_id=$boatId, user_id=$userId, name=$displayName",
      );
      return true;
    } else {
      try {
        final response = await http
            .post(
              Uri.parse('$_baseUrl/pair'),
              body: {
                'boat_id': boatId,
                'user_id': userId.toString(),
                'name': displayName,
              },
            )
            .timeout(const Duration(seconds: 5));

        return response.statusCode == 200;
      } catch (e) {
        print("Error pairing device: $e");
        return false;
      }
    }
  }

  static Future<void> notifyPairingSuccess() async {
    await Future.delayed(const Duration(milliseconds: 500));
    print("Notified device of pairing success");
  }

  static Future<void> unpairDevice() async {
    if (_useMockService) {
      await Future.delayed(const Duration(seconds: 1));
      print("Device reset request sent");
    } else {
      try {
        final response = await http
            .post(Uri.parse('$_baseUrl/reset'))
            .timeout(const Duration(seconds: 5));
        // Reset wifi usage first to allow routing to recover
        await WiFiForIoTPlugin.forceWifiUsage(false);

        // Explicitly disconnect from the Boat WiFi
        await WiFiForIoTPlugin.disconnect();
        print("Disconnected from Boat WiFi");
      } catch (e) {
        // Even if request fails, we should probably reset wifi usage if we are done
        await WiFiForIoTPlugin.forceWifiUsage(false);
        await WiFiForIoTPlugin.disconnect();
        print("Error unpairing device: $e");
      }
    }
  }
}
