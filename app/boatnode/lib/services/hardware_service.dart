import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'package:geolocator/geolocator.dart';
import '../models/boat.dart';
import '../models/nearby_boat.dart';
import 'package:boatnode/services/log_service.dart';
import 'package:boatnode/services/auth_service.dart';
import 'package:boatnode/utils/boat_utils.dart';

class HardwareService {
  static bool _useMockService = false; // Default false to test BLE
  static bool _simulateConnectionFailure = false;
  static int _mockBatteryLevel = 85;
  static Position? _mockPosition;

  static void setSimulateConnectionFailure(bool value) {
    _simulateConnectionFailure = value;
  }

  static bool get isConnectionFailureSimulated => _simulateConnectionFailure;

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

  // UUIDs
  static const String _serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  static const String _dataCharUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
  static const String _cmdCharUuid = "8246d623-6447-4ec6-8c46-d2432924151a";

  static BluetoothDevice? _connectedDevice;
  static BluetoothCharacteristic? _dataChar;
  static BluetoothCharacteristic? _cmdChar;
  static StreamSubscription? _dataSubscription;

  static void setUseMockService(bool value) {
    _useMockService = value;
  }

  static bool get isMockService => _useMockService;
  static bool get isConnected => _connectedDevice != null;

  static Future<bool> checkInternetConnection() async {
    // BLE doesn't provide internet.
    // This check is for the Phone's 4G/WiFi connection to the backend.
    if (_useMockService) return true;
    try {
      return await InternetConnectionChecker().hasConnection;
    } catch (e) {
      LogService.e("Error checking internet connection", e);
      return false;
    }
  }

  // --- BLE Methods ---

  static final StreamController<List<ScanResult>> _scanResultsController =
      StreamController<List<ScanResult>>.broadcast();

  static Stream<List<ScanResult>> get scanResults =>
      _scanResultsController.stream;

  static StreamSubscription? _flutterBlueScanSubscription;

  static Future<void> startScan() async {
    if (_useMockService) return;

    // 1. Get already connected devices (from System)
    List<BluetoothDevice> systemDevices = [];
    try {
      systemDevices = await FlutterBluePlus.systemDevices([Guid(_serviceUuid)]);
    } catch (e) {
      LogService.w("Could not get system devices: $e");
    }

    // Convert to ScanResults so UI can use them directly
    List<ScanResult> connectedResults = systemDevices.map((d) {
      return ScanResult(
        device: d,
        advertisementData: AdvertisementData(
          advName: d.platformName,
          txPowerLevel: null,
          connectable: true,
          manufacturerData: {},
          serviceUuids: [],
          serviceData: {},
          appearance: null,
        ),
        rssi: 0,
        timeStamp: DateTime.now(),
      );
    }).toList();

    // Emit initial list
    _scanResultsController.add(connectedResults);

    // 2. Start Scanning
    try {
      await FlutterBluePlus.startScan(
        withServices: [Guid(_serviceUuid)],
        timeout: const Duration(seconds: 15),
      );

      // 3. Merge streams
      _flutterBlueScanSubscription?.cancel();
      _flutterBlueScanSubscription = FlutterBluePlus.scanResults.listen(
        (scannedResults) {
          // Merge connectedResults and scannedResults
          // Avoid duplicates based on remoteId
          final Set<String> existingIds = connectedResults
              .map((r) => r.device.remoteId.toString())
              .toSet();

          final List<ScanResult> merged = List.from(connectedResults);
          for (var r in scannedResults) {
            if (!existingIds.contains(r.device.remoteId.toString())) {
              merged.add(r);
            }
          }
          _scanResultsController.add(merged);
        },
        onError: (e) {
          LogService.e("Scan stream error", e);
        },
      );
    } catch (e) {
      LogService.e("Start scan error", e);
    }
  }

  static Future<void> stopScan() async {
    if (_useMockService) return;
    await _flutterBlueScanSubscription?.cancel();
    _flutterBlueScanSubscription = null;
    await FlutterBluePlus.stopScan();
  }

  static final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();

  static Stream<bool> get connectionState => _connectionStateController.stream;

  // Track device subscription to handle accidental disconnects
  static StreamSubscription<BluetoothConnectionState>? _deviceStateSubscription;

  static Future<void> connectToDevice(BluetoothDevice device) async {
    if (_useMockService) {
      _connectedDevice = device; // Mock
      _connectionStateController.add(true);
      return;
    }

    // Stop scanning before connecting to ensure clean state
    await stopScan();
    // Android often needs a breather between scan stop and connect to avoid GATT 133
    await Future.delayed(const Duration(milliseconds: 500));

    int retries = 3;
    while (retries > 0) {
      try {
        await device.connect(autoConnect: false);
        break; // Connected successfully
      } catch (e) {
        retries--;
        LogService.w("Connection failed, retrying... ($retries attempts left)");
        await device.disconnect(); // Ensure clean slate
        await Future.delayed(const Duration(seconds: 1)); // Wait before retry
        if (retries == 0) {
          _connectedDevice = null;
          _connectionStateController.add(false);
          rethrow;
        }
      }
    }

    _connectedDevice = device;
    _connectionStateController.add(true);

    // Listen for disconnects
    _deviceStateSubscription?.cancel();
    _deviceStateSubscription = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        LogService.i("Device Disconnected Unexpectedly");
        _connectedDevice = null;
        _connectionStateController.add(false);
        _deviceStateSubscription?.cancel();
      }
    });

    try {
      // Discover Services
      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        if (service.uuid.toString() == _serviceUuid) {
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid.toString() == _dataCharUuid) {
              _dataChar = characteristic;
              // Subscribe to notifications
              await _dataChar!.setNotifyValue(true);
              _dataSubscription = _dataChar!.onValueReceived.listen(
                _onDataReceived,
              );
            } else if (characteristic.uuid.toString() == _cmdCharUuid) {
              _cmdChar = characteristic;
            }
          }
        }
      }
      LogService.i("Connected to BLE Device: ${device.platformName}");
    } catch (e) {
      LogService.e("Error discovering services", e);
      await device.disconnect();
      _connectedDevice = null;
      _connectionStateController.add(false);
      rethrow;
    }
  }

  static Future<void> disconnect() async {
    if (_connectedDevice != null) {
      await _dataSubscription?.cancel();
      await _deviceStateSubscription?.cancel(); // Stop listening to state
      await _connectedDevice!.disconnect();
      _connectedDevice = null;
      _dataChar = null;
      _cmdChar = null;
      _connectionStateController.add(false);
    }
  }

  static final StreamController<String> _loraStatusController =
      StreamController<String>.broadcast();
  static Stream<String> get loraStatus => _loraStatusController.stream;

  static Map<String, dynamic> _lastBleData = {};

  static void _onDataReceived(List<int> value) {
    String data = utf8.decode(value);
    LogService.d("BLE Data Received: $data");

    try {
      // Expected Format: S:4,Lat:13.0,Lon:80.2,Bat:95,St:Joined
      List<String> parts = data.split(',');
      for (var part in parts) {
        var kv = part.split(':');
        if (kv.length == 2) {
          String key = kv[0].trim();
          String val = kv[1].trim();
          _lastBleData[key] = val;

          // Check for Status Update
          if (key == 'St') {
            _loraStatusController.add(val);
          }
        }
      }
    } catch (e) {
      LogService.e("Error parsing BLE data", e);
    }
  }

  // --- Boat Data Methods ---

  static Future<Boat> getBoatStatus(String id) async {
    if (_simulateConnectionFailure) {
      await Future.delayed(const Duration(milliseconds: 500));
      return Boat(
        id: id,
        name: "Connection Failed",
        batteryLevel: 0,
        connection: {'ble': false, 'lora': false},
        lastFix: {},
        gpsStatus: "UNKNOWN",
      );
    }

    if (_useMockService) {
      // Return Mock Data
      await Future.delayed(const Duration(milliseconds: 800));
      final user = await AuthService.getCurrentUser();
      final boatName = BoatUtils.getDynamicBoatName(user?.displayName);
      return Boat(
        id: id,
        name: boatName,
        batteryLevel: _mockBatteryLevel,
        connection: {'ble': true, 'lora': false, 'mesh': 3},
        lastFix: _mockPosition != null
            ? {'lat': _mockPosition!.latitude, 'lng': _mockPosition!.longitude}
            : {'lat': 13.0827, 'lng': 80.2707},
        gpsStatus: "LOCKED",
      );
    }

    // Real BLE: We rely on the last notified data.
    // Since this method is usually polled or called once,
    // we should return the latest cached state from BLE notifications.
    // For this simple migration, let's assume we aren't fully parsing yet
    // or return a placeholder if not connected.

    if (_connectedDevice == null) {
      return Boat(
        id: id,
        name: "Not Connected",
        batteryLevel: 0,
        connection: {'ble': false},
        lastFix: {},
        gpsStatus: "DISCONNECTED",
      );
    }

    // Parse cached BLE data
    double lat = double.tryParse(_lastBleData['Lat'] ?? '0') ?? 0.0;
    double lon = double.tryParse(_lastBleData['Lon'] ?? '0') ?? 0.0;
    int bat = int.tryParse(_lastBleData['Bat'] ?? '0') ?? 0;
    String loraStatus = _lastBleData['St'] ?? "Unknown";
    int sats = int.tryParse(_lastBleData['S'] ?? '0') ?? 0;
    String gpsStatus = (lat != 0 && lon != 0)
        ? "LOCKED ($sats)"
        : "SEARCHING ($sats)";

    return Boat(
      id: id,
      name: _connectedDevice!.platformName,
      batteryLevel: bat,
      connection: {
        'ble': true,
        'lora':
            loraStatus.toLowerCase().contains("joined") ||
            loraStatus.toLowerCase().contains("ready"),
      },
      lastFix: {'lat': lat, 'lng': lon},
      gpsStatus: gpsStatus,
    );
  }

  // --- Pairing Methods ---

  static Future<bool> pairDevice({
    required String boatId,
    required int userId,
    required String displayName,
  }) async {
    if (_useMockService) {
      await Future.delayed(const Duration(seconds: 1));
      return true;
    }

    if (_cmdChar == null) {
      LogService.e("Command Characteristic not found");
      return false;
    }

    try {
      // Format: SET:boat_id:user_id:name
      String cmd = "SET:$boatId:$userId:$displayName";
      await _cmdChar!.write(utf8.encode(cmd));
      LogService.i("Sent Configuration: $cmd");
      return true;
    } catch (e) {
      LogService.e("Error writing to config char", e);
      return false;
    }
  }

  static Future<void> unpairDevice() async {
    await disconnect();
    LogService.i("Device Unpaired");
  }

  static Future<void> notifyPairingSuccess() async {
    // Optional: Send a command to BLE to flash LED or purely UI feedback
    LogService.i("Pairing Success Notification");
    // If we had a specific command:
    // await _cmdChar?.write(utf8.encode("PAIR_SUCCESS"));
  }

  static Future<bool> startJourney() async {
    if (_useMockService) {
      LogService.i("Mock Journey Started");
      return true;
    }
    if (_cmdChar == null) return false;
    try {
      await _cmdChar!.write(utf8.encode("START_JOURNEY"));
      LogService.i("Sent START_JOURNEY");
      return true;
    } catch (e) {
      LogService.e("Error sending START_JOURNEY", e);
      return false;
    }
  }

  static Future<bool> endJourney() async {
    if (_useMockService) {
      LogService.i("Mock Journey Ended");
      return true;
    }
    if (_cmdChar == null) return false;
    try {
      await _cmdChar!.write(utf8.encode("END_JOURNEY"));
      LogService.i("Sent END_JOURNEY");
      return true;
    } catch (e) {
      LogService.e("Error sending END_JOURNEY", e);
      return false;
    }
  }

  // --- Scan for Nearby Boats (Mesh) ---
  static Future<List<NearbyBoat>> scanMesh() async {
    // This would come from BLE notifications interpreted as Mesh Packets
    // For now, return empty or mock if requested.
    if (_useMockService) {
      // ... (Keep existing mock logic if needed or simplify)
      return [];
    }
    return [];
  }

  // --- Helpers ---

  static Future<Position?> getCurrentLocation() async {
    return await Geolocator.getCurrentPosition();
  }
}
