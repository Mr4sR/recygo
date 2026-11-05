import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/labels.dart';
import '../../../core/widgets/app_widgets.dart';
import '../data/item.dart';
import '../data/item_repository.dart';

class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key});
  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage> {
  String _query = '';
  String _category = 'all';
  String _status = 'all';
  String _sort = 'newest';

  List<Item> _apply(List<Item> items) {
    var list = items.where((i) {
      final q = _query.trim().toLowerCase();
      final matchesQ =
          q.isEmpty ||
          i.name.toLowerCase().contains(q) ||
          i.tags.any((t) => t.toLowerCase().contains(q));
      final matchesC = _category == 'all' || i.category == _category;
      final matchesS = _status == 'all' || i.status == _status;
      return matchesQ && matchesC && matchesS;
    }).toList();
    switch (_sort) {
      case 'oldest':
        list.sort(
          (a, b) => (a.createdAt ?? DateTime(0)).compareTo(
            b.createdAt ?? DateTime(0),
          ),
        );
        break;
      case 'name':
        list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        break;
      default:
        list.sort(
          (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
            a.createdAt ?? DateTime(0),
          ),
        );
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myItemsProvider);
    final disableAnim = MediaQuery.of(context).disableAnimations;
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Collection'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort),
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'newest', child: Text('Newest')),
              PopupMenuItem(value: 'oldest', child: Text('Oldest')),
              PopupMenuItem(value: 'name', child: Text('Name A–Z')),
            ],
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'scanFab',
            onPressed: () => context.push('/items/new?scan=1'),
            icon: const Icon(Icons.document_scanner_outlined),
            label: const Text('Scan Many Items'),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'addFab',
            onPressed: () => context.push('/items/new'),
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('Add Item'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search by name or tag…',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                TagChip(
                  label: 'All',
                  selected: _category == 'all',
                  onTap: () => setState(() => _category = 'all'),
                ),
                const SizedBox(width: 6),
                for (final e in Labels.categories.entries) ...[
                  TagChip(
                    label: e.value,
                    selected: _category == e.key,
                    onTap: () => setState(() => _category = e.key),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Row(
              children: [
                TagChip(
                  label: 'All Status',
                  selected: _status == 'all',
                  onTap: () => setState(() => _status = 'all'),
                ),
                const SizedBox(width: 6),
                for (final e in Labels.statuses.entries) ...[
                  TagChip(
                    label: e.value,
                    selected: _status == e.key,
                    onTap: () => setState(() => _status = e.key),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.72,
                ),
                itemCount: 6,
                itemBuilder: (_, _) => const ShimmerCard(),
              ),
              error: (e, _) => Center(child: Text('Failed to load: $e')),
              data: (items) {
                final filtered = _apply(items);
                if (filtered.isEmpty) {
                  return EmptyState(
                    lottieAsset: 'assets/lottie/empty_box.json',
                    title: items.isEmpty
                        ? 'No items yet'
                        : 'Nothing matches your filters',
                    subtitle: items.isEmpty
                        ? 'Take a photo of a used item to start your collection.'
                        : 'Try a different search or filter.',
                    ctaLabel: items.isEmpty ? 'Photo Your First Item' : null,
                    onCta: items.isEmpty
                        ? () => context.push('/items/new')
                        : null,
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(myItemsProvider),
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 220,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.72,
                        ),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final item = filtered[i];
                      return ItemCard(
                            name: item.name,
                            categoryLabel: Labels.category(item.category),
                            conditionLabel: item.condition != null
                                ? Labels.condition(item.condition)
                                : null,
                            cutoutUrl: item.cutoutPhotoUrl,
                            photoUrls: item.photoUrls,
                            badgeText: item.isSegmented ? 'AI Cutout' : null,
                            onTap: () => context.push('/items/${item.id}'),
                          )
                          .animate(target: disableAnim ? 0 : 1)
                          .fadeIn(duration: 220.ms, delay: (i % 8 * 40).ms)
                          .slideY(begin: 0.08);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
