import 'dart:async';
import 'package:boatnode/models/boat.dart';
import 'package:boatnode/screens/nearby_screen.dart';
import 'package:boatnode/screens/rescue_screen.dart';
import 'package:boatnode/screens/settings_screen.dart';
import 'package:boatnode/services/hardware_service.dart';
import 'package:boatnode/theme/app_theme.dart';
import 'package:boatnode/l10n/app_localizations.dart';
import 'package:boatnode/services/location_service.dart';
import 'package:boatnode/services/backend_service.dart';
import 'package:boatnode/services/session_service.dart';
import 'package:flutter/material.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Boat? _boat;
  bool _isInternetConnected = false;
  Timer? _timer;
  DateTime? _lastBackendUpdate;

  @override
  void initState() {
    super.initState();
    _loadData();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();

    int interval;
    if (SessionService.isPaired) {
      interval = SessionService.statusInterval;
    } else {
      interval = SessionService.gpsUpdateInterval;
    }

    print(
      "Dashboard: Starting timer with interval ${interval}s (Paired: ${SessionService.isPaired})",
    );

    _timer = Timer.periodic(Duration(seconds: interval), (timer) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    final isConnected = await HardwareService.checkInternetConnection();

    if (SessionService.isPaired) {
      // Paired Mode: Get data from Module
      final boat = await HardwareService.getBoatStatus('123');
      if (mounted) {
        setState(() {
          _boat = boat;
          _isInternetConnected = isConnected;
        });
      }
    } else {
      // Unpaired Mode: Use Phone GPS
      final position = await LocationService.getCurrentLocation();
      if (position != null) {
        // Send to backend
        await BackendService.updateLocation(
          lat: position.latitude,
          lon: position.longitude,
          battery: 100, // Phone battery (mocked for now)
        );

        if (mounted) {
          setState(() {
            _lastBackendUpdate = DateTime.now();
            _boat = Boat(
              id: "PHONE-GPS",
              name: "Phone GPS Active",
              batteryLevel: -1, // -1 indicates N/A for unpaired mode
              connection: {'wifi': false, 'lora': false, 'mesh': 0},
              lastFix: {
                'lat': position.latitude,
                'lng': position.longitude,
                'source': 'Phone GPS',
                'timestamp': DateTime.now().toIso8601String(),
              },
            );
            _isInternetConnected = isConnected;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_boat == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              _buildStatusCard(),
              const SizedBox(height: 32),
              Expanded(
                child: Column(
                  children: [
                    // First row - Full width rescue button
                    Expanded(
                      flex: 2, // Takes more space
                      child: _buildActionButton(
                        AppLocalizations.of(context)!.translate('rescueMode'),
                        Icons.support,
                        kRed600,
                        () async {
                          final confirmed =
                              await showDialog<bool>(
                                context: context,
                                barrierDismissible: false,
                                builder: (BuildContext context) {
                                  final localizations = AppLocalizations.of(
                                    context,
                                  )!;
                                  return AlertDialog(
                                    backgroundColor: kZinc900,
                                    title: Text(
                                      localizations.translate(
                                        'sosConfirmationTitle',
                                      ),
                                      style: const TextStyle(
                                        color: kRed500,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    content: Text(
                                      localizations.translate(
                                        'sosConfirmationMessage',
                                      ),
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(false),
                                        child: Text(
                                          localizations
                                              .translate('cancel')
                                              .toUpperCase(),
                                          style: const TextStyle(
                                            color: kZinc400,
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(true),
                                        child: Text(
                                          localizations
                                              .translate('confirm')
                                              .toUpperCase(),
                                          style: const TextStyle(
                                            color: kRed500,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ) ??
                              false;

                          if (confirmed == true && context.mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const RescueScreen(),
                              ),
                            );
                          }
                        },
                        isRescue: true,
                        isFullWidth: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Second row - Two buttons side by side
                    Expanded(
                      flex: 2, // Same height as first row
                      child: Row(
                        children: [
                          // Nearby Boats button
                          Expanded(
                            child: _buildActionButton(
                              AppLocalizations.of(
                                context,
                              )!.translate('nearbyBoats'),
                              Icons.radar,
                              kZinc800,
                              () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const NearbyScreen(),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Settings button
                          Expanded(
                            child: _buildActionButton(
                              AppLocalizations.of(
                                context,
                              )!.translate('settings'),
                              Icons.settings,
                              kZinc800,
                              () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const SettingsScreen(),
                                  ),
                                );
                                // Refresh data and restart timer when returning from settings
                                // as intervals might have changed
                                _loadData();
                                _startTimer();
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Third row - Half height sync button
                    Expanded(
                      flex: 1, // Half the height of other rows
                      child: _buildActionButton(
                        AppLocalizations.of(context)!.translate('syncStatus'),
                        Icons.refresh,
                        kZinc800,
                        _loadData,
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

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kZinc900,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kZinc800),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)!.translate('status'),
                    style: const TextStyle(color: kZinc500, fontSize: 12),
                  ),
                  Text(
                    _boat!.name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    "${AppLocalizations.of(context)!.translate('id')}: ${_boat!.id}",
                    style: const TextStyle(
                      color: kZinc500,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: SessionService.isPaired
                          ? kZinc800
                          : kBlue600.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: SessionService.isPaired
                            ? kZinc700
                            : kBlue600.withOpacity(0.5),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      SessionService.isPaired
                          ? "SOURCE: MODULE"
                          : "SOURCE: PHONE GPS",
                      style: TextStyle(
                        fontSize: 10,
                        color: SessionService.isPaired ? kZinc400 : kBlue600,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF14532D),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF166534)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.bolt, color: kGreen500, size: 16),
                    Text(
                      "${_boat!.batteryLevel}%",
                      style: const TextStyle(
                        color: kGreen500,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_boat!.batteryLevel == -1 && _lastBackendUpdate != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.access_time, color: kZinc500, size: 12),
                const SizedBox(width: 4),
                Text(
                  "Last Updated: ${_formatTime(_lastBackendUpdate!)}",
                  style: const TextStyle(color: kZinc500, fontSize: 12),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildBadge(Icons.network_cell, "Network", _isInternetConnected),
              _buildBadge(
                Icons.wifi_tethering,
                "Module",
                _boat!.name != "Connection Failed",
              ),
              _buildBadge(
                Icons.cell_tower,
                AppLocalizations.of(context)!.translate('lora'),
                _boat!.connection['lora'] == true,
              ),
              _buildBadge(
                Icons.group,
                "${AppLocalizations.of(context)!.translate('mesh')} (${_boat!.connection['mesh'] ?? 0})",
                (_boat!.connection['mesh'] ?? 0) > 0,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(IconData icon, String label, bool active) {
    return Column(
      children: [
        Icon(icon, color: active ? kGreen500 : kZinc500),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: active ? kGreen500 : kZinc500,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(
    String label,
    IconData icon,
    Color bg,
    VoidCallback onTap, {
    bool isRescue = false,
    bool isFullWidth = false,
  }) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Icon(
                    icon,
                    size: isRescue ? 32 : 28,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: isRescue ? 16 : 14,
                      fontWeight: isRescue ? FontWeight.w800 : FontWeight.bold,
                      color: Colors.white,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
              if (isRescue) ...[
                const SizedBox(height: 2),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      AppLocalizations.of(
                        context,
                      )!.translate('broadcastSignal'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withOpacity(0.8),
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}";
  }
}
