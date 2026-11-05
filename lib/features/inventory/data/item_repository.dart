import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/api/api_client.dart';
import '../../../core/config/env.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../auth/data/auth_repository.dart';
import 'item.dart';

class ItemRepository {
  bool get _demo => Env.demoMode;
  bool get _backend => Env.useBackend;

  Future<List<Item>> fetchMyItems(String ownerId) async {
    if (_backend) {
      final data = await apiClient.getJson('/v1/items');
      return asJsonList(
        data,
      ).whereType<Map>().map((r) => Item.fromJson(asJsonMap(r))).toList();
    }
    if (_demo) {
      return DemoStore.items.where((i) => i.ownerId == ownerId).toList()..sort(
        (a, b) =>
            (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
      );
    }
    final rows = await supabase
        .from('items')
        .select()
        .eq('owner_id', ownerId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => Item.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<Item?> fetchItem(String id) async {
    if (_backend) {
      try {
        final data = await apiClient.getJson('/v1/items/$id');
        return Item.fromJson(asJsonMap(data));
      } on ApiException catch (e) {
        if (e.status == 404) return null;
        rethrow;
      }
    }
    if (_demo) {
      for (final i in DemoStore.items) {
        if (i.id == id) return i;
      }
      return null;
    }
    final rows = await supabase.from('items').select().eq('id', id).limit(1);
    final list = rows as List;
    if (list.isEmpty) return null;
    return Item.fromJson(list.first as Map<String, dynamic>);
  }

  Future<Item> createItem(Item item) async {
    if (_backend) {
      final data = await apiClient.postJson('/v1/items', {
        'data': item.toInsertJson(),
      });
      return Item.fromJson(asJsonMap(data));
    }
    if (_demo) {
      DemoStore.items.insert(0, item);
      return item;
    }
    final row = await supabase
        .from('items')
        .insert(item.toInsertJson())
        .select()
        .single();
    return Item.fromJson(row);
  }

  Future<Item> updateItem(Item item) async {
    if (_backend) {
      final data = await apiClient.patchJson('/v1/items/${item.id}', {
        'data': item.toUpdateJson(),
      });
      return Item.fromJson(asJsonMap(data));
    }
    if (_demo) {
      final idx = DemoStore.items.indexWhere((i) => i.id == item.id);
      if (idx >= 0) DemoStore.items[idx] = item;
      return item;
    }
    final row = await supabase
        .from('items')
        .update(item.toUpdateJson())
        .eq('id', item.id)
        .select()
        .single();
    return Item.fromJson(row);
  }

  Future<void> deleteItem(Item item) async {
    if (_backend) {
      await apiClient.deleteJson('/v1/items/${item.id}');
      return;
    }
    if (_demo) {
      DemoStore.items.removeWhere((i) => i.id == item.id);
      return;
    }
    await supabase.from('items').delete().eq('id', item.id);
    // Best-effort storage cleanup.
    final paths = <String>[];
    for (final url in [
      ...item.photoUrls,
      item.originalPhotoUrl,
      item.cutoutPhotoUrl,
    ]) {
      if (url == null) continue;
      final marker = '/item-photos/';
      final idx = url.indexOf(marker);
      if (idx >= 0) paths.add(url.substring(idx + marker.length));
    }
    if (paths.isNotEmpty) {
      try {
        await supabase.storage.from('item-photos').remove(paths);
      } catch (_) {}
    }
  }

  Future<String> uploadPhoto(
    String uid,
    String itemId,
    String filename,
    Uint8List bytes, {
    String contentType = 'image/jpeg',
  }) async {
    if (_backend) {
      return apiClient.uploadBytes(
        bytes,
        filename: filename,
        folder: 'items/$itemId',
        contentType: contentType,
      );
    }
    if (_demo) return '';
    final path = '$uid/$itemId/$filename';
    await supabase.storage
        .from('item-photos')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: contentType),
        );
    return supabase.storage.from('item-photos').getPublicUrl(path);
  }

  Future<String> uploadDraftPhoto(
    String uid,
    String draftId,
    String filename,
    Uint8List bytes, {
    String contentType = 'image/jpeg',
  }) async {
    if (_backend) {
      return apiClient.uploadBytes(
        bytes,
        filename: filename,
        folder: 'draft/$draftId',
        contentType: contentType,
      );
    }
    if (_demo) return '';
    final path = '$uid/draft/$draftId/$filename';
    await supabase.storage
        .from('item-photos')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: contentType),
        );
    return supabase.storage.from('item-photos').getPublicUrl(path);
  }

  Future<void> deleteDraftFolder(String uid, String draftId) async {
    if (_backend || _demo) return;
    try {
      final files = await supabase.storage
          .from('item-photos')
          .list(path: '$uid/draft/$draftId');
      if (files.isNotEmpty) {
        await supabase.storage
            .from('item-photos')
            .remove(files.map((f) => '$uid/draft/$draftId/${f.name}').toList());
      }
    } catch (_) {}
  }

  Future<void> removeByUrls(List<String> urls) async {
    if (_backend || _demo) return;
    final paths = <String>[];
    for (final url in urls) {
      final marker = '/item-photos/';
      final idx = url.indexOf(marker);
      if (idx >= 0) paths.add(url.substring(idx + marker.length));
    }
    if (paths.isEmpty) return;
    try {
      await supabase.storage.from('item-photos').remove(paths);
    } catch (_) {}
  }
}

final itemRepositoryProvider = Provider<ItemRepository>(
  (_) => ItemRepository(),
);

final myItemsProvider = FutureProvider<List<Item>>((ref) async {
  final profile = ref.watch(currentProfileProvider);
  if (profile == null) return const [];
  return ref.read(itemRepositoryProvider).fetchMyItems(profile.id);
});

final itemDetailProvider = FutureProvider.family<Item?, String>((
  ref,
  id,
) async {
  return ref.read(itemRepositoryProvider).fetchItem(id);
});
