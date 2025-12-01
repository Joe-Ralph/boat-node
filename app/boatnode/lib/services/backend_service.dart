// import 'dart:convert';
// import 'package:http/http.dart' as http;

class BackendService {
  // Mock Backend URL
  // static const String _baseUrl = "https://api.boatnode.com/v1";

  static Future<void> updateLocation({
    required double lat,
    required double lon,
    required int battery,
    String? boatId,
  }) async {
    // In a real app, we would send this to the backend.
    // For now, we just log it.

    final body = {
      "lat": lat,
      "lon": lon,
      "battery": battery,
      "timestamp": DateTime.now().toIso8601String(),
      if (boatId != null) "boat_id": boatId,
    };

    print("BackendService: Sending location update -> $body");

    // Simulate network call
    // await http.post(Uri.parse('$_baseUrl/location'), body: json.encode(body));
  }
}
