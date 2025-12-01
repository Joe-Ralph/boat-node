class NearbyBoat {
  final String id;
  final String name;
  final int distance; // Calculated on phone
  final String bearing; // Calculated on phone
  final int lastSeen; // age_sec
  final double lat;
  final double lon;
  final int userId;
  final int battery;

  NearbyBoat({
    required this.id,
    required this.name,
    required this.distance,
    required this.bearing,
    required this.lastSeen,
    required this.lat,
    required this.lon,
    required this.userId,
    required this.battery,
  });

  factory NearbyBoat.fromJson(Map<String, dynamic> json, double myLat, double myLon) {
    final lat = (json['lat'] as num).toDouble();
    final lon = (json['lon'] as num).toDouble();
    
    // Calculate distance and bearing here (mock implementation)
    // In real app, use geolocator or vector_math
    final dist = _calculateDistance(myLat, myLon, lat, lon);
    final bear = _calculateBearing(myLat, myLon, lat, lon);

    return NearbyBoat(
      id: json['boat_id'] as String,
      name: json['display_name'] as String? ?? "Unknown",
      distance: dist,
      bearing: bear,
      lastSeen: json['age_sec'] as int,
      lat: lat,
      lon: lon,
      userId: json['user_id'] as int? ?? 0,
      battery: json['battery'] as int? ?? 0,
    );
  }

  static int _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    // Placeholder for Haversine formula
    // Returning dummy distance based on simple diff
    return ((lat1 - lat2).abs() * 111000).toInt(); 
  }

  static String _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    // Placeholder
    return "N";
  }
}
