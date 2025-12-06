class User {
  final String id;
  final String displayName;
  final String email;

  final String? role;
  final String? villageId;
  final String? boatId;

  User({
    required this.id,
    required this.displayName,
    required this.email,
    this.role,
    this.villageId,
    this.boatId,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'].toString(),
      displayName: json['display_name'] as String,
      email: json['email'] as String,
      role: json['role'] as String?,
      villageId: json['village_id'] as String?,
      boatId: json['boat_id'] as String?,
    );
  }

  User copyWith({
    String? id,
    String? displayName,
    String? email,
    String? role,
    String? villageId,
    String? boatId,
  }) {
    return User(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      role: role ?? this.role,
      villageId: villageId ?? this.villageId,
      boatId: boatId ?? this.boatId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'display_name': displayName,
      'email': email,
      'role': role,
      'village_id': villageId,
      'boat_id': boatId,
    };
  }
}
