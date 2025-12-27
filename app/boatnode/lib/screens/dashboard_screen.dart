import 'dart:async';
import 'package:boatnode/models/boat.dart';
import 'package:boatnode/screens/nearby_screen.dart';
import 'package:boatnode/screens/rescue_screen.dart';
import 'package:boatnode/screens/settings_screen.dart';
import 'package:boatnode/screens/pairing_screen.dart';
import 'package:boatnode/services/hardware_service.dart';
import 'package:boatnode/theme/app_theme.dart';
import 'package:boatnode/l10n/app_localizations.dart';
import 'package:boatnode/services/session_service.dart';
import 'package:boatnode/services/notification_service.dart';
import 'package:boatnode/services/backend_service.dart'; // Added for GPS sync
import 'package:boatnode/services/map_service.dart';
import 'package:boatnode/services/log_service.dart';
import 'package:boatnode/services/geofence_service.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/material.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'package:boatnode/services/auth_service.dart';
import 'package:boatnode/models/user.dart';
import 'package:boatnode/screens/qr_scan_screen.dart';
import 'package:boatnode/screens/qr_code_screen.dart';
import 'package:geolocator/geolocator.dart';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/ui_utils.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Boat? _boat;
  Timer? _statusTimer;
  DateTime? _lastUpdated;
  bool _hasInternet = false;
  Position? _currentPosition;
  bool _isNearBorder = false;
  bool _isConnecting = false;
  bool _isProcessingJourney = false;

  User? _user;

  @override
  void initState() {
    super.initState();
    NotificationService().init();
    _checkInternet();
    _loadData();
    _startStatusTimer();
    _setupCallKitListener();
  }

  void _setupCallKitListener() {
    FlutterCallkitIncoming.onEvent.listen((event) {
      if (event != null && event.event == Event.actionCallAccept) {
        _handleAcceptedCall(event.body);
      }
    });

    // Check if app was launched from a call
    _checkLastCall();
  }

  Future<void> _checkLastCall() async {
    var calls = await FlutterCallkitIncoming.activeCalls();
    if (calls is List && calls.isNotEmpty) {
      // Loop or pick first? Usually handled by event, but if missed:
      // _handleAcceptedCall(calls.first);
    }
  }

  void _handleAcceptedCall(Map<dynamic, dynamic> body) {
    LogService.i("SOS Call Accepted: $body");
    // Extract location
    if (body['extra'] != null) {
      final lat = body['extra']['lat'];
      final long = body['extra']['long'];
      if (lat != null && long != null) {
        // Navigate to NearbyScreen or Map
        // For simplicity, we assume NearbyScreen can handle showing this location or we pass it
        // We'll pass it as arguments or modify NearbyScreen to accept target.
        // For now, let's just push NearbyScreen.
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NearbyScreen()),
        );
      }
    }
  }

  void _startStatusTimer() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(
      Duration(
        seconds: SessionService.isPaired
            ? SessionService.statusInterval
            : SessionService.gpsUpdateInterval,
      ),
      (timer) {
        if (mounted) {
          _loadData();
          _checkInternet();
        }
      },
    );
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkInternet() async {
    final hasInternet = await InternetConnectionChecker().hasConnection;
    if (mounted) {
      setState(() {
        _hasInternet = hasInternet;
      });
    }
  }

  Future<void> _loadData() async {
    final user = await AuthService.getCurrentUser();
    if (mounted) {
      setState(() {
        _user = user;

        // New Logic: If Owner and no Boat ID known, fetch from backend and persist
        if (user != null && user.role == 'owner' && user.boatId == null) {
          BackendService.getUserBoats(user.id)
              .then((boats) async {
                if (boats.isNotEmpty) {
                  final boatId = boats.first['id'].toString();
                  // Update local user object
                  final updatedUser = user.copyWith(boatId: boatId);
                  setState(
                    () => _user = updatedUser,
                  ); // Update state with new user
                  // Persist updated user
                  await SessionService.saveUser(updatedUser);
                  LogService.i(
                    "Dashboard: Fetched and persisted Boat ID: $boatId",
                  );
                }
              })
              .catchError((e) {
                LogService.e("Dashboard: Failed to fetch user boats", e);
              });
        }
      });
    }

    // Unpaired + Journey Active = Use phone GPS and upload to backend
    if (!SessionService.isPaired && SessionService.isJourneyActive) {
      HardwareService.getCurrentLocation().then((position) {
        if (mounted) {
          setState(() {
            _currentPosition = position;
            _lastUpdated = DateTime.now(); // Update localized "Updated" time
          });
        }
        // Upload to Backend if we have a valid position and user is logged in
        if (position != null && _user != null && _user!.boatId != null) {
          // We use the user's boatId to tag the location
          BackendService.updateLiveLocation(
            lat: position.latitude,
            lon: position.longitude,
            battery:
                100, // Phone battery not easily accessible without package, mocking 100
            boatId: _user!.boatId!,
            speed: position.speed,
            heading: position.heading,
          ).catchError((e) {
            LogService.e("Dashboard: Error uploading live location", e);
          });
        }
      });
      // If journey is active and unpaired, we handle location updates here and don't proceed to fetch boat status.
      // The return statement ensures we don't try to fetch boat status from a device that isn't paired.
      return;
    }

    // Paired Mode = Fetch status from device (Existing)
    if (!SessionService.isPaired) {
      final position = await HardwareService.getCurrentLocation();
      if (mounted) {
        setState(() {
          _boat = null;
          _currentPosition = position;
          if (position != null) {
            _lastUpdated = DateTime.now();
          }
        });
      }
      return;
    }

    // --- Journey Mode Logic (Unpaired) ---
    // Note: With native background service, we might not need this timer-based logic anymore
    // if the background service handles it.
    // However, for immediate feedback while app is open, we can keep it OR rely solely on the service.
    // If we rely on service, we should ensure service is running.
    // Let's keep this for now but maybe reduce frequency or rely on service if active.
    // Actually, if we have a background service, it runs independently.
    // If we duplicate logic here, we might send double updates.
    // So we should REMOVE this block if the background service is doing the work.
    // But the background service runs on a timer (e.g. 30s).
    // Let's disable this block to avoid duplication and rely on the native service.

    /*
    if (!SessionService.isPaired && SessionService.isJourneyActive) {
       // ... (Logic moved to BackgroundService)
    }
    */

    final boat = await HardwareService.getBoatStatus('123');
    if (!mounted) return;
    setState(() {
      _boat = boat;
      _lastUpdated = DateTime.now();
    });

    if (SessionService.isPaired) {
      final title = AppLocalizations.of(context)!.translate('lowBatteryTitle');
      final message = AppLocalizations.of(
        context,
      )!.translate('lowBatteryMessage');
      await NotificationService().checkBatteryAndNotify(
        boat.batteryLevel,
        title,
        message,
      );
    }

    // Check for border proximity
    bool nearBorder = false;
    if (SessionService.isPaired) {
      final lastFix = boat.lastFix;
      if (lastFix['lat'] != null && lastFix['lng'] != null) {
        nearBorder = GeofenceService.isNearBorder(
          LatLng(lastFix['lat'], lastFix['lng']),
        );
      }
    } else if (_currentPosition != null) {
      nearBorder = GeofenceService.isNearBorder(
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
      );
    }

    if (mounted) {
      setState(() {
        _isNearBorder = nearBorder;
      });
    }
  }

  Future<void> _connectToDevice() async {
    setState(() => _isConnecting = true);
    UiUtils.showSnackBar(
      context,
      AppLocalizations.of(context)!.translate('connectingToDevice'),
      duration: const Duration(seconds: 2),
    );

    // Try to connect to the known SSID
    // In a real scenario, we might need to know the specific SSID if it changes per device
    // But assuming 'pairme-1234' is the password for the AP
    await HardwareService.connectToDeviceWifi('pairme-1234');

    // Wait a bit for connection to stabilize
    await Future.delayed(const Duration(seconds: 3));

    // Refresh data to check connection
    await _loadData();

    if (mounted) {
      setState(() => _isConnecting = false);
      if (_boat == null || _boat!.name == "Connection Failed") {
        UiUtils.showSnackBar(
          context,
          "Connection failed. Please ensure device is on.",
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // if (_boat == null) {
    //   return const Scaffold(body: Center(child: CircularProgressIndicator()));
    // }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              if (_isNearBorder)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kRed600,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.redAccent, width: 2),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "BORDER ALERT!",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              "You are approaching the maritime boundary.",
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              _buildStatusCard(),
              const SizedBox(height: 20),
              Expanded(
                child: Column(
                  children: [
                    Expanded(flex: 2, child: _buildJourneyButton()),
                    const SizedBox(height: 12),
                    Expanded(
                      flex: 2,
                      child: Row(
                        children: [
                          Expanded(child: _buildActionGrid()),
                          const SizedBox(width: 12),
                          Expanded(child: _buildRescueButton()),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      flex: 1,
                      child: Row(
                        children: [
                          Expanded(child: _buildSyncButton()),
                          const SizedBox(width: 12),
                          Expanded(child: _buildQRActionButton()),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRescueButton() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: kRed600,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RescueScreen()),
          ),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.support, size: 32, color: Colors.white),
                SizedBox(height: 8),
                Text(
                  AppLocalizations.of(
                    context,
                  )!.translate('rescueMode').toUpperCase(),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  AppLocalizations.of(context)!.translate('broadcastSignal'),
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionGrid() {
    final isPaired = SessionService.isPaired;
    final isConnected = _boat != null && _boat!.name != "Connection Failed";
    final role = _user?.role;

    // Logic for button display
    IconData icon;
    String label;
    VoidCallback onTap;
    bool showLoading = false;

    if (isPaired) {
      // User is associated with a boat
      if (role == 'land_user' || role == 'land_admin') {
        // Land users just track, no connection
        icon = Icons.map;
        label = AppLocalizations.of(
          context,
        )!.translate('nearbyBoats'); // Or "Track Boat"
        onTap = () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NearbyScreen()),
          );
        };
      } else {
        // Owner or Joiner - Can connect to device
        if (isConnected) {
          icon = Icons.radar;
          label = AppLocalizations.of(context)!.translate('nearbyBoats');
          onTap = () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NearbyScreen()),
            );
          };
        } else {
          icon = Icons.wifi_find;
          label = AppLocalizations.of(context)!.translate('connectDevice');
          showLoading = _isConnecting;
          onTap = () async {
            if (!_isConnecting) {
              await _connectToDevice();
            }
          };
        }
      }
    } else {
      // No boat associated
      if (role == 'owner') {
        icon = Icons.link;
        label = AppLocalizations.of(context)!.translate('pairDeviceButton');
        onTap = () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PairingScreen()),
          );
          if (result == true) {
            // Defer success handling to allow pop animation to finish
            if (mounted) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _handlePairingSuccess();
              });
            }
          }
        };
      } else {
        // Joiner or Land User - Scan QR
        icon = Icons.qr_code_scanner;
        label = "Scan QR"; // TODO: Localize
        onTap = () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const QRScanScreen()),
          );
        };
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: isPaired ? (isConnected ? kZinc800 : kBlue600) : kBlue600,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (showLoading)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                else
                  Icon(icon, size: 32, color: Colors.white),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handlePairingSuccess() {
    LogService.i("Dashboard: Pairing success handled.");
    try {
      _loadData();
      _startStatusTimer();
      if (mounted) {
        UiUtils.showSnackBar(
          context,
          "Pairing successful. Caching offline maps...",
        );
        HardwareService.getCurrentLocation().then((pos) {
          if (pos != null && mounted) {
            LogService.i(
              "Dashboard: Caching map area for ${pos.latitude}, ${pos.longitude}",
            );
            MapService.cacheArea(
              context,
              pos.latitude,
              pos.longitude,
            ).catchError((e) {
              LogService.e("Dashboard: Map caching error", e);
            });
          }
        });
      }
    } catch (e) {
      LogService.e("Dashboard: Error in _handlePairingSuccess", e);
    }
  }

  Widget _buildQRActionButton() {
    final bool isOwner = _user?.role == 'owner';
    final bool isPaired = SessionService.isPaired;

    // Determine mode:
    // Owner: ALWAYS Show QR (to let others join)
    // Joiner (Paired): Show QR (to let others track/join same boat)
    // Joiner (Unpaired) / Land: Scan QR (to join a boat)
    final bool showMode = isOwner || (isPaired && _user?.role != 'land_user');

    return Container(
      decoration: BoxDecoration(
        color: kZinc800,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (showMode) {
              // Show QR
              if (_boat != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => QRCodeScreen(boat: _boat!)),
                );
              } else {
                // Try fetching data if IDs are available
                final boatId = SessionService.pairedBoatId ?? _user?.boatId;
                if (boatId != null) {
                  UiUtils.showSnackBar(context, "Fetching boat data...");
                  HardwareService.getBoatStatus(boatId)
                      .then((boat) {
                        if (mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => QRCodeScreen(boat: boat),
                            ),
                          );
                        }
                      })
                      .catchError((e) {
                        if (mounted) {
                          UiUtils.showSnackBar(
                            context,
                            "Failed to load data: $e",
                            isError: true,
                          );
                        }
                      });
                } else {
                  UiUtils.showSnackBar(
                    context,
                    "Boat data not available yet",
                    isError: true,
                  );
                }
              }
            } else {
              // Scan QR
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const QRScanScreen()),
              );
            }
          },
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  showMode ? Icons.qr_code : Icons.qr_code_scanner,
                  size: 24,
                  color: Colors.white,
                ),
                SizedBox(height: 8),
                Text(
                  showMode ? "SHOW QR" : "SCAN QR",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSyncButton() {
    return Container(
      height: double.infinity,
      width: double.infinity,
      decoration: BoxDecoration(
        color: kZinc800,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _loadData,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.refresh, size: 24, color: Colors.white),
                SizedBox(height: 6),
                Text(
                  AppLocalizations.of(
                    context,
                  )!.translate('syncStatus').toUpperCase(),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildJourneyButton() {
    final isJourneyActive = SessionService.isJourneyActive;
    // Only show if unpaired? Or always?
    // "only that period we will transmit the data gps data ... unpaired functionality"
    // So primarily for unpaired mode.
    // if (SessionService.isPaired) {
    //   return const SizedBox.shrink(); // Hide if paired (module handles it)
    // }

    return Container(
      height: double.infinity,
      width: double.infinity,
      decoration: BoxDecoration(
        color: isJourneyActive ? kRed600 : kGreen500,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            if (_isProcessingJourney) return;
            setState(() => _isProcessingJourney = true);

            try {
              // Paired Mode Logic
              if (SessionService.isPaired) {
                // Only connect if we are STARTING a journey
                if (!isJourneyActive) {
                  await _connectToDevice();

                  // Start watchdog
                  Future.delayed(const Duration(seconds: 10), () {
                    if (mounted &&
                        (_boat == null || _boat!.name == "Connection Failed")) {
                      UiUtils.showSnackBar(
                        context,
                        "Unable to connect to device. Retrying...",
                        isError: true,
                      );
                    }
                  });
                }
                // Fall through to toggle logic below
              }

              // Unpaired Mode Logic
              if (!isJourneyActive) {
                // Request Permission FIRST
                var status = await Permission.location.request();
                if (status.isDenied || status.isPermanentlyDenied) {
                  if (mounted) {
                    UiUtils.showSnackBar(
                      context,
                      "Location permission is required for journey tracking.",
                      isError: true,
                    );
                  }
                  return;
                }

                // Check Location Service status BEFORE starting
                bool serviceEnabled =
                    await Geolocator.isLocationServiceEnabled();
                if (!serviceEnabled) {
                  if (mounted) {
                    await showDialog(
                      // await the dialog
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(
                          AppLocalizations.of(
                            context,
                          )!.translate('enableLocation'),
                        ),
                        content: const Text(
                          "Location services are disabled. Please enable them to start a journey.",
                        ),
                        actions: [
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              Geolocator.openLocationSettings();
                            },
                            child: const Text("Open Settings"),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text("Cancel"),
                          ),
                        ],
                      ),
                    );
                  }
                  return;
                }
              }

              // Toggle Journey (Existing logic)
              final newState = !isJourneyActive;
              await SessionService.saveJourneyState(newState);

              // Cache User ID and Boat ID for Background Service
              if (_user != null) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('user_id_cache', _user!.id);
                if (_user!.boatId != null) {
                  await prefs.setString('boat_id_cache', _user!.boatId!);
                }
              }

              final service = FlutterBackgroundService();
              if (newState) {
                await service.startService();
                UiUtils.showSnackBar(
                  context,
                  "Journey Started! Background tracking enabled.",
                );
                // Ensure periodic timer is also running for UI updates if needed
                _startStatusTimer();
              } else {
                service.invoke("stopService");
                UiUtils.showSnackBar(
                  context,
                  "Journey Ended. Background tracking disabled.",
                );
              }

              if (mounted) setState(() {});
            } finally {
              if (mounted) setState(() => _isProcessingJourney = false);
            }
          },
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _isProcessingJourney
                  ? [
                      const SizedBox(
                        width: 48,
                        height: 48,
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        "Connecting...",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ]
                  : [
                      Icon(
                        isJourneyActive
                            ? Icons.stop_circle
                            : Icons.play_circle_fill,
                        size: 48,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isJourneyActive
                            ? AppLocalizations.of(
                                context,
                              )!.translate('endJourney')
                            : AppLocalizations.of(
                                context,
                              )!.translate('startJourney'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18, // Slightly smaller to fit
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kZinc900,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kZinc800),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)!.translate('status'),
                    style: TextStyle(color: kZinc500, fontSize: 12),
                  ),
                  Text(
                    _boat?.name ??
                        (SessionService.isPaired
                            ? AppLocalizations.of(
                                context,
                              )!.translate('boatName')
                            : "No Device Paired"),
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'ID: ${_boat?.id ?? 'N/A'}',
                    style: TextStyle(color: kZinc500, fontSize: 12),
                  ),
                ],
              ),
              Row(
                children: [
                  if (SessionService.isPaired) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: (_boat?.batteryLevel ?? 0) < 20
                            ? const Color(0xFF450a0a) // Dark Red
                            : (_boat?.batteryLevel ?? 0) <= 50
                            ? const Color(0xFF431407) // Dark Orange
                            : const Color(0xFF14532D), // Dark Green
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: (_boat?.batteryLevel ?? 0) < 20
                              ? kRed600
                              : (_boat?.batteryLevel ?? 0) <= 50
                              ? Colors.orange
                              : const Color(0xFF166534),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.bolt,
                            color: (_boat?.batteryLevel ?? 0) < 20
                                ? kRed600
                                : (_boat?.batteryLevel ?? 0) <= 50
                                ? Colors.orange
                                : kGreen500,
                            size: 16,
                          ),
                          SizedBox(width: 4),
                          Text(
                            "${_boat?.batteryLevel ?? 0}%",
                            style: TextStyle(
                              color: (_boat?.batteryLevel ?? 0) < 20
                                  ? kRed600
                                  : (_boat?.batteryLevel ?? 0) <= 50
                                  ? Colors.orange
                                  : kGreen500,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  IconButton(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                      // Defer the update to allow pop animation to complete smoothly
                      if (mounted) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            _startStatusTimer();
                            setState(() {});
                          }
                        });
                      }
                    },
                    icon: const Icon(
                      Icons.settings,
                      color: Colors.white70,
                      size: 24,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Status Badges Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatusBadge(Icons.network_cell, "Network", _hasInternet),
              _buildStatusBadge(
                Icons.wifi,
                'Module',
                SessionService.isPaired &&
                    ((_boat?.connection ?? {})['wifi'] ?? false),
              ),
              _buildStatusBadge(
                Icons.cell_tower,
                'LoRa',
                SessionService.isPaired &&
                    ((_boat?.connection ?? {})['lora'] ?? false),
              ),
              _buildStatusBadge(
                Icons.group,
                'Mesh',
                SessionService.isPaired &&
                    (((_boat?.connection ?? {})['mesh'] ?? 0) > 0),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: kZinc800, height: 1, thickness: 1),
          const SizedBox(height: 16),
          Row(
            children: [
              // Pin Icon
              const Icon(Icons.location_on, size: 14, color: kZinc500),
              const SizedBox(width: 8),

              // Last Fix Time
              Text(
                !SessionService.isPaired && _currentPosition != null
                    ? "Last Fix: ${_formatTime(_currentPosition!.timestamp)}"
                    : "Last Fix: ${(_boat?.lastFix ?? {})['time'] ?? 'N/A'}",
                style: const TextStyle(color: kZinc500, fontSize: 12),
              ),

              // Separator dot
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text('•', style: TextStyle(color: kZinc500)),
              ),

              // Coordinates
              _boat?.gpsStatus == "SEARCHING"
                  ? const Text(
                      "GPS Searching...",
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    )
                  : !SessionService.isPaired && _currentPosition != null
                  ? Text(
                      "${_currentPosition!.latitude.toStringAsFixed(2)}, ${_currentPosition!.longitude.toStringAsFixed(2)}",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'monospace',
                      ),
                    )
                  : Text(
                      "${((_boat?.lastFix ?? {})['lat'] ?? 0.0).toStringAsFixed(2)}, ${((_boat?.lastFix ?? {})['lng'] ?? 0.0).toStringAsFixed(2)}",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'monospace',
                      ),
                    ),

              const Spacer(),

              // Last Updated
              Text(
                "Updated: ${_formatTimeAgo(_lastUpdated)}",
                style: const TextStyle(color: kZinc500, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(IconData icon, String label, bool isActive) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: isActive ? kGreen500 : kRed600, size: 20),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: isActive ? kGreen500 : kZinc500,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  String _formatTimeAgo(DateTime? time) {
    if (time == null) return 'Never';
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 5) return 'now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  String _formatTime(DateTime time) {
    final localTime = time.toLocal();
    return "${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}";
  }
}
