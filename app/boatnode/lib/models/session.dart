class Session {
  final String token;
  final String userId;
  final String displayName;
  final DateTime expiresAt;

  Session({
    required this.token,
    required this.userId,
    required this.displayName,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Map<String, dynamic> toJson() => {
    'token': token,
    'userId': userId,
    'display_name': displayName,
    'expiresAt': expiresAt.toIso8601String(),
  };

  factory Session.fromJson(Map<String, dynamic> json) => Session(
    token: json['token'],
    userId: json['userId'],
    displayName: json['display_name'] ?? 'User',
    expiresAt: DateTime.parse(json['expiresAt']),
  );
}
