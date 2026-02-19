import 'dart:async';

import 'package:flutter/material.dart';
import 'package:boatnode/l10n/app_localizations.dart';
import 'package:boatnode/services/hardware_service.dart';
import 'package:boatnode/services/auth_service.dart';
import 'package:boatnode/services/session_service.dart';
import 'package:boatnode/services/backend_service.dart';
import 'package:boatnode/theme/app_theme.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:boatnode/services/log_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen>
    with SingleTickerProviderStateMixin {
  bool _isScanning = false;
  bool _isPairing = false;
  String? _statusMessage;
  bool _isPaired = false;
  late AnimationController _pulseController;

  // ignore: unused_field
  StreamSubscription? _scanSubscription;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _pulseController.dispose();
    HardwareService.stopScan();
    super.dispose();
  }

  Future<void> _startPairing() async {
    setState(() {
      _isScanning = true;
      _statusMessage = AppLocalizations.of(
        context,
      )!.translate('scanningForDevices');
      _pulseController.repeat();
    });

    try {
      // 1. Permissions
      // We need Location (for BLE on older Android) and Bluetooth Scan/Connect
      Map<Permission, PermissionStatus> statuses = await [
        Permission.location,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission
            .bluetooth, // For iOS often covered by plist but good to check
      ].request();

      // Check if critical permissions are granted
      bool locationGranted = statuses[Permission.location]!.isGranted;
      bool bleGranted =
          (statuses[Permission.bluetoothScan]?.isGranted ?? true) &&
          (statuses[Permission.bluetoothConnect]?.isGranted ?? true);

      if (!locationGranted && !bleGranted) {
        // Handle permission denial
        throw Exception("Bluetooth and Location permissions are required.");
      }

      // 2. Start Scan
      await HardwareService.startScan();

      // The UI will update via StreamBuilder on scanResults
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _pulseController.stop();
        _statusMessage = "Error: $e";
      });
    }
  }

  Future<void> _onDeviceSelected(BluetoothDevice device) async {
    HardwareService.stopScan();
    setState(() {
      _isScanning = false;
      _isPairing = true;
      _statusMessage = AppLocalizations.of(
        context,
      )!.translate('connectingToDevice');
    });

    try {
      // 1. Connect
      await HardwareService.connectToDevice(device);

      // 2. Pair / Configure
      // Get User Info
      final user = await AuthService.getCurrentUser();
      String boatId = "1001"; // Default or fetch from backend

      try {
        final boats = await BackendService.getUserBoats(user?.id ?? "0");
        if (boats.isNotEmpty) boatId = boats.first['id'].toString();
      } catch (e) {
        LogService.w("Could not fetch boat ID, using default/generated");
      }

      final result = await HardwareService.pairDevice(
        boatId: boatId,
        userId: int.tryParse(user?.id ?? "0") ?? 0,
        displayName: user?.displayName ?? "User",
      );

      if (result) {
        await SessionService.savePairingState(true, boatId);
        setState(() {
          _isPaired = true;
          _statusMessage = AppLocalizations.of(
            context,
          )!.translate('pairingSuccessful');
          _pulseController.stop();
        });

        if (mounted) {
          await Future.delayed(const Duration(seconds: 2));
          Navigator.of(context).pop(true);
        }
      } else {
        throw Exception("Configuration Failed");
      }
    } catch (e) {
      setState(() {
        _isPairing = false;
        _statusMessage = "Pairing Failed: $e";
        _pulseController.stop();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kZinc950,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.translate('pairDevice')),
        backgroundColor: kZinc950,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            children: [
              // Animation / Icon Area
              SizedBox(
                height: 150,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_isScanning || _isPairing)
                      ScaleTransition(
                        scale: Tween(begin: 1.0, end: 1.5).animate(
                          CurvedAnimation(
                            parent: _pulseController,
                            curve: Curves.easeOut,
                          ),
                        ),
                        child: FadeTransition(
                          opacity: Tween(begin: 0.5, end: 0.0).animate(
                            CurvedAnimation(
                              parent: _pulseController,
                              curve: Curves.easeOut,
                            ),
                          ),
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: kBlue600.withOpacity(0.5),
                            ),
                          ),
                        ),
                      ),
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isPaired ? kGreen500 : kZinc800,
                      ),
                      child: Icon(
                        _isPaired ? Icons.check : Icons.bluetooth_searching,
                        size: 48,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

              Text(
                _statusMessage ??
                    AppLocalizations.of(
                      context,
                    )!.translate('pairingInstructions'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),

              const SizedBox(height: 24),

              // Device List
              if (_isScanning)
                Expanded(
                  child: StreamBuilder<List<ScanResult>>(
                    stream: HardwareService.scanResults,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return Center(
                          child: Text(
                            "Searching...",
                            style: TextStyle(color: kZinc500),
                          ),
                        );
                      }

                      final results = snapshot.data!;
                      return ListView.builder(
                        itemCount: results.length,
                        itemBuilder: (context, index) {
                          final r = results[index];
                          String name = r.device.platformName.isNotEmpty
                              ? r.device.platformName
                              : "Unknown Device";
                          return Card(
                            color: kZinc900,
                            child: ListTile(
                              title: Text(
                                name,
                                style: TextStyle(color: Colors.white),
                              ),
                              subtitle: Text(
                                r.device.remoteId.toString(),
                                style: TextStyle(color: kZinc500),
                              ),
                              trailing: ElevatedButton(
                                child: Text("Connect"),
                                onPressed: () => _onDeviceSelected(r.device),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),

              if (!_isScanning && !_isPaired && !_isPairing)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _startPairing,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kBlue600,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      AppLocalizations.of(context)!.translate('startPairing'),
                      style: const TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
