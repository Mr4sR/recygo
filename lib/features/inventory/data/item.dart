import '../../../core/utils/labels.dart';

class Item {
  final String id;
  final String ownerId;
  final String name;
  final String category;
  final List<String> tags;
  final String? description;
  final String? condition;
  final String? brand;
  final String? material;
  final String unit;
  final int quantity;
  final List<String> photoUrls;
  final String? originalPhotoUrl;
  final String? cutoutPhotoUrl;
  final Map<String, dynamic>? segmentation;
  final String status;
  final bool isPublished;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Item({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.category,
    this.tags = const [],
    this.description,
    this.condition,
    this.brand,
    this.material,
    this.unit = 'satuan',
    this.quantity = 1,
    this.photoUrls = const [],
    this.originalPhotoUrl,
    this.cutoutPhotoUrl,
    this.segmentation,
    this.status = 'tersedia',
    this.isPublished = false,
    this.createdAt,
    this.updatedAt,
  });

  String? get coverUrl {
    if (cutoutPhotoUrl != null && cutoutPhotoUrl!.isNotEmpty) {
      return cutoutPhotoUrl;
    }
    if (photoUrls.isNotEmpty) return photoUrls.first;
    return originalPhotoUrl;
  }

  bool get isSegmented =>
      segmentation != null && segmentation!['source'] == 'sam31';

  factory Item.fromJson(Map<String, dynamic> j) => Item(
    id: j['id'] as String,
    ownerId: j['owner_id'] as String,
    name: (j['name'] as String?) ?? '',
    category: (j['category'] as String?) ?? 'lainnya',
    tags: asStringList(j['tags']),
    description: j['description'] as String?,
    condition: j['condition'] as String?,
    brand: j['brand'] as String?,
    material: j['material'] as String?,
    unit: (j['unit'] as String?) ?? 'satuan',
    quantity: (j['quantity'] as num?)?.toInt() ?? 1,
    photoUrls: asStringList(j['photo_urls']),
    originalPhotoUrl: j['original_photo_url'] as String?,
    cutoutPhotoUrl: j['cutout_photo_url'] as String?,
    segmentation: j['segmentation'] == null ? null : asMap(j['segmentation']),
    status: (j['status'] as String?) ?? 'tersedia',
    isPublished: (j['is_published'] as bool?) ?? false,
    createdAt: j['created_at'] != null
        ? DateTime.tryParse(j['created_at'].toString())
        : null,
    updatedAt: j['updated_at'] != null
        ? DateTime.tryParse(j['updated_at'].toString())
        : null,
  );

  Map<String, dynamic> toInsertJson() => {
    'id': id,
    'owner_id': ownerId,
    'name': name,
    'category': category,
    'tags': tags,
    'description': description,
    'condition': condition,
    'brand': brand,
    'material': material,
    'unit': unit,
    'quantity': quantity,
    'photo_urls': photoUrls,
    'original_photo_url': originalPhotoUrl,
    'cutout_photo_url': cutoutPhotoUrl,
    'segmentation': segmentation,
    'status': status,
    'is_published': isPublished,
  };

  Map<String, dynamic> toUpdateJson() => {
    'name': name,
    'category': category,
    'tags': tags,
    'description': description,
    'condition': condition,
    'brand': brand,
    'material': material,
    'unit': unit,
    'quantity': quantity,
    'photo_urls': photoUrls,
    'original_photo_url': originalPhotoUrl,
    'cutout_photo_url': cutoutPhotoUrl,
    'segmentation': segmentation,
    'status': status,
    'is_published': isPublished,
  };

  Item copyWith({
    String? name,
    String? category,
    List<String>? tags,
    String? description,
    String? condition,
    String? brand,
    String? material,
    String? unit,
    int? quantity,
    List<String>? photoUrls,
    String? originalPhotoUrl,
    String? cutoutPhotoUrl,
    Map<String, dynamic>? segmentation,
    String? status,
    bool? isPublished,
  }) => Item(
    id: id,
    ownerId: ownerId,
    name: name ?? this.name,
    category: category ?? this.category,
    tags: tags ?? this.tags,
    description: description ?? this.description,
    condition: condition ?? this.condition,
    brand: brand ?? this.brand,
    material: material ?? this.material,
    unit: unit ?? this.unit,
    quantity: quantity ?? this.quantity,
    photoUrls: photoUrls ?? this.photoUrls,
    originalPhotoUrl: originalPhotoUrl ?? this.originalPhotoUrl,
    cutoutPhotoUrl: cutoutPhotoUrl ?? this.cutoutPhotoUrl,
    segmentation: segmentation ?? this.segmentation,
    status: status ?? this.status,
    isPublished: isPublished ?? this.isPublished,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Validated AI auto-fill result (from ai-analyze-item).
class AiItemSuggestion {
  final String name;
  final String category;
  final List<String> tags;
  final String? description;
  final String? condition;
  final String? brand;
  final String? material;
  final String unitGuess;
  final int quantityGuess;
  final double confidence;

  const AiItemSuggestion({
    required this.name,
    required this.category,
    this.tags = const [],
    this.description,
    this.condition,
    this.brand,
    this.material,
    this.unitGuess = 'satuan',
    this.quantityGuess = 1,
    this.confidence = 0,
  });

  static const _categories = {
    'plastik',
    'kertas_kardus',
    'logam',
    'kaca',
    'kain_tekstil',
    'kayu',
    'elektronik',
    'organik',
    'lainnya',
  };
  static const _conditions = {
    'baru',
    'baik',
    'cukup',
    'rusak_ringan',
    'rusak_berat',
  };
  static const _units = {
    'satuan',
    'kardus',
    'karung',
    'paket',
    'kilogram',
    'lainnya',
  };

  /// Parse + validate: out-of-enum values fall back, strings trimmed, confidence clamped.
  factory AiItemSuggestion.fromJson(Map<String, dynamic> j) {
    final categoryValue = j['category'];
    final conditionValue = j['condition'];
    final unitValue = j['unitGuess'];
    final catRaw = categoryValue is String ? categoryValue.trim() : '';
    final condRaw = conditionValue is String ? conditionValue.trim() : '';
    final unitRaw = unitValue is String ? unitValue.trim() : '';
    final confidenceValue = j['confidence'];
    final quantityValue = j['quantityGuess'];
    final confRaw = confidenceValue is num ? confidenceValue.toDouble() : 0.0;
    final qtyRaw = quantityValue is num ? quantityValue.toInt() : 1;
    String? clean(dynamic v) {
      if (v is! String) return null;
      final s = v.trim();
      return s.isEmpty ? null : s;
    }

    return AiItemSuggestion(
      name: (clean(j['name']) ?? 'Used Item'),
      category: _categories.contains(catRaw) ? catRaw : 'lainnya',
      tags: (j['tags'] is List ? j['tags'] as List : const [])
          .whereType<String>()
          .map((t) => t.toLowerCase().trim())
          .where((t) => t.isNotEmpty)
          .take(6)
          .toList(),
      description: clean(j['description']),
      condition: _conditions.contains(condRaw) ? condRaw : null,
      brand: clean(j['brand']),
      material: clean(j['material']),
      unitGuess: _units.contains(unitRaw) ? unitRaw : 'satuan',
      quantityGuess: qtyRaw < 1 ? 1 : qtyRaw,
      confidence: confRaw.clamp(0.0, 1.0),
    );
  }
}
