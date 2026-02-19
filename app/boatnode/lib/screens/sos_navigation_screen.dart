import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:boatnode/theme/app_theme.dart';
import 'package:boatnode/services/backend_service.dart';
import 'package:boatnode/services/log_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

class SosNavigationScreen extends StatefulWidget {
  final Map<dynamic, dynamic> targetSignal;

  const SosNavigationScreen({super.key, required this.targetSignal});

  @override
  State<SosNavigationScreen> createState() => _SosNavigationScreenState();
}

class _SosNavigationScreenState extends State<SosNavigationScreen> {
  // Target
  late double _targetLat;
  late double _targetLong;

  // Current State
  Position? _currentPosition;
  double? _heading; // Device heading (0-360)
  double _distanceToTarget = 0;
  double _bearingToTarget = 0; // Bearing from North to target

  // Stream Subscriptions
  // Stream Subscriptions
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<CompassEvent>? _compassStream;
  RealtimeChannel? _sosChannel;

  // Throttling
  int _lastCompassUpdate = 0;
  static const int _compassThrottleMs = 32; // ~30 FPS

  // Metadata
  Map<String, dynamic>? _profile;
  int _broadcastCount = 0;
  bool _loading = true;
  bool _isResolved = false;

  // Timer for polling fallback
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    // Defer heavy initialization to ensure context is ready and transition is complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _safeInit();
    });

    _parseTarget();
    _fetchMetadata();
  }

  Future<void> _safeInit() async {
    // Wait for transition animation to complete
    await Future.delayed(const Duration(milliseconds: 500));

    try {
      if (!mounted) return;
      // Keep screen on
      await WakelockPlus.enable();
      LogService.i("SosNavigationScreen: Wakelock enabled");
    } catch (e) {
      LogService.e("SosNavigationScreen: Error enabling wakelock", e);
    }

    if (!mounted) return;
    _startSensors();

    if (!mounted) return;
    _setupRealtimeAndPolling();
  }

  void _setupRealtimeAndPolling() {
    final signalId = widget.targetSignal['id'];
    LogService.i(
      "SosNavigationScreen: Monitoring Signal ID: $signalId (Type: ${signalId.runtimeType})",
    );

    if (signalId == null) {
      LogService.e(
        "SosNavigationScreen: Signal ID is null. Cannot monitor status.",
      );
      return;
    }

    // 1. Realtime Subscription
    try {
      _sosChannel = Supabase.instance.client
          .channel('public:sos_signals:id=eq.$signalId')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'sos_signals',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: signalId,
            ),
            callback: (payload, [ref]) {
              final newStatus = payload.newRecord['status'];
              LogService.i(
                "SosNavigationScreen: Realtime update received. Status: $newStatus",
              );
              if (newStatus == 'resolved' || newStatus == 'cancelled') {
                _handleSosResolved();
              }
            },
          )
          .subscribe((status, error) {
            LogService.i(
              "SosNavigationScreen: Realtime Subscription Status: $status $error",
            );
          });
    } catch (e) {
      LogService.e("SosNavigationScreen: Error setting up realtime", e);
    }

    // 2. Polling Fallback (Every 5 seconds)
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!mounted || _isResolved) {
        timer.cancel();
        return;
      }
      try {
        final response = await Supabase.instance.client
            .from('sos_signals')
            .select('status')
            .eq('id', signalId)
            .maybeSingle();

        if (response != null) {
          final status = response['status'];
          if (status == 'resolved' || status == 'cancelled') {
            LogService.i("SosNavigationScreen: Polling detected SOS end.");
            _handleSosResolved();
          }
        }
      } catch (e) {
        LogService.e("SosNavigationScreen: Polling error", e);
      }
    });
  }

  void _handleSosResolved() {
    if (!mounted || _isResolved) return;
    setState(() => _isResolved = true);

    // Cancel timer immediately
    _pollingTimer?.cancel();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("SOS Ended"),
        content: const Text("The SOS signal has been resolved or cancelled."),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(); // Exit screen
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  void _parseTarget() {
    final extra = widget.targetSignal['extra'];
    if (extra != null && extra['lat'] != null && extra['long'] != null) {
      _targetLat = (extra['lat'] as num).toDouble();
      _targetLong = (extra['long'] as num).toDouble();
    } else {
      _targetLat = 0;
      _targetLong = 0;
      LogService.e("SosNavigationScreen: Invalid target coordinates");
    }
  }

  Future<void> _fetchMetadata() async {
    final senderId = widget.targetSignal['sender_id'];
    if (senderId != null) {
      final profile = await BackendService.getPublicProfile(senderId);
      final count = await BackendService.getSosBroadcastCount(senderId);
      if (mounted) {
        setState(() {
          _profile = profile;
          _broadcastCount = count;
          _loading = false;
        });
      }
    } else {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startSensors() {
    // 1. Position Stream
    try {
      _positionStream =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 5, // Relaxed from 2m to 5m to reduce GPS strain
            ),
          ).listen(
            (position) {
              LogService.d(
                "SosNavigationScreen: Position update received: ${position.latitude}, ${position.longitude}",
              );
              try {
                if (mounted) {
                  setState(() {
                    _currentPosition = position;
                    _updateNavigationCalculations();
                  });
                }
              } catch (e) {
                LogService.e(
                  "SosNavigationScreen: Error processing position update",
                  e,
                );
              }
            },
            onError: (e) {
              LogService.e("SosNavigationScreen: Geolocator stream error", e);
            },
          );
    } catch (e) {
      LogService.e("SosNavigationScreen: Error starting Geolocator", e);
    }

    // 2. Compass Stream
    try {
      _compassStream = FlutterCompass.events?.listen(
        (event) {
          try {
            // Log every 50 updates to avoid spam but confirm activity
            if (_lastCompassUpdate % 50 == 0) {
              // LogService.v("SosNavigationScreen: Compass event received: ${event.heading}");
            }

            final now = DateTime.now().millisecondsSinceEpoch;
            if (now - _lastCompassUpdate > _compassThrottleMs) {
              _lastCompassUpdate = now;
              if (mounted) {
                setState(() {
                  _heading = event.heading;
                });
              }
            }
          } catch (e) {
            LogService.e(
              "SosNavigationScreen: Error processing compass update",
              e,
            );
          }
        },
        onError: (e) {
          LogService.e("SosNavigationScreen: Compass stream error", e);
        },
      );
    } catch (e) {
      LogService.e("SosNavigationScreen: Error starting Compass", e);
    }

    // Initial fetch to show something immediately
    try {
      Geolocator.getCurrentPosition()
          .then((pos) {
            if (mounted) {
              setState(() {
                _currentPosition = pos;
                _updateNavigationCalculations();
              });
            }
          })
          .catchError((e) {
            LogService.e(
              "SosNavigationScreen: Error getting initial position",
              e,
            );
          });
    } catch (e) {
      LogService.e("SosNavigationScreen: Error requesting initial position", e);
    }
  }

  void _updateNavigationCalculations() {
    if (_currentPosition == null) return;

    // Calculate Distance
    _distanceToTarget = Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      _targetLat,
      _targetLong,
    );

    // Calculate Bearing (True North)
    _bearingToTarget = Geolocator.bearingBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      _targetLat,
      _targetLong,
    );
  }

  @override
  void deactivate() {
    LogService.i("SosNavigationScreen: deactivate()");
    super.deactivate();
  }

  @override
  void dispose() {
    LogService.i("SosNavigationScreen: dispose()");
    try {
      WakelockPlus.disable();
    } catch (e) {
      LogService.e("SosNavigationScreen: Error disabling wakelock", e);
    }
    _pollingTimer?.cancel();
    _positionStream?.cancel();
    _compassStream?.cancel();
    try {
      _sosChannel?.unsubscribe();
    } catch (e) {
      LogService.e("SosNavigationScreen: Error unsubscribing realtime", e);
    }
    // Ensure call is ended on exit
    try {
      FlutterCallkitIncoming.endAllCalls();
    } catch (e) {
      LogService.e("SosNavigationScreen: Error ending calls on dispose", e);
    }
    super.dispose();
  }

  // Helper to get rotation angle for arrow
  double _getArrowRotation() {
    // Heading is direction device is facing (0=N, 90=E)
    // Bearing is direction to target from North
    // We want arrow to point to target relative to device
    // Angle = Bearing - Heading

    // Example: Target is East (90), Device facing North (0) -> Arrow points right (90)
    // Example: Target is East (90), Device facing East (90) -> Arrow points up (0)

    double heading = _heading ?? 0;
    double bearing = _bearingToTarget;

    // Normalize to 0-360
    double diff = (bearing - heading);
    // Geolocator bearing is -180 to 180, normalize it first? No, math works usually.
    // Let's ensure everything is in radians for Transform.rotate
    return diff * (math.pi / 180);
  }

  Color _getStatusColor() {
    if (_distanceToTarget < 20) return kGreen500;
    if (_distanceToTarget < 100) return Colors.orangeAccent;
    return kRed600;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _currentPosition == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: kRed600)),
      );
    }

    final color = _getStatusColor();
    final isClose = _distanceToTarget < 10;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "SOS SIGNAL",
          style: TextStyle(color: kRed600, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          // 1. Info Header
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                Text(
                  _profile?['display_name'] ?? "Unknown User",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "$_broadcastCount others notified",
                  style: const TextStyle(color: kZinc500),
                ),
              ],
            ),
          ),

          // 2. Compass / Arrow Area
          Expanded(
            child: Center(
              child: isClose
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(30),
                          decoration: BoxDecoration(
                            color: kGreen500.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_circle,
                            color: kGreen500,
                            size: 100,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          "YOU ARE HERE",
                          style: TextStyle(
                            color: kGreen500,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                      ],
                    )
                  : Stack(
                      alignment: Alignment.center,
                      children: [
                        // Outer ring
                        Container(
                          width: 300,
                          height: 300,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: color.withOpacity(0.3),
                              width: 2,
                            ),
                          ),
                        ),
                        // Rotating Arrow
                        Transform.rotate(
                          angle: _getArrowRotation(),
                          child: Icon(
                            Icons.navigation,
                            size: 200,
                            color: color,
                          ),
                        ),
                      ],
                    ),
            ),
          ),

          // 3. Distance Metrics
          Padding(
            padding: const EdgeInsets.only(bottom: 20.0),
            child: Column(
              children: [
                Text(
                  "${_distanceToTarget.toStringAsFixed(0)}m",
                  style: TextStyle(
                    color: color,
                    fontSize: 72,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  isClose ? "ARRIVED" : "DISTANCE",
                  style: TextStyle(
                    color: color.withOpacity(0.8),
                    fontSize: 16,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),

          // 4. Stop Rescue Button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 16.0,
              ),
              child: SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () async {
                    try {
                      await FlutterCallkitIncoming.endAllCalls();
                    } catch (e) {
                      LogService.e(
                        "SosNavigationScreen: Error ending calls",
                        e,
                      );
                    }
                    if (context.mounted) Navigator.pop(context);
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: kZinc800,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    "STOP RESCUE",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
