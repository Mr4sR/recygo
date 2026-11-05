import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/labels.dart';
import '../../../core/utils/providers.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../auth/data/auth_repository.dart';
import '../../community/data/community_models.dart';
import '../data/wastebank_repository.dart';

class WasteBankListPage extends ConsumerWidget {
  const WasteBankListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(wasteBanksProvider);
    final profile = ref.watch(currentProfileProvider);
    final deviceLoc = ref.watch(deviceLocationProvider).value;
    final loc =
        deviceLoc ??
        (profile?.lat != null
            ? UserLocation(profile!.lat!, profile.lng!)
            : null);

    return Scaffold(
      appBar: AppBar(title: const Text('Waste Banks')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (banks) {
          final sorted = [...banks]
            ..sort((a, b) {
              if (loc == null) return a.name.compareTo(b.name);
              final da = haversineKm(loc.lat, loc.lng, a.lat, a.lng);
              final db = haversineKm(loc.lat, loc.lng, b.lat, b.lng);
              return da.compareTo(db);
            });
          if (sorted.isEmpty) {
            return const EmptyState(
              lottieAsset: 'assets/lottie/empty_box.json',
              title: 'No waste banks yet',
              subtitle: 'Waste bank data is managed by admins.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(wasteBanksProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: sorted.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final b = sorted[i];
                final d = loc != null
                    ? haversineKm(loc.lat, loc.lng, b.lat, b.lng)
                    : null;
                return _BankCard(bank: b, distanceKm: d);
              },
            ),
          );
        },
      ),
    );
  }
}

class _BankCard extends StatelessWidget {
  final WasteBank bank;
  final double? distanceKm;
  const _BankCard({required this.bank, this.distanceKm});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.push('/waste-banks/${bank.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: AppColors.accentMint,
                    child: Icon(
                      Icons.account_balance,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      bank.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (bank.isVerified)
                    const Icon(
                      Icons.verified,
                      color: AppColors.primary,
                      size: 18,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(bank.address, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (distanceKm != null)
                    _meta(Icons.near_me_outlined, formatDistance(distanceKm)),
                  if (bank.openingHours != null)
                    _meta(Icons.schedule, bank.openingHours!),
                  if (bank.city != null)
                    _meta(Icons.location_city_outlined, bank.city!),
                ],
              ),
              if (bank.acceptedCategories.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final c in bank.acceptedCategories)
                      Chip(
                        label: Text(Labels.category(c)),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
              if (bank.priceInfo != null) ...[
                const SizedBox(height: 8),
                PriceTag(bank.priceInfo!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: AppColors.muted),
      const SizedBox(width: 4),
      Text(text, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
    ],
  );
}

/// Small map with a single marker (used by waste-bank & listing detail).
class MiniMap extends StatelessWidget {
  final double lat;
  final double lng;
  final Color markerColor;
  const MiniMap({
    super.key,
    required this.lat,
    required this.lng,
    this.markerColor = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 200,
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: LatLng(lat, lng),
                initialZoom: 14,
                interactionOptions: const InteractionOptions(
                  flags:
                      InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'id.recygo.recygo',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(lat, lng),
                      width: 38,
                      height: 38,
                      child: Icon(
                        Icons.location_on,
                        color: markerColor,
                        size: 34,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Positioned(
              left: 8,
              bottom: 6,
              child: Text(
                '© OpenStreetMap contributors',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WasteBankDetailPage extends ConsumerWidget {
  final String bankId;
  const WasteBankDetailPage({super.key, required this.bankId});

  Future<void> _launch(Uri uri, BuildContext context) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
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
    final async = ref.watch(wasteBankDetailProvider(bankId));
    return Scaffold(
      appBar: AppBar(title: const Text('Waste Bank Detail')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (bank) {
          if (bank == null) {
            return const Center(child: Text('Waste bank not found.'));
          }
          final contact = bank.contactNumber;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      bank.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  if (bank.isVerified)
                    const Icon(Icons.verified, color: AppColors.primary),
                ],
              ),
              const SizedBox(height: 10),
              _row(Icons.location_on_outlined, 'Address', bank.address),
              if (bank.description != null)
                _row(Icons.info_outline, 'About', bank.description!),
              if (bank.openingHours != null)
                _row(Icons.schedule, 'Opening Hours', bank.openingHours!),
              if (bank.priceInfo != null)
                _row(Icons.sell_outlined, 'Indicative Prices', bank.priceInfo!),
              if (bank.acceptedCategories.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Accepted Categories',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final c in bank.acceptedCategories)
                      Chip(label: Text(Labels.category(c))),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              MiniMap(lat: bank.lat, lng: bank.lng),
              const SizedBox(height: 20),
              if (contact != null) ...[
                AppButton(
                  label: 'Chat on WhatsApp',
                  icon: Icons.chat,
                  onPressed: () => _launch(
                    Uri.parse(
                      'https://wa.me/$contact?text=${Uri.encodeComponent('Hi, I would like to ask about selling used items at ${bank.name} (RecyGo).')}',
                    ),
                    context,
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => _launch(Uri.parse('tel:$contact'), context),
                  icon: const Icon(Icons.call_outlined, size: 18),
                  label: const Text('Call'),
                ),
                const SizedBox(height: 10),
              ],
              AppButton(
                label: 'Directions',
                icon: Icons.directions,
                ghost: contact == null,
                onPressed: () => _launch(
                  Uri.parse(
                    'https://www.openstreetmap.org/directions?to=${bank.lat},${bank.lng}',
                  ),
                  context,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                Text(value),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
