enum UserRole {
  ADMIN,
  FINANCE,
  COLLECTOR,
  OPERATOR,
  RETAILER,
}

extension UserRoleExtension on UserRole {
  String get name {
    switch (this) {
      case UserRole.ADMIN:
        return 'Admin';
      case UserRole.FINANCE:
        return 'Finance';
      case UserRole.COLLECTOR:
        return 'Collector';
      case UserRole.OPERATOR:
        return 'Operator';
      case UserRole.RETAILER:
        return 'Retailer';
    }
  }

  static UserRole fromString(String role) {
    switch (role.toUpperCase()) {
      case 'ADMIN':
        return UserRole.ADMIN;
      case 'FINANCE':
        return UserRole.FINANCE;
      case 'COLLECTOR':
        return UserRole.COLLECTOR;
      case 'OPERATOR':
        return UserRole.OPERATOR;
      case 'RETAILER':
        return UserRole.RETAILER;
      default:
        return UserRole.OPERATOR;
    }
  }
}

class AppUser {
  final String uid;
  final String email;
  final String name;
  final UserRole role;
  final bool isActive;
  final DateTime createdAt;

  /// Firebase `retailers/{retailerId}` key when [role] is [UserRole.RETAILER].
  final String? retailerId;

  AppUser({
    required this.uid,
    required this.email,
    required this.name,
    required this.role,
    this.isActive = true,
    required this.createdAt,
    this.retailerId,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'name': name,
      'role': role.toString().split('.').last,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      if (retailerId != null && retailerId!.isNotEmpty) 'retailerId': retailerId,
    };
  }

  factory AppUser.fromMap(Map<String, dynamic> map, String uid) {
    return AppUser(
      uid: uid,
      email: map['email']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      role: UserRoleExtension.fromString(map['role']?.toString() ?? 'OPERATOR'),
      isActive: (map['isActive'] is bool) ? map['isActive'] : true,
      createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '') ?? DateTime.now(),
      retailerId: map['retailerId']?.toString(),
    );
  }

  bool get isAdmin => role == UserRole.ADMIN;
  bool get isFinance => role == UserRole.FINANCE || role == UserRole.ADMIN;
  bool get isCollector => role == UserRole.COLLECTOR;
  bool get isRetailer => role == UserRole.RETAILER;
}
