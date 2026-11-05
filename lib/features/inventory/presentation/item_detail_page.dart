import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/labels.dart';
import '../../../core/utils/providers.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../community/data/community_repository.dart';
import '../data/item_repository.dart';

class ItemDetailPage extends ConsumerWidget {
  final String itemId;
  const ItemDetailPage({super.key, required this.itemId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(itemDetailProvider(itemId));
    final listingAsync = ref.watch(activeListingForItemProvider(itemId));
    final inFuse = ref.watch(fuseSelectionProvider).contains(itemId);

    return Scaffold(
      appBar: AppBar(title: const Text('Item Detail')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (item) {
          if (item == null) return const Center(child: Text('Item not found.'));
          final gallery = <String>[];
          if (item.cutoutPhotoUrl != null) gallery.add(item.cutoutPhotoUrl!);
          for (final u in item.photoUrls) {
            if (!gallery.contains(u)) gallery.add(u);
          }
          if (item.originalPhotoUrl != null &&
              !gallery.contains(item.originalPhotoUrl)) {
            gallery.add(item.originalPhotoUrl!);
          }
          final hasActiveListing = listingAsync.value != null;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              Hero(
                tag: item.id,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: gallery.isEmpty
                        ? const CutoutImage()
                        : PageView.builder(
                            itemCount: gallery.length,
                            itemBuilder: (_, i) => CachedNetworkImage(
                              imageUrl: gallery[i],
                              fit: BoxFit.contain,
                              memCacheWidth: 900,
                              errorWidget: (_, _, _) => const CutoutImage(),
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      item.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  if (item.isSegmented) const AiBadge(),
                ],
              ),
              if (item.isSegmented)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        size: 15,
                        color: AppColors.primary,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Automatically separated by AI',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Chip(label: Text(Labels.category(item.category))),
                  if (item.condition != null)
                    Chip(label: Text(Labels.condition(item.condition))),
                  Chip(label: Text(Labels.status(item.status))),
                  Chip(
                    label: Text('${item.quantity} × ${Labels.unit(item.unit)}'),
                  ),
                ],
              ),
              if (item.tags.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final t in item.tags) Chip(label: Text('#$t')),
                  ],
                ),
              ],
              if (item.description != null && item.description!.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(item.description!),
              ],
              const SizedBox(height: 14),
              _attr('Brand', item.brand ?? '—'),
              _attr('Material', item.material ?? '—'),
              if (item.createdAt != null)
                _attr('Added', timeAgo(item.createdAt!)),
              if (item.segmentation != null) ...[
                const SizedBox(height: 16),
                Text(
                  'Source Photo',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => context.push('/items/bulk-review'),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AspectRatio(
                      aspectRatio: 16 / 10,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if ((item.segmentation!['sourcePhotoUrl'] ?? '')
                              .toString()
                              .isNotEmpty)
                            CachedNetworkImage(
                              imageUrl: item.segmentation!['sourcePhotoUrl']
                                  .toString(),
                              fit: BoxFit.cover,
                              errorWidget: (_, _, _) =>
                                  Container(color: AppColors.accentMint),
                            )
                          else
                            Container(color: AppColors.accentMint),
                          CustomPaint(
                            painter: _BboxPainter(item.segmentation!),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap to reopen the bulk review for this batch.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 22),
              if (hasActiveListing)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.accentMint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: AppColors.primary,
                        size: 19,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This item has an active Community listing.',
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              AppButton(
                label: 'Publish to Community',
                icon: Icons.storefront_outlined,
                onPressed: () => context.push('/publish/${item.id}'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  ref.read(fuseSelectionProvider.notifier).add(item.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Added to Fuse selection. Open the Fuse tab.',
                      ),
                    ),
                  );
                },
                icon: Icon(inFuse ? Icons.check : Icons.auto_awesome),
                label: Text(inFuse ? 'In Fuse Selection' : 'Add to Fuse'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.push('/items/${item.id}/edit'),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                      ),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete Item?'),
                            content: const Text(
                              'This item, its photos, and related listings will be deleted.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (ok != true) return;
                        await ref.read(itemRepositoryProvider).deleteItem(item);
                        ref.invalidate(myItemsProvider);
                        if (context.mounted) context.go('/items');
                      },
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Delete'),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _attr(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: const TextStyle(color: AppColors.muted)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _BboxPainter extends CustomPainter {
  final Map<String, dynamic> seg;
  _BboxPainter(this.seg);

  @override
  void paint(Canvas canvas, Size size) {
    final bbox = seg['bbox'];
    if (bbox is! Map) return;
    double d(dynamic v) => (v as num?)?.toDouble() ?? 0;
    final rect = Rect.fromLTWH(
      d(bbox['x']) * size.width,
      d(bbox['y']) * size.height,
      d(bbox['w']) * size.width,
      d(bbox['h']) * size.height,
    );
    final paint = Paint()
      ..color = AppColors.secondary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _BboxPainter old) => old.seg != seg;
}
