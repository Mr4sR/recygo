import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/utils/labels.dart';
import '../../../core/utils/providers.dart';
import '../../../core/utils/sfx.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../ai/data/ai_repository.dart';
import '../../auth/data/auth_repository.dart';
import '../../inventory/data/item_repository.dart';
import '../data/fuse_recipe.dart';
import '../data/fuse_repository.dart';

class FuseSelectPage extends ConsumerWidget {
  const FuseSelectPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(myItemsProvider);
    final recipesAsync = ref.watch(myRecipesProvider);
    final selected = ref.watch(fuseSelectionProvider);
    final disableAnim = MediaQuery.of(context).disableAnimations;

    return Scaffold(
      appBar: AppBar(title: const Text('Fuse — Create Together')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const Text(
            'Pick 2–6 items from your Collection, then let AI invent creations that combine them.',
          ),
          const SizedBox(height: 14),
          itemsAsync.when(
            loading: () => const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('Failed to load items: $e'),
            data: (items) {
              if (items.isEmpty) {
                return const EmptyState(
                  lottieAsset: 'assets/lottie/empty_box.json',
                  title: 'No items yet',
                  subtitle:
                      'Add items to your Collection first, then Fuse them here.',
                );
              }
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.72,
                ),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final item = items[i];
                  final isSel = selected.contains(item.id);
                  return Stack(
                    children: [
                      ItemCard(
                            name: item.name,
                            categoryLabel: Labels.category(item.category),
                            conditionLabel: item.condition != null
                                ? Labels.condition(item.condition)
                                : null,
                            cutoutUrl: item.cutoutPhotoUrl,
                            photoUrls: item.photoUrls,
                            onTap: () => ref
                                .read(fuseSelectionProvider.notifier)
                                .toggle(item.id),
                          )
                          .animate(target: disableAnim ? 0 : 1)
                          .fadeIn(duration: 200.ms, delay: (i % 8 * 40).ms),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: CircleAvatar(
                          radius: 15,
                          backgroundColor: isSel
                              ? Theme.of(context).colorScheme.primary
                              : Colors.black38,
                          child: Icon(
                            isSel ? Icons.check : Icons.add,
                            size: 17,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      if (isSel)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 2.4,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          ),
          const SizedBox(height: 18),
          AppButton(
            label: selected.length < 2
                ? 'Fuse with AI (pick at least 2)'
                : 'Fuse with AI (${selected.length} items)',
            icon: Icons.auto_awesome,
            onPressed: selected.length < 2
                ? null
                : () async {
                    Sfx.instance.fuseMagic();
                    await _runFuse(context, ref);
                  },
          ),
          const SizedBox(height: 26),
          Text(
            'My Fuse Results',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          recipesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Failed to load recipes: $e'),
            data: (recipes) {
              if (recipes.isEmpty) {
                return const Text(
                  'No Fuse results yet. Create your first one above!',
                );
              }
              return Column(
                children: [
                  for (final r in recipes)
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        leading: SizedBox(
                          width: 56,
                          height: 56,
                          child: r.imageUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: r.imageUrl!,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, _, _) =>
                                      const Icon(Icons.auto_awesome),
                                )
                              : const Icon(Icons.auto_awesome),
                        ),
                        title: Text(
                          r.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${Labels.difficulty(r.difficulty)}${r.estimatedMinutes != null ? ' • ~${r.estimatedMinutes} min' : ''}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Delete recipe',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await ref
                                .read(fuseRepositoryProvider)
                                .deleteRecipe(r.id);
                            ref.invalidate(myRecipesProvider);
                          },
                        ),
                        onTap: () => context.push('/fuse/result/${r.id}'),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _runFuse(BuildContext context, WidgetRef ref) async {
    final profile = ref.read(currentProfileProvider);
    if (profile == null) return;
    final repo = ref.read(fuseRepositoryProvider);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('AI is inventing creations…')),
          ],
        ),
      ),
    );
    try {
      final all = await ref
          .read(itemRepositoryProvider)
          .fetchMyItems(profile.id);
      final selectedIds = ref.read(fuseSelectionProvider);
      final chosen = all.where((i) => selectedIds.contains(i.id)).toList();
      final ideas = await ref.read(aiRepositoryProvider).fuse(chosen);
      if (ideas.isEmpty) {
        throw Exception('AI could not create ideas. Please try again.');
      }
      FuseRecipe? first;
      for (final idea in ideas) {
        final recipe = FuseRecipe(
          id: const Uuid().v4(),
          ownerId: profile.id,
          title: idea.title,
          description: idea.description,
          steps: idea.steps,
          difficulty: idea.difficulty,
          estimatedMinutes: idea.estimatedMinutes,
          sourceItemIds: chosen.map((i) => i.id).toList(),
          usedItems: idea.usedItems
              .map(
                (u) => UsedItem(
                  itemId: (u['itemId'] ?? '').toString(),
                  name: (u['name'] ?? '').toString(),
                  role: (u['role'] ?? '').toString(),
                ),
              )
              .toList(),
          missingItems: idea.missingItems
              .map(
                (m) => MissingItem(
                  name: (m['name'] ?? '').toString(),
                  category: (m['category'] ?? 'lainnya').toString(),
                  suggestion: (m['suggestion'] ?? '').toString(),
                ),
              )
              .toList(),
        );
        final saved = await repo.createRecipe(recipe.copyWithId(recipe.id));
        first ??= saved;
        // Async illustration (failure must not fail the recipe).
        final refUrl = chosen.isNotEmpty ? chosen.first.coverUrl : null;
        ref
            .read(aiRepositoryProvider)
            .fuseImage(saved.id, idea.imagePrompt, referenceImageUrl: refUrl)
            .then((url) async {
              if (url.isNotEmpty) {
                await repo.updateRecipeImage(saved.id, url);
                ref.invalidate(myRecipesProvider);
                ref.invalidate(recipeDetailProvider(saved.id));
              }
            })
            .catchError((_) {});
      }
      ref.invalidate(myRecipesProvider);
      if (!context.mounted) return;
      Navigator.of(context).pop();
      if (first != null) context.push('/fuse/result/${first.id}');
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }
}

extension on FuseRecipe {
  FuseRecipe copyWithId(String id) => FuseRecipe(
    id: id,
    ownerId: ownerId,
    title: title,
    description: description,
    steps: steps,
    difficulty: difficulty,
    estimatedMinutes: estimatedMinutes,
    imageUrl: imageUrl,
    sourceItemIds: sourceItemIds,
    usedItems: usedItems,
    missingItems: missingItems,
    createdAt: createdAt,
  );
}
