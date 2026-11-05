import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/api/api_client.dart';
import '../../../core/config/env.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../auth/data/auth_repository.dart';
import 'fuse_recipe.dart';

class FuseRepository {
  bool get _demo => Env.demoMode;
  bool get _backend => Env.useBackend;

  Future<List<FuseRecipe>> fetchMyRecipes(String ownerId) async {
    if (_backend) {
      final data = await apiClient.getJson('/v1/recipes');
      return asJsonList(
        data,
      ).whereType<Map>().map((r) => FuseRecipe.fromJson(asJsonMap(r))).toList();
    }
    if (_demo) return DemoRecipes.all(ownerId);
    final rows = await supabase
        .from('fuse_recipes')
        .select()
        .eq('owner_id', ownerId)
        .order('created_at', ascending: false)
        .limit(100);
    return (rows as List)
        .map((r) => FuseRecipe.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<FuseRecipe?> fetchRecipe(String id) async {
    if (_backend) {
      try {
        final data = await apiClient.getJson('/v1/recipes/$id');
        return FuseRecipe.fromJson(asJsonMap(data));
      } on ApiException catch (e) {
        if (e.status == 404) return null;
        rethrow;
      }
    }
    if (_demo) {
      for (final r in DemoRecipes.store) {
        if (r.id == id) return r;
      }
      return null;
    }
    final rows = await supabase
        .from('fuse_recipes')
        .select()
        .eq('id', id)
        .limit(1);
    final list = rows as List;
    if (list.isEmpty) return null;
    return FuseRecipe.fromJson(list.first as Map<String, dynamic>);
  }

  Future<FuseRecipe> createRecipe(FuseRecipe recipe) async {
    if (_backend) {
      final data = await apiClient.postJson('/v1/recipes', {
        'data': {'id': recipe.id, ...recipe.toInsertJson()},
      });
      return FuseRecipe.fromJson(asJsonMap(data));
    }
    if (_demo) {
      DemoRecipes.store.insert(0, recipe);
      return recipe;
    }
    final row = await supabase
        .from('fuse_recipes')
        .insert(recipe.toInsertJson())
        .select()
        .single();
    return FuseRecipe.fromJson(row);
  }

  Future<void> updateRecipeImage(String id, String imageUrl) async {
    if (_backend) {
      await apiClient.patchJson('/v1/recipes/$id/image', {
        'data': {'imageUrl': imageUrl},
      });
      return;
    }
    if (_demo) {
      final idx = DemoRecipes.store.indexWhere((r) => r.id == id);
      if (idx >= 0) {
        final r = DemoRecipes.store[idx];
        DemoRecipes.store[idx] = FuseRecipe(
          id: r.id,
          ownerId: r.ownerId,
          title: r.title,
          description: r.description,
          steps: r.steps,
          difficulty: r.difficulty,
          estimatedMinutes: r.estimatedMinutes,
          imageUrl: imageUrl.isEmpty ? null : imageUrl,
          sourceItemIds: r.sourceItemIds,
          usedItems: r.usedItems,
          missingItems: r.missingItems,
          createdAt: r.createdAt,
        );
      }
      return;
    }
    await supabase
        .from('fuse_recipes')
        .update({'image_url': imageUrl})
        .eq('id', id);
  }

  Future<void> deleteRecipe(String id) async {
    if (_backend) {
      await apiClient.deleteJson('/v1/recipes/$id');
      return;
    }
    if (_demo) {
      DemoRecipes.store.removeWhere((r) => r.id == id);
      return;
    }
    await supabase.from('fuse_recipes').delete().eq('id', id);
  }

  Future<String> uploadFusePlaceholder(
    String uid,
    String recipeId,
    Uint8List bytes,
  ) async {
    if (_backend) {
      return apiClient.uploadBytes(
        bytes,
        filename: '$recipeId.png',
        folder: 'fuse',
        contentType: 'image/png',
      );
    }
    if (_demo) return '';
    final path = '$uid/$recipeId.png';
    await supabase.storage
        .from('fuse-images')
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/png',
          ),
        );
    return supabase.storage.from('fuse-images').getPublicUrl(path);
  }
}

class DemoRecipes {
  static final List<FuseRecipe> store = [];
  static List<FuseRecipe> all(String ownerId) =>
      store.where((r) => r.ownerId == ownerId).toList();
}

final fuseRepositoryProvider = Provider<FuseRepository>(
  (_) => FuseRepository(),
);

final myRecipesProvider = FutureProvider<List<FuseRecipe>>((ref) async {
  final profile = ref.watch(currentProfileProvider);
  if (profile == null) return const [];
  return ref.read(fuseRepositoryProvider).fetchMyRecipes(profile.id);
});

final recipeDetailProvider = FutureProvider.family<FuseRecipe?, String>((
  ref,
  id,
) async {
  return ref.read(fuseRepositoryProvider).fetchRecipe(id);
});
