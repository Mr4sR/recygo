import '../../../core/utils/labels.dart';
import '../../inventory/data/item.dart';

class CommunityListing {
  final String id;
  final String itemId;
  final String ownerId;
  final String listingType;
  final double? price;
  final String? note;
  final double? lat;
  final double? lng;
  final bool isActive;
  final DateTime? createdAt;
  final Item? item;
  final Profile? owner;

  const CommunityListing({
    required this.id,
    required this.itemId,
    required this.ownerId,
    required this.listingType,
    this.price,
    this.note,
    this.lat,
    this.lng,
    this.isActive = true,
    this.createdAt,
    this.item,
    this.owner,
  });

  bool get isForSale => listingType == 'jual';
  bool get isFree => listingType == 'gratis';

  factory CommunityListing.fromJson(Map<String, dynamic> j) {
    final itemRaw = j['items'];
    final ownerRaw = j['profiles'];
    return CommunityListing(
      id: j['id'] as String,
      itemId: j['item_id'] as String,
      ownerId: j['owner_id'] as String,
      listingType: (j['listing_type'] as String?) ?? 'gratis',
      price: (j['price'] as num?)?.toDouble(),
      note: j['note'] as String?,
      lat: (j['lat'] as num?)?.toDouble(),
      lng: (j['lng'] as num?)?.toDouble(),
      isActive: (j['is_active'] as bool?) ?? true,
      createdAt: j['created_at'] != null
          ? DateTime.tryParse(j['created_at'].toString())
          : null,
      item: itemRaw is Map ? Item.fromJson(asMap(itemRaw)) : null,
      owner: ownerRaw is Map ? Profile.fromJson(asMap(ownerRaw)) : null,
    );
  }
}

class WasteBank {
  final String id;
  final String name;
  final String? description;
  final String address;
  final String? city;
  final double lat;
  final double lng;
  final String? phone;
  final String? whatsapp;
  final String? openingHours;
  final List<String> acceptedCategories;
  final String? priceInfo;
  final String? photoUrl;
  final bool isVerified;

  const WasteBank({
    required this.id,
    required this.name,
    this.description,
    required this.address,
    this.city,
    required this.lat,
    required this.lng,
    this.phone,
    this.whatsapp,
    this.openingHours,
    this.acceptedCategories = const [],
    this.priceInfo,
    this.photoUrl,
    this.isVerified = true,
  });

  String? get contactNumber {
    if (whatsapp != null && whatsapp!.isNotEmpty) return whatsapp;
    if (phone != null && phone!.isNotEmpty) return phone;
    return null;
  }

  factory WasteBank.fromJson(Map<String, dynamic> j) => WasteBank(
    id: j['id'] as String,
    name: (j['name'] as String?) ?? '',
    description: j['description'] as String?,
    address: (j['address'] as String?) ?? '',
    city: j['city'] as String?,
    lat: (j['lat'] as num?)?.toDouble() ?? 0,
    lng: (j['lng'] as num?)?.toDouble() ?? 0,
    phone: j['phone'] as String?,
    whatsapp: j['whatsapp'] as String?,
    openingHours: j['opening_hours'] as String?,
    acceptedCategories: asStringList(j['accepted_categories']),
    priceInfo: j['price_info'] as String?,
    photoUrl: j['photo_url'] as String?,
    isVerified: (j['is_verified'] as bool?) ?? true,
  );
}
