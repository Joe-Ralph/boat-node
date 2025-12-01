class User {
  final int id;
  final String displayName;
  final String phoneNumber;

  User({
    required this.id,
    required this.displayName,
    required this.phoneNumber,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      displayName: json['display_name'] as String,
      phoneNumber: json['phone_number'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'display_name': displayName,
      'phone_number': phoneNumber,
    };
  }
}
