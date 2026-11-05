import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/config/env.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/labels.dart';
import '../../auth/data/auth_repository.dart';
import 'community_models.dart';

class CommunityRepository {
  bool get _demo => Env.demoMode;
  bool get _backend => Env.useBackend;

  Future<List<CommunityListing>> fetchListings() async {
    if (_backend) {
      final data = await apiClient.getJson('/v1/listings');
      return asJsonList(data)
          .whereType<Map>()
          .map((r) => CommunityListing.fromJson(asJsonMap(r)))
          .toList();
    }
    if (_demo) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return DemoListings.all();
    }
    final rows = await supabase
        .from('community_listings')
        .select('*, items(*), profiles!community_listings_owner_id_fkey(*)')
        .eq('is_active', true)
        .order('created_at', ascending: false)
        .limit(200);
    return (rows as List)
        .map((r) => CommunityListing.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<CommunityListing?> fetchListing(String id) async {
    if (_backend) {
      try {
        final data = await apiClient.getJson('/v1/listings/$id');
        return CommunityListing.fromJson(asJsonMap(data));
      } on ApiException catch (e) {
        if (e.status == 404) return null;
        rethrow;
      }
    }
    if (_demo) {
      for (final l in DemoListings.all()) {
        if (l.id == id) return l;
      }
      return null;
    }
    final rows = await supabase
        .from('community_listings')
        .select('*, items(*), profiles!community_listings_owner_id_fkey(*)')
        .eq('id', id)
        .limit(1);
    final list = rows as List;
    if (list.isEmpty) return null;
    return CommunityListing.fromJson(list.first as Map<String, dynamic>);
  }

  Future<CommunityListing?> fetchActiveListingForItem(String itemId) async {
    if (_backend) {
      try {
        final data = await apiClient.getJson('/v1/listings/by-item/$itemId');
        return CommunityListing.fromJson(asJsonMap(data));
      } on ApiException catch (e) {
        if (e.status == 404) return null;
        rethrow;
      }
    }
    if (_demo) {
      for (final l in DemoListings.all()) {
        if (l.itemId == itemId && l.isActive) return l;
      }
      return null;
    }
    final rows = await supabase
        .from('community_listings')
        .select('*, items(*), profiles!community_listings_owner_id_fkey(*)')
        .eq('item_id', itemId)
        .eq('is_active', true)
        .limit(1);
    final list = rows as List;
    if (list.isEmpty) return null;
    return CommunityListing.fromJson(list.first as Map<String, dynamic>);
  }

  Future<CommunityListing> publish({
    required String itemId,
    required String ownerId,
    required String listingType,
    required double? price,
    required String? note,
    required double? lat,
    required double? lng,
  }) async {
    if (_backend) {
      final data = await apiClient.postJson('/v1/listings', {
        'data': {
          'item_id': itemId,
          'listing_type': listingType,
          'price': listingType == 'jual' ? price : null,
          'note': note,
          'lat': lat,
          'lng': lng,
        },
      });
      return CommunityListing.fromJson(asJsonMap(data));
    }
    if (_demo) {
      final listing = CommunityListing(
        id: 'demo-listing-${DateTime.now().millisecondsSinceEpoch}',
        itemId: itemId,
        ownerId: ownerId,
        listingType: listingType,
        price: price,
        note: note,
        lat: lat,
        lng: lng,
        isActive: true,
        createdAt: DateTime.now(),
      );
      DemoListings.extra.insert(0, listing);
      final idx = DemoStore.items.indexWhere((i) => i.id == itemId);
      if (idx >= 0) {
        DemoStore.items[idx] = DemoStore.items[idx].copyWith(isPublished: true);
      }
      return listing;
    }
    final row = await supabase
        .from('community_listings')
        .insert({
          'item_id': itemId,
          'owner_id': ownerId,
          'listing_type': listingType,
          'price': listingType == 'jual' ? price : null,
          'note': note,
          'lat': lat,
          'lng': lng,
          'is_active': true,
        })
        .select('*, items(*), profiles!community_listings_owner_id_fkey(*)')
        .single();
    await supabase
        .from('items')
        .update({'is_published': true})
        .eq('id', itemId);
    return CommunityListing.fromJson(row);
  }

  Future<CommunityListing> updateListing({
    required String listingId,
    required String listingType,
    required double? price,
    required String? note,
    required double? lat,
    required double? lng,
  }) async {
    if (_backend) {
      final data = await apiClient.patchJson('/v1/listings/$listingId', {
        'data': {
          'listing_type': listingType,
          'price': listingType == 'jual' ? price : null,
          'note': note,
          'lat': lat,
          'lng': lng,
        },
      });
      return CommunityListing.fromJson(asJsonMap(data));
    }
    if (_demo) {
      final all = DemoListings.all();
      final idx = all.indexWhere((l) => l.id == listingId);
      CommunityListing updated = CommunityListing(
        id: listingId,
        itemId: idx >= 0 ? all[idx].itemId : '',
        ownerId: idx >= 0 ? all[idx].ownerId : '',
        listingType: listingType,
        price: price,
        note: note,
        lat: lat,
        lng: lng,
        isActive: true,
      );
      final eIdx = DemoListings.extra.indexWhere((l) => l.id == listingId);
      if (eIdx >= 0) DemoListings.extra[eIdx] = updated;
      return updated;
    }
    final row = await supabase
        .from('community_listings')
        .update({
          'listing_type': listingType,
          'price': listingType == 'jual' ? price : null,
          'note': note,
          'lat': lat,
          'lng': lng,
        })
        .eq('id', listingId)
        .select('*, items(*), profiles!community_listings_owner_id_fkey(*)')
        .single();
    return CommunityListing.fromJson(row);
  }

  Future<void> closeListing(String listingId, String itemId) async {
    if (_backend) {
      await apiClient.postJson('/v1/listings/$listingId/close', {
        'data': {'itemId': itemId},
      });
      return;
    }
    if (_demo) {
      DemoListings.extra.removeWhere((l) => l.id == listingId);
      final idx = DemoStore.items.indexWhere((i) => i.id == itemId);
      if (idx >= 0) {
        DemoStore.items[idx] = DemoStore.items[idx].copyWith(
          isPublished: false,
        );
      }
      return;
    }
    await supabase
        .from('community_listings')
        .update({'is_active': false})
        .eq('id', listingId);
    await supabase
        .from('items')
        .update({'is_published': false})
        .eq('id', itemId);
  }

  Future<Set<String>> fetchFavoriteIds(String userId) async {
    if (_backend) {
      final data = await apiClient.getJson('/v1/favorites');
      final ids = data is Map ? (data['ids'] as List? ?? const []) : const [];
      return ids.map((e) => e.toString()).toSet();
    }
    if (_demo) return DemoFavorites.ids;
    final rows = await supabase
        .from('favorites')
        .select('listing_id')
        .eq('user_id', userId);
    return (rows as List)
        .map((r) => (r as Map)['listing_id'].toString())
        .toSet();
  }

  Future<void> toggleFavorite(String userId, String listingId, bool fav) async {
    if (_backend) {
      await apiClient.postJson('/v1/favorites', {
        'data': {'listingId': listingId, 'fav': fav},
      });
      return;
    }
    if (_demo) {
      if (fav) {
        DemoFavorites.ids.add(listingId);
      } else {
        DemoFavorites.ids.remove(listingId);
      }
      return;
    }
    if (fav) {
      await supabase.from('favorites').insert({
        'user_id': userId,
        'listing_id': listingId,
      });
    } else {
      await supabase
          .from('favorites')
          .delete()
          .eq('user_id', userId)
          .eq('listing_id', listingId);
    }
  }
}

class DemoFavorites {
  static final Set<String> ids = {};
}

class DemoListings {
  static final List<CommunityListing> extra = [];
  static List<CommunityListing> all() {
    const other = Profile(
      id: 'demo-other',
      displayName: 'Sari Green',
      whatsapp: '6281298765432',
      phone: '6281298765432',
      city: 'Central Jakarta',
      lat: -6.19,
      lng: 106.838,
    );
    final items = DemoStore.items;
    final base = <CommunityListing>[
      CommunityListing(
        id: 'demo-listing-1',
        itemId: items.isNotEmpty ? items[0].id : 'demo-item-1',
        ownerId: 'demo-other',
        listingType: 'gratis',
        note: 'Free to pick up this weekend.',
        lat: -6.19,
        lng: 106.838,
        isActive: true,
        createdAt: DateTime.now().subtract(const Duration(hours: 5)),
        item: items.isNotEmpty ? items[0] : null,
        owner: other,
      ),
      CommunityListing(
        id: 'demo-listing-2',
        itemId: 'demo-item-x',
        ownerId: 'demo-other',
        listingType: 'jual',
        price: 25000,
        note: 'Selling used glass jars, 12 pcs.',
        lat: -6.21,
        lng: 106.85,
        isActive: true,
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        item: null,
        owner: other,
      ),
      CommunityListing(
        id: 'demo-listing-3',
        itemId: 'demo-item-y',
        ownerId: 'demo-other',
        listingType: 'ajak_fuse',
        note: 'Looking for partners to build planters together.',
        lat: -6.24,
        lng: 106.80,
        isActive: true,
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        item: null,
        owner: other,
      ),
    ];
    return [...extra, ...base];
  }
}

final communityRepositoryProvider = Provider<CommunityRepository>(
  (_) => CommunityRepository(),
);

final communityListingsProvider = FutureProvider<List<CommunityListing>>((
  ref,
) async {
  return ref.read(communityRepositoryProvider).fetchListings();
});

final listingDetailProvider = FutureProvider.family<CommunityListing?, String>((
  ref,
  id,
) async {
  return ref.read(communityRepositoryProvider).fetchListing(id);
});

final activeListingForItemProvider =
    FutureProvider.family<CommunityListing?, String>((ref, itemId) async {
      return ref
          .read(communityRepositoryProvider)
          .fetchActiveListingForItem(itemId);
    });

final favoriteIdsProvider = FutureProvider<Set<String>>((ref) async {
  final profile = ref.watch(currentProfileProvider);
  if (profile == null) return const {};
  return ref.read(communityRepositoryProvider).fetchFavoriteIds(profile.id);
});
