class Boat {
  final String id;
  final String name;
  final int batteryLevel;
  final Map<String, dynamic> connection;
  final Map<String, dynamic> lastFix;

  final String?
  ownerId; // Nullable if not always fetched or for backward compatibility
  final String gpsStatus;

  Boat({
    required this.id,
    required this.name,
    required this.batteryLevel,
    required this.connection,
    required this.lastFix,
    this.ownerId,
    this.gpsStatus = "UNKNOWN",
  });
}
