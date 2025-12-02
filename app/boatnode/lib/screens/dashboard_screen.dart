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
import 'package:boatnode/services/map_service.dart';
import 'package:boatnode/services/geofence_service.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/material.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'package:boatnode/services/auth_service.dart';
import 'package:boatnode/models/user.dart';
import 'package:boatnode/screens/qr_scan_screen.dart';
import 'package:boatnode/screens/qr_code_screen.dart';
import 'package:geolocator/geolocator.dart';

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

  User? _user;

  @override
  void initState() {
    super.initState();
    NotificationService().init();
    _checkInternet();
    _loadData();
    _startStatusTimer();
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadData();
    _checkInternet();
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
      });
    }

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

    final boat = await HardwareService.getBoatStatus('123');
    if (!mounted) return;
    setState(() {
      _boat = boat;
      _lastUpdated = DateTime.now();
    });

    if (boat != null && SessionService.isPaired) {
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
    if (SessionService.isPaired && boat != null) {
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context)!.translate('connectingToDevice'),
        ),
        duration: const Duration(seconds: 2),
      ),
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
      if (_boat != null && _boat!.name != "Connection Failed") {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Connected successfully!"),
            backgroundColor: kGreen500,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Connection failed. Please ensure device is on."),
            backgroundColor: kRed600,
          ),
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
                    Expanded(flex: 2, child: _buildRescueButton()),
                    const SizedBox(height: 12),
                    Expanded(
                      flex: 2,
                      child: Row(
                        children: [
                          Expanded(child: _buildActionGrid()),
                          const SizedBox(width: 12),
                          Expanded(child: _buildSettingsButton()),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      flex: 1,
                      child: Row(
                        children: [
                          Expanded(child: _buildSyncButton()),
                          if (_user?.role == 'owner' &&
                              SessionService.isPaired) ...[
                            const SizedBox(width: 12),
                            Expanded(child: _buildShowQRButton()),
                          ],
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
                    fontSize: 16,
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
            _handlePairingSuccess();
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
        color: isPaired ? (isConnected ? kZinc800 : kBlue600) : kGreen500,
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
                  Icon(icon, size: 28, color: Colors.white),
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
    print("Dashboard: Pairing success handled.");
    try {
      _loadData();
      _startStatusTimer();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Pairing successful. Caching offline maps..."),
            duration: Duration(seconds: 2),
          ),
        );
        HardwareService.getCurrentLocation().then((pos) {
          if (pos != null && mounted) {
            print(
              "Dashboard: Caching map area for ${pos.latitude}, ${pos.longitude}",
            );
            MapService.cacheArea(
              context,
              pos.latitude,
              pos.longitude,
            ).catchError((e) {
              print("Dashboard: Map caching error: $e");
            });
          }
        });
      }
    } catch (e) {
      print("Dashboard: Error in _handlePairingSuccess: $e");
    }
  }

  Widget _buildSettingsButton() {
    return Container(
      decoration: BoxDecoration(
        color: kZinc800,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            );
            // Restart timer in case interval changed
            _startStatusTimer();
            if (mounted) setState(() {});
          },
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.settings, size: 28, color: Colors.white),
                SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context)!.translate('settings'),
                  style: TextStyle(
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

  Widget _buildShowQRButton() {
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
          onTap: () {
            if (_boat != null) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => QRCodeScreen(boat: _boat!)),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Boat data not available yet"),
                  backgroundColor: kRed600,
                ),
              );
            }
          },
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.qr_code, size: 24, color: Colors.white),
                const SizedBox(height: 6),
                Text(
                  "SHOW QR",
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
              if (SessionService.isPaired)
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
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatusBadge(
                Icons.network_cell,
                "Network",
                _hasInternet,
              ), // Network is usually cellular on phone, maybe keep false or check internet? Keeping false as per current mock.
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
          const Divider(
            color: kZinc800,
            height: 1, // Occupies 1px vertical space roughly
            thickness: 1,
          ),
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
              // Coordinates or Status
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
    return "${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}:${localTime.second.toString().padLeft(2, '0')}";
  }
}
