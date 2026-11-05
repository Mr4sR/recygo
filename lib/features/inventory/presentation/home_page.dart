import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/format.dart';
import '../../../core/utils/labels.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../auth/data/auth_repository.dart';
import '../data/item_repository.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);
    final itemsAsync = ref.watch(myItemsProvider);
    final disableAnim = MediaQuery.of(context).disableAnimations;

    return Scaffold(
      appBar: AppBar(
        title: const Text('RecyGo'),
        actions: [
          IconButton(
            tooltip: 'Profile',
            onPressed: () => context.push('/profile'),
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myItemsProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(
              'Hi, ${profile?.displayName ?? 'there'} 👋',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'What used items will you rescue today?',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 18),
            Card(
                  color: const Color(0xFF0E6B45),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.auto_awesome, color: Colors.white),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Scan & Separate Automatically',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            AiBadge(),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'One crowded photo becomes many catalog-ready items with transparent cutouts.',
                          style: TextStyle(
                            color: Color(0xFFCFEEDF),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF0E6B45),
                          ),
                          onPressed: () => context.push('/items/new?scan=1'),
                          icon: const Icon(Icons.document_scanner_outlined),
                          label: const Text('Scan Many Items'),
                        ),
                      ],
                    ),
                  ),
                )
                .animate(target: disableAnim ? 0 : 1)
                .fadeIn(duration: 220.ms)
                .slideY(begin: 0.06),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _QuickCard(
                    icon: Icons.add_a_photo_outlined,
                    label: 'Add Item',
                    onTap: () => context.push('/items/new'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _QuickCard(
                    icon: Icons.auto_awesome,
                    label: 'Fuse Items',
                    onTap: () => context.go('/fuse'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _QuickCard(
                    icon: Icons.account_balance_outlined,
                    label: 'Waste Banks',
                    onTap: () => context.push('/waste-banks'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Recent Items',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed: () => context.go('/items'),
                  child: const Text('See All'),
                ),
              ],
            ),
            itemsAsync.when(
              loading: () => const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text('Failed to load items: $e'),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No items yet. Add your first used item!'),
                  );
                }
                final recent = items.take(6).toList();
                return SizedBox(
                  height: 238,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: recent.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, i) {
                      final item = recent[i];
                      return SizedBox(
                            width: 170,
                            child: ItemCard(
                              name: item.name,
                              categoryLabel: Labels.category(item.category),
                              conditionLabel: item.condition != null
                                  ? Labels.condition(item.condition)
                                  : null,
                              cutoutUrl: item.cutoutPhotoUrl,
                              photoUrls: item.photoUrls,
                              badgeText: item.isSegmented ? 'AI Cutout' : null,
                              onTap: () => context.push('/items/${item.id}'),
                            ),
                          )
                          .animate(target: disableAnim ? 0 : 1)
                          .fadeIn(duration: 220.ms, delay: (i * 40).ms)
                          .slideY(begin: 0.08);
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Tip: publish items to Community so others can buy, take them for free, or Fuse with you. Find owners near you and chat via WhatsApp.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (profile?.lat != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Your location: ${profile!.city ?? ''} (${formatDistance(0) == '' ? '' : ''}${profile.lat!.toStringAsFixed(3)}, ${profile.lng!.toStringAsFixed(3)})',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _QuickCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, color: const Color(0xFF1B9E6B), size: 26),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
