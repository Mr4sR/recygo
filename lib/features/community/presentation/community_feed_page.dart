import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/format.dart';
import '../../../core/utils/labels.dart';
import '../../../core/utils/providers.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../auth/data/auth_repository.dart';
import '../data/community_models.dart';
import '../data/community_repository.dart';

class CommunityFeedPage extends ConsumerStatefulWidget {
  final String? initialQuery;
  final String? initialCategory;
  const CommunityFeedPage({super.key, this.initialQuery, this.initialCategory});

  @override
  ConsumerState<CommunityFeedPage> createState() => _CommunityFeedPageState();
}

class _CommunityFeedPageState extends ConsumerState<CommunityFeedPage> {
  String _query = '';
  String _typeFilter = 'all';
  String _category = 'all';
  String _sort = 'newest';

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery ?? '';
    if (widget.initialCategory != null &&
        Labels.categories.containsKey(widget.initialCategory)) {
      _category = widget.initialCategory!;
    }
    // Default sort: nearest when location is available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final loc = ref.read(deviceLocationProvider).value;
      if (loc != null && mounted) setState(() => _sort = 'nearest');
    });
  }

  List<CommunityListing> _apply(List<CommunityListing> all, UserLocation? loc) {
    var list = all.where((l) {
      final item = l.item;
      final name = (item?.name ?? '').toLowerCase();
      final tags = item?.tags.join(' ').toLowerCase() ?? '';
      final q = _query.trim().toLowerCase();
      final matchesQ = q.isEmpty || name.contains(q) || tags.contains(q);
      final matchesT = _typeFilter == 'all' || l.listingType == _typeFilter;
      final matchesC =
          _category == 'all' || (item?.category ?? '') == _category;
      return matchesQ && matchesT && matchesC;
    }).toList();

    double? dist(CommunityListing l) {
      if (loc == null || l.lat == null || l.lng == null) return null;
      return haversineKm(loc.lat, loc.lng, l.lat!, l.lng!);
    }

    switch (_sort) {
      case 'nearest':
        list.sort((a, b) => (dist(a) ?? 1e9).compareTo(dist(b) ?? 1e9));
        break;
      case 'price_low':
        list.sort((a, b) => (a.price ?? 1e12).compareTo(b.price ?? 1e12));
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
    final async = ref.watch(communityListingsProvider);
    final loc = ref.watch(deviceLocationProvider).value;
    final repo = ref.read(communityRepositoryProvider);
    final profile = ref.watch(currentProfileProvider);
    final favorites = ref.watch(favoriteIdsProvider).value ?? const <String>{};
    final disableAnim = MediaQuery.of(context).disableAnimations;
    // Profile location is also acceptable for distance.
    final effectiveLoc =
        loc ??
        (profile?.lat != null
            ? UserLocation(profile!.lat!, profile.lng!)
            : null);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Community'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort),
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'nearest', child: Text('Nearest')),
              PopupMenuItem(value: 'newest', child: Text('Newest')),
              PopupMenuItem(value: 'price_low', child: Text('Lowest Price')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextFormField(
              initialValue: _query,
              decoration: const InputDecoration(
                hintText: 'Search items in Community…',
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
                  selected: _typeFilter == 'all',
                  onTap: () => setState(() => _typeFilter = 'all'),
                ),
                const SizedBox(width: 6),
                TagChip(
                  label: 'For Sale',
                  selected: _typeFilter == 'jual',
                  onTap: () => setState(() => _typeFilter = 'jual'),
                ),
                const SizedBox(width: 6),
                TagChip(
                  label: 'Free',
                  selected: _typeFilter == 'gratis',
                  onTap: () => setState(() => _typeFilter = 'gratis'),
                ),
                const SizedBox(width: 6),
                TagChip(
                  label: 'Fuse Together',
                  selected: _typeFilter == 'ajak_fuse',
                  onTap: () => setState(() => _typeFilter = 'ajak_fuse'),
                ),
                const SizedBox(width: 10),
                TagChip(
                  label: 'All Categories',
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
          Expanded(
            child: async.when(
              loading: () => GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.68,
                ),
                itemCount: 6,
                itemBuilder: (_, _) => const ShimmerCard(),
              ),
              error: (e, _) => Center(child: Text('Failed to load: $e')),
              data: (all) {
                final list = _apply(all, effectiveLoc);
                if (list.isEmpty) {
                  return const EmptyState(
                    lottieAsset: 'assets/lottie/empty_box.json',
                    title: 'No listings found',
                    subtitle:
                        'Try another search, or publish your own item to Community.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(communityListingsProvider);
                    ref.invalidate(favoriteIdsProvider);
                  },
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 220,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.68,
                        ),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final l = list[i];
                      final isMine = profile != null && l.ownerId == profile.id;
                      final isFav = favorites.contains(l.id);
                      return ItemCard(
                            name: l.item?.name ?? 'Used Item',
                            categoryLabel: Labels.category(l.item?.category),
                            conditionLabel: l.item?.condition != null
                                ? Labels.condition(l.item?.condition)
                                : null,
                            cutoutUrl: l.item?.cutoutPhotoUrl,
                            photoUrls: l.item?.photoUrls ?? const [],
                            priceText: l.listingType == 'jual'
                                ? formatRupiah(l.price)
                                : Labels.listingType(l.listingType),
                            badgeText: isMine ? 'Yours' : null,
                            trailing: IconButton(
                              tooltip: isFav ? 'Remove favorite' : 'Favorite',
                              icon: Icon(
                                isFav ? Icons.favorite : Icons.favorite_border,
                                size: 20,
                                color: isFav ? Colors.red : null,
                              ),
                              onPressed: () async {
                                if (profile == null) return;
                                await repo.toggleFavorite(
                                  profile.id,
                                  l.id,
                                  !isFav,
                                );
                                ref.invalidate(favoriteIdsProvider);
                              },
                            ),
                            onTap: () => context.push('/community/${l.id}'),
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
