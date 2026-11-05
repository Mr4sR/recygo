import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/labels.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../ai/data/ai_repository.dart';
import '../../inventory/data/item_repository.dart';
import '../data/fuse_repository.dart';

class FuseResultPage extends ConsumerStatefulWidget {
  final String recipeId;
  const FuseResultPage({super.key, required this.recipeId});
  @override
  ConsumerState<FuseResultPage> createState() => _FuseResultPageState();
}

class _FuseResultPageState extends ConsumerState<FuseResultPage> {
  bool _regenLoading = false;
  Timer? _imagePoll;
  int _imagePollTicks = 0;
  static const int _maxImagePollTicks = 30;

  @override
  void initState() {
    super.initState();
    // The illustration is generated in the background by the Fuse flow, so a
    // freshly opened result starts without one. Poll the recipe until the
    // backend stores the image URL instead of leaving a stale placeholder.
    _imagePoll = Timer.periodic(const Duration(seconds: 4), (_) {
      final recipe = ref.read(recipeDetailProvider(widget.recipeId)).value;
      if (recipe?.imageUrl != null || ++_imagePollTicks >= _maxImagePollTicks) {
        _stopImagePoll();
        if (mounted) setState(() {});
        return;
      }
      ref.invalidate(recipeDetailProvider(widget.recipeId));
    });
  }

  void _stopImagePoll() {
    _imagePoll?.cancel();
    _imagePoll = null;
  }

  @override
  void dispose() {
    _stopImagePoll();
    super.dispose();
  }

  Future<void> _regenerateImage() async {
    final recipe = ref.read(recipeDetailProvider(widget.recipeId)).value;
    if (recipe == null) return;
    setState(() => _regenLoading = true);
    try {
      // Re-derive a prompt from the title/description when the original is unknown.
      final prompt =
          'Photorealistic product photo of ${recipe.title}, made from recycled used items, clean bright background';
      String? refUrl;
      if (recipe.sourceItemIds.isNotEmpty) {
        final item = await ref
            .read(itemRepositoryProvider)
            .fetchItem(recipe.sourceItemIds.first);
        refUrl = item?.coverUrl;
      }
      final url = await ref
          .read(aiRepositoryProvider)
          .fuseImage(recipe.id, prompt, referenceImageUrl: refUrl);
      if (url.isNotEmpty) {
        await ref
            .read(fuseRepositoryProvider)
            .updateRecipeImage(recipe.id, url);
        ref.invalidate(recipeDetailProvider(widget.recipeId));
        ref.invalidate(myRecipesProvider);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Illustration could not be created. Try again.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _regenLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(recipeDetailProvider(widget.recipeId));
    // All recipes from the same Fuse batch, for quick switching.
    final recipesAsync = ref.watch(myRecipesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Fuse Result')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (recipe) {
          if (recipe == null) {
            return const Center(child: Text('Recipe not found.'));
          }
          final batch =
              recipesAsync.value
                  ?.where(
                    (r) =>
                        r.sourceItemIds.toSet().containsAll(
                          recipe.sourceItemIds,
                        ) &&
                        recipe.sourceItemIds.toSet().containsAll(
                          r.sourceItemIds,
                        ),
                  )
                  .toList() ??
              [recipe];
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              if (batch.length > 1) ...[
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: batch.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => TagChip(
                      label: batch[i].title,
                      selected: batch[i].id == recipe.id,
                      onTap: () => context.pushReplacement(
                        '/fuse/result/${batch[i].id}',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // Capped so the caption and actions below stay on screen.
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: recipe.imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: recipe.imageUrl!,
                            fit: BoxFit.cover,
                            memCacheWidth: 1000,
                            placeholder: (_, _) => const _ImagePlaceholder(),
                            errorWidget: (_, _, _) => const _ImagePlaceholder(),
                          )
                        : _ImagePlaceholder(
                            caption: _imagePoll != null
                                ? 'Creating illustration…'
                                : 'No illustration yet',
                          ),
                  ),
                ),
              ),
              if (recipe.imageUrl == null) ...[
                const SizedBox(height: 10),
                if (_imagePoll == null)
                  AppButton(
                    label: 'Create Illustration Again',
                    icon: Icons.image_outlined,
                    loading: _regenLoading,
                    onPressed: _regenerateImage,
                    ghost: true,
                  ),
              ] else ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _regenLoading ? null : _regenerateImage,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Regenerate Illustration'),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      recipe.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  const AiBadge(),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  Chip(label: Text(Labels.difficulty(recipe.difficulty))),
                  if (recipe.estimatedMinutes != null)
                    Chip(label: Text('~${recipe.estimatedMinutes} min')),
                ],
              ),
              const SizedBox(height: 10),
              Text(recipe.description),
              const SizedBox(height: 20),
              Text(
                'Materials You Use',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (recipe.usedItems.isEmpty)
                const Text('—')
              else
                for (final u in recipe.usedItems)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.check_circle,
                      color: AppColors.primary,
                    ),
                    title: Text(u.name),
                    subtitle: u.role.isNotEmpty ? Text(u.role) : null,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: u.itemId.isNotEmpty
                        ? () => context.push('/items/${u.itemId}')
                        : null,
                  ),
              const SizedBox(height: 12),
              Text('Steps', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              for (int i = 0; i < recipe.steps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 13,
                        backgroundColor: AppColors.primary,
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(recipe.steps[i])),
                    ],
                  ),
                ),
              if (recipe.missingItems.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  "Materials You Don't Have Yet",
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                for (final m in recipe.missingItems)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  Labels.category(m.category),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                if (m.suggestion.isNotEmpty)
                                  Text(
                                    m.suggestion,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                              ],
                            ),
                          ),
                          FilledButton(
                            onPressed: () {
                              final q = Uri.encodeQueryComponent(m.name);
                              context.go(
                                '/community?q=$q&category=${m.category}',
                              );
                            },
                            child: const Text('Find in Community'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  final String? caption;
  const _ImagePlaceholder({this.caption});
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      color: AppColors.accentMint,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 96,
              height: 96,
              child: Lottie.asset(
                'assets/lottie/ai_thinking.json',
                errorBuilder: (_, _, _) => const Icon(
                  Icons.auto_awesome,
                  size: 48,
                  color: AppColors.primary,
                ),
              ),
            ),
            if (caption != null) ...[
              const SizedBox(height: 12),
              Text(
                caption!,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
