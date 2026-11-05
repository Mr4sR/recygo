import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../auth/data/auth_repository.dart';
import '../../inventory/data/item.dart';
import '../../inventory/data/item_repository.dart';
import '../data/community_repository.dart';

class PublishPage extends ConsumerStatefulWidget {
  final String itemId;
  const PublishPage({super.key, required this.itemId});
  @override
  ConsumerState<PublishPage> createState() => _PublishPageState();
}

class _PublishPageState extends ConsumerState<PublishPage> {
  String _type = 'gratis';
  final _price = TextEditingController();
  final _note = TextEditingController();
  bool _saving = false;
  bool _closing = false;
  bool _inited = false;

  @override
  void dispose() {
    _price.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save(Item item, String? existingListingId) async {
    final profile = ref.read(currentProfileProvider);
    if (profile == null) return;
    if (_type == 'jual') {
      final p = double.tryParse(_price.text.replaceAll(RegExp(r'[^0-9]'), ''));
      if (p == null || p < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid price for "For Sale".')),
        );
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final repo = ref.read(communityRepositoryProvider);
      final price = _type == 'jual'
          ? double.tryParse(_price.text.replaceAll(RegExp(r'[^0-9]'), ''))
          : null;
      if (existingListingId != null) {
        await repo.updateListing(
          listingId: existingListingId,
          listingType: _type,
          price: price,
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          lat: profile.lat,
          lng: profile.lng,
        );
      } else {
        await repo.publish(
          itemId: item.id,
          ownerId: profile.id,
          listingType: _type,
          price: price,
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          lat: profile.lat,
          lng: profile.lng,
        );
      }
      ref.invalidate(communityListingsProvider);
      ref.invalidate(activeListingForItemProvider(item.id));
      ref.invalidate(itemDetailProvider(item.id));
      ref.invalidate(myItemsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Published to Community.')));
      context.go('/community');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to publish: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _closeListing(String listingId, String itemId) async {
    setState(() => _closing = true);
    try {
      await ref
          .read(communityRepositoryProvider)
          .closeListing(listingId, itemId);
      ref.invalidate(communityListingsProvider);
      ref.invalidate(activeListingForItemProvider(itemId));
      ref.invalidate(itemDetailProvider(itemId));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Listing closed.')));
      context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to close listing: $e')));
      }
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemAsync = ref.watch(itemDetailProvider(widget.itemId));
    final listingAsync = ref.watch(activeListingForItemProvider(widget.itemId));
    final profile = ref.watch(currentProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Publish to Community')),
      body: itemAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (item) {
          if (item == null) return const Center(child: Text('Item not found.'));
          final existing = listingAsync.value;
          if (existing != null && !_inited) {
            _inited = true;
            _type = existing.listingType;
            if (existing.price != null) {
              _price.text = existing.price!.toInt().toString();
            }
            _note.text = existing.note ?? '';
          }
          final needsLocation = profile != null && profile.lat == null;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              ItemCard(
                name: item.name,
                categoryLabel: item.category,
                cutoutUrl: item.cutoutPhotoUrl,
                photoUrls: item.photoUrls,
              ),
              const SizedBox(height: 18),
              if (existing != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6F7EE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'This item already has an active listing. You are editing it.',
                  ),
                ),
              Text(
                'Listing Type',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'jual',
                    label: Text('For Sale'),
                    icon: Icon(Icons.sell_outlined),
                  ),
                  ButtonSegment(
                    value: 'gratis',
                    label: Text('Free'),
                    icon: Icon(Icons.volunteer_activism_outlined),
                  ),
                  ButtonSegment(
                    value: 'ajak_fuse',
                    label: Text('Fuse Together'),
                    icon: Icon(Icons.auto_awesome),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              if (_type == 'jual') ...[
                const SizedBox(height: 16),
                AppTextField(
                  controller: _price,
                  label: 'Price (Rp) *',
                  keyboardType: TextInputType.number,
                  hint: 'e.g. 25000',
                ),
                if (_price.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      formatRupiah(
                        double.tryParse(
                          _price.text.replaceAll(RegExp(r'[^0-9]'), ''),
                        ),
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              AppTextField(
                controller: _note,
                label: 'Note (optional)',
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.location_on_outlined),
                title: Text(profile?.city ?? 'Location not set'),
                subtitle: Text(
                  profile?.lat != null
                      ? '${profile!.lat!.toStringAsFixed(4)}, ${profile.lng!.toStringAsFixed(4)}'
                      : 'Add your location in Edit Profile so buyers can see distance.',
                ),
              ),
              if (needsLocation)
                OutlinedButton.icon(
                  onPressed: () => context.push('/profile/edit'),
                  icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
                  label: const Text('Set Location in Profile'),
                ),
              const SizedBox(height: 20),
              AppButton(
                label: existing != null ? 'Save Listing' : 'Publish',
                onPressed: _saving ? null : () => _save(item, existing?.id),
                loading: _saving,
              ),
              if (existing != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _closing
                      ? null
                      : () => _closeListing(existing.id, item.id),
                  icon: const Icon(Icons.visibility_off_outlined, size: 18),
                  label: const Text('Close Listing'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
