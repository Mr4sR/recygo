import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/format.dart';
import '../../../core/utils/labels.dart';
import '../../../core/utils/providers.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../auth/data/auth_repository.dart';
import '../../wastebank/presentation/wastebank_pages.dart';
import '../data/community_models.dart';
import '../data/community_repository.dart';

class ListingDetailPage extends ConsumerWidget {
  final String listingId;
  const ListingDetailPage({super.key, required this.listingId});

  Future<void> _launch(Uri uri, BuildContext context) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the link.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the link.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(listingDetailProvider(listingId));
    final profile = ref.watch(currentProfileProvider);
    final favorites = ref.watch(favoriteIdsProvider).value ?? const <String>{};
    final isFav = favorites.contains(listingId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Listing Detail'),
        actions: [
          IconButton(
            tooltip: isFav ? 'Remove favorite' : 'Favorite',
            icon: Icon(
              isFav ? Icons.favorite : Icons.favorite_border,
              color: isFav ? Colors.red : null,
            ),
            onPressed: () async {
              if (profile == null) return;
              await ref
                  .read(communityRepositoryProvider)
                  .toggleFavorite(profile.id, listingId, !isFav);
              ref.invalidate(favoriteIdsProvider);
            },
          ),
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.share_outlined),
            onPressed: () async {
              await _launch(Uri.parse(Uri.base.toString()), context);
            },
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (listing) {
          if (listing == null) {
            return const Center(child: Text('Listing not found.'));
          }
          return _body(context, ref, listing, profile?.id);
        },
      ),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    CommunityListing listing,
    String? myId,
  ) {
    final item = listing.item;
    final owner = listing.owner;
    final isMine = myId != null && listing.ownerId == myId;
    final contact = owner?.contactNumber;
    final profile = ref.watch(currentProfileProvider);
    final loc =
        ref.watch(deviceLocationProvider).value ??
        (profile?.lat != null
            ? UserLocation(profile!.lat!, profile.lng!)
            : null);
    final distance = (loc != null && listing.lat != null)
        ? haversineKm(loc.lat, loc.lng, listing.lat!, listing.lng!)
        : null;
    final gallery = <String>[];
    if (item?.cutoutPhotoUrl != null) gallery.add(item!.cutoutPhotoUrl!);
    for (final u in item?.photoUrls ?? const <String>[]) {
      if (!gallery.contains(u)) gallery.add(u);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        ClipRRect(
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
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                item?.name ?? 'Used Item',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            PriceTag(
              listing.listingType == 'jual'
                  ? formatRupiah(listing.price)
                  : Labels.listingType(listing.listingType),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            Chip(label: Text(Labels.listingType(listing.listingType))),
            Chip(label: Text(Labels.category(item?.category))),
            if (item?.condition != null)
              Chip(label: Text(Labels.condition(item?.condition))),
          ],
        ),
        if (item?.description != null && item!.description!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(item.description!),
        ],
        if (listing.note != null && listing.note!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(listing.note!, style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundImage: owner?.avatarUrl != null
                ? NetworkImage(owner!.avatarUrl!)
                : null,
            child: owner?.avatarUrl == null
                ? Text(
                    owner?.displayName.isNotEmpty == true
                        ? owner!.displayName[0].toUpperCase()
                        : '?',
                  )
                : null,
          ),
          title: Text(owner?.displayName ?? 'Owner'),
          subtitle: Text(
            [
              if (owner?.city != null) owner!.city!,
              if (distance != null) formatDistance(distance),
              if (listing.createdAt != null) timeAgo(listing.createdAt!),
            ].join(' • '),
          ),
        ),
        if (listing.lat != null && listing.lng != null) ...[
          const SizedBox(height: 8),
          MiniMap(lat: listing.lat!, lng: listing.lng!),
        ],
        const SizedBox(height: 20),
        if (isMine) ...[
          AppButton(
            label: 'Edit Listing',
            icon: Icons.edit_outlined,
            onPressed: () => context.push('/publish/${listing.itemId}'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () async {
              await ref
                  .read(communityRepositoryProvider)
                  .closeListing(listing.id, listing.itemId);
              ref.invalidate(communityListingsProvider);
              if (context.mounted) context.go('/community');
            },
            icon: const Icon(Icons.visibility_off_outlined, size: 18),
            label: const Text('Close Listing'),
          ),
        ] else if (contact == null) ...[
          const Text('The owner has not added contact info.'),
        ] else ...[
          AppButton(
            label: 'Chat on WhatsApp',
            icon: Icons.chat,
            onPressed: () {
              final text = Uri.encodeComponent(
                'Hi, I am interested in "${item?.name ?? 'your item'}" on RecyGo.',
              );
              _launch(Uri.parse('https://wa.me/$contact?text=$text'), context);
            },
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _launch(Uri.parse('tel:$contact'), context),
            icon: const Icon(Icons.call_outlined, size: 18),
            label: const Text('Call'),
          ),
        ],
      ],
    );
  }
}
