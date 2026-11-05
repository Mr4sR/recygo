import 'dart:convert';

class Labels {
  static const Map<String, String> categories = {
    'plastik': 'Plastic',
    'kertas_kardus': 'Paper/Cardboard',
    'logam': 'Metal',
    'kaca': 'Glass',
    'kain_tekstil': 'Fabric/Textile',
    'kayu': 'Wood',
    'elektronik': 'Electronics',
    'organik': 'Organic',
    'lainnya': 'Other',
  };
  static const Map<String, String> conditions = {
    'baru': 'New',
    'baik': 'Good',
    'cukup': 'Fair',
    'rusak_ringan': 'Lightly Damaged',
    'rusak_berat': 'Heavily Damaged',
  };
  static const Map<String, String> units = {
    'satuan': 'Piece',
    'kardus': 'Box',
    'karung': 'Sack',
    'paket': 'Bundle',
    'kilogram': 'Kilogram',
    'lainnya': 'Other',
  };
  static const Map<String, String> statuses = {
    'draft': 'Draft',
    'tersedia': 'Available',
    'diberikan': 'Given Away',
    'terjual': 'Sold',
    'habis': 'Out of Stock',
  };
  static const Map<String, String> listingTypes = {
    'jual': 'For Sale',
    'gratis': 'Free',
    'ajak_fuse': 'Fuse Together',
  };
  static const Map<String, String> difficulties = {
    'mudah': 'Easy',
    'sedang': 'Medium',
    'sulit': 'Hard',
  };

  static String category(String? code) => categories[code] ?? 'Other';
  static String condition(String? code) =>
      code == null ? '—' : (conditions[code] ?? code);
  static String unit(String? code) => units[code] ?? 'Piece';
  static String status(String? code) => statuses[code] ?? 'Available';
  static String listingType(String? code) => listingTypes[code] ?? '';
  static String difficulty(String? code) => difficulties[code] ?? 'Easy';
}

Map<String, dynamic> asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
  if (v is String && v.isNotEmpty) {
    try {
      final d = jsonDecode(v);
      if (d is Map) return d.map((k, val) => MapEntry(k.toString(), val));
    } catch (_) {}
  }
  return <String, dynamic>{};
}

List<dynamic> asList(dynamic v) {
  if (v is List) return v;
  if (v is String && v.isNotEmpty) {
    try {
      final d = jsonDecode(v);
      if (d is List) return d;
    } catch (_) {}
  }
  return <dynamic>[];
}

List<String> asStringList(dynamic v) =>
    asList(v).map((e) => e.toString()).where((e) => e.isNotEmpty).toList();

class Profile {
  final String id;
  final String displayName;
  final String? avatarUrl;
  final String? phone;
  final String? whatsapp;
  final String? bio;
  final String? city;
  final double? lat;
  final double? lng;

  const Profile({
    required this.id,
    required this.displayName,
    this.avatarUrl,
    this.phone,
    this.whatsapp,
    this.bio,
    this.city,
    this.lat,
    this.lng,
  });

  String? get contactNumber {
    if (whatsapp != null && whatsapp!.isNotEmpty) return whatsapp;
    if (phone != null && phone!.isNotEmpty) return phone;
    return null;
  }

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
    id: j['id'] as String,
    displayName: (j['display_name'] as String?) ?? '',
    avatarUrl: j['avatar_url'] as String?,
    phone: j['phone'] as String?,
    whatsapp: j['whatsapp'] as String?,
    bio: j['bio'] as String?,
    city: j['city'] as String?,
    lat: (j['lat'] as num?)?.toDouble(),
    lng: (j['lng'] as num?)?.toDouble(),
  );

  Map<String, dynamic> toUpdateJson() => {
    'display_name': displayName,
    'avatar_url': avatarUrl,
    'phone': phone,
    'whatsapp': whatsapp,
    'bio': bio,
    'city': city,
    'lat': lat,
    'lng': lng,
  };

  Profile copyWith({
    String? displayName,
    String? avatarUrl,
    String? phone,
    String? whatsapp,
    String? bio,
    String? city,
    double? lat,
    double? lng,
  }) => Profile(
    id: id,
    displayName: displayName ?? this.displayName,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    phone: phone ?? this.phone,
    whatsapp: whatsapp ?? this.whatsapp,
    bio: bio ?? this.bio,
    city: city ?? this.city,
    lat: lat ?? this.lat,
    lng: lng ?? this.lng,
  );
}
