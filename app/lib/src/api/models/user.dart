class User {
  const User({
    required this.id,
    required this.phone,
    required this.role,
    this.name,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as int,
        phone: json['phone'] as String,
        name: json['name'] as String?,
        role: json['role'] as String? ?? 'client',
      );

  final int id;
  final String phone;
  final String? name;
  final String role;

  Map<String, dynamic> toJson() => {
        'id': id,
        'phone': phone,
        'name': name,
        'role': role,
      };

  String get displayName =>
      (name != null && name!.isNotEmpty) ? name! : phone;
}
