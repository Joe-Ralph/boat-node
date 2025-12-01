import 'package:latlong2/latlong.dart';

class GeofenceService {
  // Approximate Maritime Boundary Line (IMBL) points for Tamil Nadu coast
  // These are illustrative and should be replaced with accurate official coordinates.
  // Starting from north of Chennai down to Kanyakumari, roughly following the IMBL.
  static final List<LatLng> borderPoints = [
    const LatLng(13.5000, 80.8000), // North of Chennai
    const LatLng(13.0000, 80.6000), // Off Chennai
    const LatLng(12.0000, 80.2000), // Off Pondicherry
    const LatLng(10.5000, 79.9000), // Palk Strait North
    const LatLng(9.5000, 79.5000), // Palk Bay
    const LatLng(9.1000, 79.2000), // Gulf of Mannar
    const LatLng(8.0000, 77.8000), // South of Kanyakumari
  ];

  static const double alertThresholdMeters = 5000.0; // 5 km

  /// Returns true if the point is within [threshold] meters of the border.
  static bool isNearBorder(
    LatLng point, {
    double threshold = alertThresholdMeters,
  }) {
    final distance = getDistanceToBorder(point);
    return distance < threshold;
  }

  /// Calculates the minimum distance in meters from [point] to the border polyline.
  static double getDistanceToBorder(LatLng point) {
    double minDistance = double.infinity;
    final Distance distanceCalculator = const Distance();

    for (int i = 0; i < borderPoints.length - 1; i++) {
      final p1 = borderPoints[i];
      final p2 = borderPoints[i + 1];

      final dist = _distanceToSegment(point, p1, p2, distanceCalculator);
      if (dist < minDistance) {
        minDistance = dist;
      }
    }
    return minDistance;
  }

  // Helper to calculate distance from point P to segment AB
  static double _distanceToSegment(
    LatLng p,
    LatLng a,
    LatLng b,
    Distance distanceCalculator,
  ) {
    // Project P onto the line defined by A and B
    // We can approximate this by checking distance to A, B, and intermediate points
    // or using a proper geometric projection.
    // For simplicity and performance with latlong2, we can check distance to the line segment.

    // Simple implementation: check distance to A and B.
    // For a more accurate "distance to line", we need vector math.
    // Let's implement a basic vector projection approximation.

    // Convert to simple x/y for projection (valid for small distances, less accurate for large)
    // But since we are dealing with lat/lon, let's stick to a simpler approach:
    // Check distance to A, B, and the midpoint. If we need high precision, we recurse.
    // Or just use the library if it has one (latlong2 doesn't have explicit point-to-segment).

    // Let's use a simplified cross-track distance approximation logic or just min distance to vertices for MVP
    // if the segments are short enough. Our segments are long (~100km), so we need projection.

    // Implementation of cross-track distance is complex on sphere.
    // Let's use a sampling approach: check 10 points along the segment.
    double minD = double.infinity;
    const int steps = 10;
    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final lat = a.latitude + (b.latitude - a.latitude) * t;
      final lng = a.longitude + (b.longitude - a.longitude) * t;
      final sample = LatLng(lat, lng);
      final d = distanceCalculator.as(LengthUnit.Meter, p, sample);
      if (d < minD) minD = d;
    }
    return minD;
  }
}
