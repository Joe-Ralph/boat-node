class User {
  final int id;
  final String displayName;
  final String phoneNumber;

  final String? role;
  final String? villageId;
  final String? boatId;

  User({
    required this.id,
    required this.displayName,
    required this.phoneNumber,
    this.role,
    this.villageId,
    this.boatId,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      displayName: json['display_name'] as String,
      phoneNumber: json['phone_number'] as String,
      role: json['role'] as String?,
      villageId: json['village_id'] as String?,
      boatId: json['boat_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'display_name': displayName,
      'phone_number': phoneNumber,
      'role': role,
      'village_id': villageId,
      'boat_id': boatId,
    };
  }
}
