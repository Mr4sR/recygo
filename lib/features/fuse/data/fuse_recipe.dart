class FuseRecipe {
  final String id;
  final String ownerId;
  final String title;
  final String description;
  final List<String> steps;
  final String difficulty;
  final int? estimatedMinutes;
  final String? imageUrl;
  final List<String> sourceItemIds;
  final List<UsedItem> usedItems;
  final List<MissingItem> missingItems;
  final DateTime? createdAt;

  const FuseRecipe({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.description,
    this.steps = const [],
    this.difficulty = 'mudah',
    this.estimatedMinutes,
    this.imageUrl,
    this.sourceItemIds = const [],
    this.usedItems = const [],
    this.missingItems = const [],
    this.createdAt,
  });

  factory FuseRecipe.fromJson(Map<String, dynamic> j) => FuseRecipe(
    id: j['id'] as String,
    ownerId: j['owner_id'] as String,
    title: (j['title'] as String?) ?? '',
    description: (j['description'] as String?) ?? '',
    steps: _strList(j['steps']),
    difficulty: (j['difficulty'] as String?) ?? 'mudah',
    estimatedMinutes: (j['estimated_minutes'] as num?)?.toInt(),
    imageUrl: j['image_url'] as String?,
    sourceItemIds: _strList(j['source_item_ids']),
    usedItems: _list(
      j['used_items'],
    ).map((e) => UsedItem.fromJson(_map(e))).toList(),
    missingItems: _list(
      j['missing_items'],
    ).map((e) => MissingItem.fromJson(_map(e))).toList(),
    createdAt: j['created_at'] != null
        ? DateTime.tryParse(j['created_at'].toString())
        : null,
  );

  Map<String, dynamic> toInsertJson() => {
    'owner_id': ownerId,
    'title': title,
    'description': description,
    'steps': steps,
    'difficulty': difficulty,
    'estimated_minutes': estimatedMinutes,
    'image_url': imageUrl,
    'source_item_ids': sourceItemIds,
    'used_items': usedItems.map((e) => e.toJson()).toList(),
    'missing_items': missingItems.map((e) => e.toJson()).toList(),
  };
}

class UsedItem {
  final String itemId;
  final String name;
  final String role;
  const UsedItem({required this.itemId, required this.name, this.role = ''});
  factory UsedItem.fromJson(Map<String, dynamic> j) => UsedItem(
    itemId: (j['itemId'] ?? '').toString(),
    name: (j['name'] ?? '').toString(),
    role: (j['role'] ?? '').toString(),
  );
  Map<String, dynamic> toJson() => {
    'itemId': itemId,
    'name': name,
    'role': role,
  };
}

class MissingItem {
  final String name;
  final String category;
  final String suggestion;
  const MissingItem({
    required this.name,
    this.category = 'lainnya',
    this.suggestion = '',
  });
  factory MissingItem.fromJson(Map<String, dynamic> j) => MissingItem(
    name: (j['name'] ?? '').toString(),
    category: (j['category'] ?? 'lainnya').toString(),
    suggestion: (j['suggestion'] ?? '').toString(),
  );
  Map<String, dynamic> toJson() => {
    'name': name,
    'category': category,
    'suggestion': suggestion,
  };
}

List<dynamic> _list(dynamic v) => v is List ? v : const [];
List<String> _strList(dynamic v) =>
    _list(v).map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
Map<String, dynamic> _map(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
  return <String, dynamic>{};
}
