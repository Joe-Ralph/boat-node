import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:boatnode/services/hardware_service.dart';
import 'package:boatnode/services/session_service.dart';
import 'package:boatnode/models/nearby_boat.dart';
import 'package:boatnode/theme/app_theme.dart';
import 'package:boatnode/services/geofence_service.dart';
import 'package:boatnode/services/map_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:boatnode/services/backend_service.dart';
import 'package:boatnode/services/log_service.dart';

class CachedTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);
    return CachedNetworkImageProvider(url);
  }
}

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  List<NearbyBoat> _boats = [];
  bool _loading = true;
  Position? _currentPosition;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() => _loading = true);

    // Determine source of "current location"
    Position? position;
    if (SessionService.isPaired) {
      // If paired, use the boat's location
      final boatStatus = await HardwareService.getBoatStatus(
        '123',
      ); // ID should ideally be dynamic
      final lastFix = boatStatus.lastFix;
      if (lastFix['lat'] != null && lastFix['lng'] != null) {
        position = Position(
          longitude: lastFix['lng'],
          latitude: lastFix['lat'],
          timestamp: DateTime.now(),
          accuracy: 0,
          altitude: 0,
          heading: 0, // Boat heading could be added to Boat model if available
          speed: 0,
          speedAccuracy: 0,
          altitudeAccuracy: 0,
          headingAccuracy: 0,
        );
      }
    }

    // Fallback or if unpaired: use phone location
    position ??= await HardwareService.getCurrentLocation();

    // Fetch boats based on mode
    List<NearbyBoat> boats = [];
    if (SessionService.isPaired) {
      // Mesh Scan (Paired)
      boats = await HardwareService.scanMesh();
    } else if (position != null) {
      // Backend Query (Unpaired) - Find boats near me
      try {
        final backendBoats = await BackendService.getNearbyBoats(
          lat: position.latitude,
          lon: position.longitude,
        );
        // Convert Map to NearbyBoat model
        boats = backendBoats.map((data) {
          return NearbyBoat(
            id: (data['boat_id'] as String?) ?? 'unknown',
            name: (data['boat_name'] as String?) ?? 'Unknown Boat',
            lat: (data['lat'] as num).toDouble(),
            lon: (data['lon'] as num).toDouble(),
            distance: (data['distance_meters'] as num).toInt(),
            lastSeen: _calculateMinutesAgo(data['last_updated']),
            battery: data['battery_level'] ?? 0,
            userId:
                0, // Backend uses UUIDs, legacy model uses int. Defaulting to 0.
            bearing:
                "N", // Placeholder, calculation logic is internal to model or not needed for basic list
          );
        }).toList();
      } catch (e) {
        LogService.e("NearbyScreen: Error fetching nearby boats", e);
        // Fallback or empty list
      }
    }

    if (mounted) {
      setState(() {
        _currentPosition = position;
        _boats = boats;
        _loading = false;
      });

      // Fit bounds to include user and all boats
      if (position != null) {
        final points = [LatLng(position.latitude, position.longitude)];
        for (var boat in boats) {
          points.add(LatLng(boat.lat, boat.lon));
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (points.length > 1) {
            final bounds = LatLngBounds.fromPoints(points);
            _mapController.fitCamera(
              CameraFit.bounds(
                bounds: bounds,
                padding: const EdgeInsets.all(80), // Padding for UI elements
              ),
            );
          } else {
            _mapController.move(points.first, 15.0);
          }
        });
      }
    }
  }

  int _calculateMinutesAgo(String? isoString) {
    if (isoString == null) return 0;
    try {
      final time = DateTime.parse(isoString);
      return DateTime.now().difference(time).inMinutes;
    } catch (_) {
      return 0;
    }
  }

  String _getBoatLetter(int index) {
    // Generate A, B, C... Z, AA, AB...
    const letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    if (index < letters.length) {
      return letters[index];
    }
    return letters[index % letters.length]; // Fallback loop for now
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("Nearby Boats"),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF14532D),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              "MESH ACTIVE",
              style: TextStyle(
                fontSize: 10,
                color: kGreen500,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Map Section
          SizedBox(
            height: 300, // Fixed height for map
            width: double.infinity,
            child: _currentPosition == null && _loading
                ? const Center(child: CircularProgressIndicator())
                : Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _currentPosition != null
                              ? LatLng(
                                  _currentPosition!.latitude,
                                  _currentPosition!.longitude,
                                )
                              : const LatLng(
                                  13.0827,
                                  80.2707,
                                ), // Default to Chennai
                          initialZoom: 15.0,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.boatnode.app',
                            tileProvider: CachedTileProvider(),
                          ),
                          TileLayer(
                            urlTemplate:
                                'https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.boatnode.app',
                            tileProvider: CachedTileProvider(),
                          ),
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: GeofenceService.borderPoints,
                                strokeWidth: 3.0,
                                color: kRed600.withOpacity(0.7),
                                pattern: StrokePattern.dashed(
                                  segments: [10, 10],
                                ),
                              ),
                            ],
                          ),
                          MarkerLayer(
                            markers: [
                              // Self Marker (Blue Arrow)
                              if (_currentPosition != null)
                                Marker(
                                  point: LatLng(
                                    _currentPosition!.latitude,
                                    _currentPosition!.longitude,
                                  ),
                                  width: 40,
                                  height: 40,
                                  child: Transform.rotate(
                                    angle:
                                        (_currentPosition!.heading *
                                        3.14159 /
                                        180),
                                    child: const Icon(
                                      Icons.navigation,
                                      color: kBlue600,
                                      size: 32,
                                    ),
                                  ),
                                ),

                              // Other Boats Markers
                              ..._boats.asMap().entries.map((entry) {
                                final index = entry.key;
                                final boat = entry.value;
                                return Marker(
                                  point: LatLng(boat.lat, boat.lon),
                                  width: 40,
                                  height: 40,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: kRed600,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      _getBoatLetter(index),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ],
                      ),
                      // Zoom Buttons
                      Positioned(
                        bottom: 16,
                        right: 16,
                        child: Column(
                          children: [
                            FloatingActionButton.small(
                              heroTag: "zoom_in",
                              onPressed: () {
                                final currentZoom = _mapController.camera.zoom;
                                _mapController.move(
                                  _mapController.camera.center,
                                  currentZoom + 1,
                                );
                              },
                              backgroundColor: kZinc800,
                              child: const Icon(Icons.add, color: Colors.white),
                            ),
                            const SizedBox(height: 8),
                            FloatingActionButton.small(
                              heroTag: "zoom_out",
                              onPressed: () {
                                final currentZoom = _mapController.camera.zoom;
                                _mapController.move(
                                  _mapController.camera.center,
                                  currentZoom - 1,
                                );
                              },
                              backgroundColor: kZinc800,
                              child: const Icon(
                                Icons.remove,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            FloatingActionButton.small(
                              heroTag: "center_map",
                              onPressed: () {
                                if (_currentPosition != null) {
                                  _mapController.move(
                                    LatLng(
                                      _currentPosition!.latitude,
                                      _currentPosition!.longitude,
                                    ),
                                    _mapController.camera.zoom,
                                  );
                                }
                              },
                              backgroundColor: kZinc800,
                              child: const Icon(
                                Icons.my_location,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Caching Progress Bar
                      ValueListenableBuilder<double>(
                        valueListenable: MapService.cachingProgress,
                        builder: (context, progress, child) {
                          if (progress <= 0.0 || progress >= 1.0) {
                            return const SizedBox.shrink();
                          }
                          return Positioned(
                            top: 16,
                            left: 16,
                            right: 16,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: kZinc900.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: kZinc800),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        "Caching Offline Maps...",
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        "${(progress * 100).toInt()}%",
                                        style: const TextStyle(
                                          color: kGreen500,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  LinearProgressIndicator(
                                    value: progress,
                                    backgroundColor: kZinc800,
                                    color: kGreen500,
                                    minHeight: 4,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
          ),

          // List Section
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _boats.length,
                    itemBuilder: (context, index) {
                      final boat = _boats[index];
                      return GestureDetector(
                        onTap: () {
                          _mapController.move(LatLng(boat.lat, boat.lon), 15.0);
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: kZinc900,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: kZinc800),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: kRed600,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: kZinc800),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  _getBoatLetter(index),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      boat.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    Text(
                                      "ID: ${boat.id} • ${boat.lastSeen}m ago",
                                      style: const TextStyle(
                                        color: kZinc500,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    "${boat.distance}m",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                  const Text(
                                    "Strong Signal",
                                    style: TextStyle(
                                      color: kGreen500,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Sync Button
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _scan,
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: const Text(
                  "SYNC STATUS",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kZinc800,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
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
