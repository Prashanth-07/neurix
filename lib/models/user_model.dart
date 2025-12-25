class UserModel {
  final String uid;
  final String email;
  final String? displayName;
  final String? photoUrl;
  final DateTime createdAt;
  final DateTime? lastLoginAt;
  final Map<String, dynamic>? preferences;
  final bool isEmailVerified;

  UserModel({
    required this.uid,
    required this.email,
    this.displayName,
    this.photoUrl,
    required this.createdAt,
    this.lastLoginAt,
    this.preferences,
    this.isEmailVerified = false,
  });

  factory UserModel.fromFirebase(dynamic user) {
    return UserModel(
      uid: user.uid,
      email: user.email ?? '',
      displayName: user.displayName,
      photoUrl: user.photoURL,
      createdAt: DateTime.now(),
      lastLoginAt: DateTime.now(),
      isEmailVerified: user.emailVerified ?? false,
      preferences: {},
    );
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] ?? '',
      email: map['email'] ?? '',
      displayName: map['display_name'],
      photoUrl: map['photo_url'],
      createdAt: DateTime.parse(map['created_at'] ?? DateTime.now().toIso8601String()),
      lastLoginAt: map['last_login_at'] != null 
          ? DateTime.parse(map['last_login_at']) 
          : null,
      isEmailVerified: map['is_email_verified'] == 1,
      preferences: map['preferences'] ?? {},
    );
  }

  factory UserModel.fromFirestore(Map<String, dynamic> doc) {
    return UserModel(
      uid: doc['uid'] ?? '',
      email: doc['email'] ?? '',
      displayName: doc['displayName'],
      photoUrl: doc['photoUrl'],
      createdAt: doc['createdAt'] != null 
          ? (doc['createdAt'] as dynamic).toDate() 
          : DateTime.now(),
      lastLoginAt: doc['lastLoginAt'] != null 
          ? (doc['lastLoginAt'] as dynamic).toDate() 
          : null,
      isEmailVerified: doc['isEmailVerified'] ?? false,
      preferences: doc['preferences'] ?? {},
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'display_name': displayName,
      'photo_url': photoUrl,
      'created_at': createdAt.toIso8601String(),
      'last_login_at': lastLoginAt?.toIso8601String(),
      'is_email_verified': isEmailVerified ? 1 : 0,
      'preferences': preferences?.toString(),
    };
  }

  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'createdAt': createdAt,
      'lastLoginAt': lastLoginAt,
      'isEmailVerified': isEmailVerified,
      'preferences': preferences,
    };
  }

  UserModel copyWith({
    String? uid,
    String? email,
    String? displayName,
    String? photoUrl,
    DateTime? createdAt,
    DateTime? lastLoginAt,
    Map<String, dynamic>? preferences,
    bool? isEmailVerified,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      preferences: preferences ?? this.preferences,
      isEmailVerified: isEmailVerified ?? this.isEmailVerified,
    );
  }

  @override
  String toString() {
    return 'UserModel(uid: $uid, email: $email, displayName: $displayName)';
  }
} 