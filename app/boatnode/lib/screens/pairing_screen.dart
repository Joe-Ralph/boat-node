import 'package:flutter/material.dart';
import 'package:boatnode/l10n/app_localizations.dart';
import 'package:boatnode/services/hardware_service.dart';
import 'package:boatnode/services/auth_service.dart';
import 'package:boatnode/services/session_service.dart';
import 'package:boatnode/theme/app_theme.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

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
    _pulseController.dispose();
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
      // 1. Get boat ID from server
      final boatId = await HardwareService.getBoatId();

      // Request Location Permission for Wi-Fi scanning
      var status = await Permission.location.status;
      if (!status.isGranted) {
        status = await Permission.location.request();
      }

      // Request Nearby Wifi Devices Permission (Android 13+)
      if (await Permission.nearbyWifiDevices.status.isDenied) {
        await Permission.nearbyWifiDevices.request();
      }

      if (!await Permission.location.isGranted &&
          !await Permission.nearbyWifiDevices.isGranted) {
        throw Exception(
          "Location or Nearby Devices permission is required for Wi-Fi scanning",
        );
      }

      // 2. Scan for Wi-Fi networks with prefix 'BOAT-PAIR-'
      final deviceFound = await HardwareService.scanForPairingDevices();

      if (!mounted) return;

      if (!deviceFound) {
        setState(() {
          _statusMessage = AppLocalizations.of(
            context,
          )!.translate('noDevicesFound');
          _isScanning = false;
          _pulseController.stop();
        });
        return;
      }

      setState(() {
        _isScanning = false;
        _isPairing = true;
        _statusMessage = AppLocalizations.of(
          context,
        )!.translate('connectingToDevice');
      });

      // 3. Connect to the device's Wi-Fi
      await HardwareService.connectToDeviceWifi('pairme-1234');

      // 4. Send pairing request
      final user = await AuthService.getCurrentUser();
      if (user == null) throw Exception('User not logged in');

      // Validate boatId is numeric and within uint16 range
      final boatIdInt = int.tryParse(boatId);
      if (boatIdInt == null || boatIdInt < 0 || boatIdInt > 65535) {
        throw Exception(
          'Invalid Boat ID: Must be a number between 0 and 65535',
        );
      }

      final result = await HardwareService.pairDevice(
        boatId: boatId,
        userId: user.id,
        displayName: user.displayName,
      );

      if (!mounted) return;

      if (result) {
        // Save pairing state
        await SessionService.savePairingState(true, boatId);

        setState(() {
          _isPaired = true;
          _statusMessage = AppLocalizations.of(
            context,
          )!.translate('pairingSuccessful');
          _pulseController.stop();
        });

        // Notify device to show success (long blue flash)
        await HardwareService.notifyPairingSuccess();

        // Return to dashboard after a delay
        if (mounted) {
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) {
            Navigator.pop(context, true); // Return success
          }
        }
      } else {
        throw Exception('Pairing failed');
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isScanning = false;
        _isPairing = false;
        _pulseController.stop();
      });

      String errorMessage = e.toString();
      // Clean up exception message
      if (errorMessage.startsWith("Exception: ")) {
        errorMessage = errorMessage.substring(11);
      }

      if (errorMessage.contains("Location Service is disabled")) {
        _showLocationServiceDialog();
      } else if (errorMessage.contains("Location Permission denied")) {
        _showPermissionDialog();
      } else if (errorMessage.contains("WiFi is disabled")) {
        _statusMessage = AppLocalizations.of(context)!.translate('enableWifi');
      } else {
        _statusMessage =
            '${AppLocalizations.of(context)!.translate('pairingFailed')}: $errorMessage';
      }
    }
  }

  void _showLocationServiceDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          AppLocalizations.of(context)!.translate('locationRequired'),
        ),
        content: Text(
          AppLocalizations.of(context)!.translate('enableLocationMessage'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.translate('cancel')),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Geolocator.openLocationSettings();
            },
            child: Text(AppLocalizations.of(context)!.translate('settings')),
          ),
        ],
      ),
    );
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          AppLocalizations.of(context)!.translate('permissionRequired'),
        ),
        content: Text(
          AppLocalizations.of(context)!.translate('grantLocationPermission'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.translate('cancel')),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: Text(AppLocalizations.of(context)!.translate('settings')),
          ),
        ],
      ),
    );
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated Icon
            Stack(
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
            const SizedBox(height: 48),

            // Status Text
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
            const SizedBox(height: 16),
            if (!_isScanning && !_isPairing && !_isPaired)
              Text(
                AppLocalizations.of(
                  context,
                )!.translate('makeSureDevicePowered'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: kZinc500),
              ),

            const Spacer(),

            // Action Button
            if (!_isPaired)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_isScanning || _isPairing) ? null : _startPairing,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kBlue600,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isScanning || _isPairing
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
                              )!.translate('pleaseWait'),
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          AppLocalizations.of(
                            context,
                          )!.translate('startPairing'),
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            if (_isPaired)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kGreen500,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    AppLocalizations.of(context)!.translate('done'),
                    style: const TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
