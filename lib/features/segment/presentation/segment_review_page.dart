import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/labels.dart';
import '../../../core/utils/sfx.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../ai/data/ai_repository.dart';
import '../../ai/presentation/ai_fill_sheet.dart';
import '../../auth/data/auth_repository.dart';
import '../../inventory/data/item.dart';
import '../../inventory/data/item_repository.dart';
import '../data/bulk_draft.dart';

class SegmentReviewPage extends ConsumerStatefulWidget {
  const SegmentReviewPage({super.key});
  @override
  ConsumerState<SegmentReviewPage> createState() => _SegmentReviewPageState();
}

class _SegmentReviewPageState extends ConsumerState<SegmentReviewPage> {
  String? _highlightId;
  bool _saving = false;
  String _progress = '';

  Future<void> _enrich(BulkDraft draft) async {
    final profile = ref.read(currentProfileProvider);
    final state = ref.read(bulkDraftProvider);
    if (profile == null || state == null) return;
    try {
      String cutoutUrl;
      if (draft.cutoutBytes != null) {
        cutoutUrl = await ref
            .read(itemRepositoryProvider)
            .uploadDraftPhoto(
              profile.id,
              state.batchId,
              'enrich-${draft.localId}.png',
              draft.cutoutBytes!,
              contentType: 'image/png',
            );
      } else {
        cutoutUrl = state.sourcePhotoUrl;
      }
      final urls = [
        if (cutoutUrl.isNotEmpty) cutoutUrl else state.sourcePhotoUrl,
      ];
      if (!mounted) return;
      final applied = await showAiFillSheet(
        context,
        title: 'Enrich with AI',
        future: ref.read(aiRepositoryProvider).analyzeItem(urls),
      );
      if (applied == null) return;
      ref
          .read(bulkDraftProvider.notifier)
          .updateDraft(
            draft.localId,
            (d) => d.copyWith(
              name: applied.name,
              category: applied.category,
              tags: applied.tags,
              enrichment: ItemEnrichment(
                description: applied.description,
                condition: applied.condition,
                brand: applied.brand,
                material: applied.material,
              ),
            ),
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _merge() async {
    final controller = ref.read(bulkDraftProvider.notifier);
    if (!controller.canMerge) return;
    final sel =
        ref.read(bulkDraftProvider)?.drafts.where((d) => d.selected).toList() ??
        [];
    final totalQty = sel.fold<int>(0, (s, d) => s + d.quantity);
    final nameCtrl = TextEditingController(
      text: sel.isNotEmpty ? sel.first.name : '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Merge Items'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Merge ${sel.length} items into one with total quantity $totalQty?',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Merged name'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Merge'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    controller.mergeSelected();
    if (nameCtrl.text.trim().isNotEmpty) {
      final state = ref.read(bulkDraftProvider);
      if (state != null && state.drafts.isNotEmpty) {
        ref
            .read(bulkDraftProvider.notifier)
            .updateDraft(
              state.drafts.first.localId,
              (d) => d.copyWith(name: nameCtrl.text.trim()),
            );
      }
    }
  }

  Future<void> _saveAll() async {
    final state = ref.read(bulkDraftProvider);
    final profile = ref.read(currentProfileProvider);
    if (state == null || profile == null) return;
    final selected = state.drafts.where((d) => d.selected).toList();
    if (selected.isEmpty) return;
    setState(() {
      _saving = true;
      _progress = '0/${selected.length}';
    });
    final itemRepo = ref.read(itemRepositoryProvider);
    int done = 0;
    final failed = <String>[];

    for (final draft in selected) {
      try {
        final itemId = const Uuid().v4();
        final isPng = draft.cutoutOk;
        final cutoutUrl = draft.cutoutBytes != null
            ? await itemRepo.uploadPhoto(
                profile.id,
                itemId,
                isPng ? 'cutout.png' : 'cover.jpg',
                draft.cutoutBytes!,
                contentType: isPng ? 'image/png' : 'image/jpeg',
              )
            : '';
        final originalUrl = await itemRepo.uploadPhoto(
          profile.id,
          itemId,
          'original.jpg',
          state.sourceBytes,
        );
        final cover = cutoutUrl.isNotEmpty ? cutoutUrl : originalUrl;
        if (cover.isEmpty) throw Exception('upload failed');
        final item = Item(
          id: itemId,
          ownerId: profile.id,
          name: draft.name.trim().isEmpty ? draft.label : draft.name.trim(),
          category: draft.category,
          tags: draft.tags,
          description: draft.enrichment?.description,
          condition: draft.enrichment?.condition,
          brand: draft.enrichment?.brand,
          material: draft.enrichment?.material,
          unit: 'satuan',
          quantity: draft.quantity < 1 ? 1 : draft.quantity,
          photoUrls: [
            cover,
            if (originalUrl.isNotEmpty && originalUrl != cover) originalUrl,
          ],
          originalPhotoUrl: originalUrl.isEmpty ? null : originalUrl,
          cutoutPhotoUrl: draft.cutoutOk && cutoutUrl.isNotEmpty
              ? cutoutUrl
              : null,
          segmentation: {
            'sourcePhotoUrl': state.sourcePhotoUrl,
            'prompt': draft.prompt,
            'promptLabel': draft.label,
            'confidence': draft.confidence,
            'bbox': {'x': draft.x, 'y': draft.y, 'w': draft.w, 'h': draft.h},
            'source': draft.cutoutOk ? 'sam31' : 'manual',
          },
          status: 'tersedia',
          isPublished: false,
        );
        await itemRepo.createItem(item);
        done++;
      } catch (_) {
        failed.add(draft.name);
      }
      if (mounted) setState(() => _progress = '$done/${selected.length}');
    }

    // Best-effort draft cleanup.
    await itemRepo.deleteDraftFolder(profile.id, state.batchId);
    ref.invalidate(myItemsProvider);
    if (!mounted) return;
    setState(() => _saving = false);

    if (failed.isEmpty) {
      Sfx.instance.success();
      ref.read(bulkDraftProvider.notifier).clear();
      context.go('/items');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$done item(s) added to your Collection.')),
      );
    } else {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Partially Saved'),
          content: Text(
            'Successfully saved $done of ${selected.length} items.\nFailed: ${failed.join(', ')}',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.go('/items');
              },
              child: const Text('View Collection'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Retry Failed'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bulkDraftProvider);
    if (state == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Bulk Review')),
        body: EmptyState(
          lottieAsset: 'assets/lottie/empty_box.json',
          title: 'No scan in progress',
          subtitle:
              'Start from "Scan & Separate Automatically" to separate many items from one photo.',
          ctaLabel: 'Add Item',
          onCta: () => context.go('/items/new'),
        ),
      );
    }
    final controller = ref.read(bulkDraftProvider.notifier);
    final selectedCount = state.selectedCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Separated Items'),
        actions: [
          TextButton(
            onPressed: () => controller.selectAll(true),
            child: const Text('Select All'),
          ),
          TextButton(
            onPressed: () => controller.selectAll(false),
            child: const Text('Clear'),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: controller.canMerge && !_saving ? _merge : null,
                  icon: const Icon(Icons.merge_type, size: 18),
                  label: const Text('Merge Selected'),
                ),
              ),
              if (!controller.canMerge &&
                  state.drafts.where((d) => d.selected).length >= 2)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Only similar items can be merged.',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ),
              const SizedBox(height: 8),
              AppButton(
                label: _saving
                    ? 'Saving $_progress…'
                    : 'Save All ($selectedCount items)',
                onPressed: selectedCount >= 1 && !_saving ? _saveAll : null,
                loading: _saving,
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          if (state.usedFallbackPrompts)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'The item list was generated with limited automation — please check each card.',
              ),
            ),
          Text('Source Photo', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (state.sourceBytes.isNotEmpty)
                    Image.memory(state.sourceBytes, fit: BoxFit.cover)
                  else
                    Container(color: AppColors.accentMint),
                  CustomPaint(
                    painter: _DraftBboxPainter(
                      state.drafts,
                      highlightedId: _highlightId,
                      onTapBox: (id) => setState(() => _highlightId = id),
                    ),
                  ),
                  for (final d in state.drafts)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () => setState(() => _highlightId = d.localId),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap a box to highlight its card below.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 240,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.62,
            ),
            itemCount: state.drafts.length,
            itemBuilder: (context, i) {
              final d = state.drafts[i];
              final highlighted = _highlightId == d.localId;
              return Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: highlighted
                        ? AppColors.primary
                        : Theme.of(context).dividerColor,
                    width: highlighted ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        AspectRatio(
                          aspectRatio: 4 / 3,
                          child: CutoutBackground(
                            child: d.cutoutBytes != null
                                ? Image.memory(
                                    d.cutoutBytes!,
                                    fit: BoxFit.contain,
                                  )
                                : state.sourceBytes.isNotEmpty
                                ? Image.memory(
                                    state.sourceBytes,
                                    fit: BoxFit.cover,
                                  )
                                : const Icon(
                                    Icons.image_outlined,
                                    color: AppColors.muted,
                                  ),
                          ),
                        ),
                        Positioned(
                          top: 4,
                          left: 4,
                          child: Chip(
                            label: Text(
                              '${(d.confidence * 100).round()}%',
                              style: const TextStyle(fontSize: 11),
                            ),
                            visualDensity: VisualDensity.compact,
                            backgroundColor: d.confidence >= 0.5
                                ? AppColors.primary.withValues(alpha: 0.85)
                                : AppColors.secondary.withValues(alpha: 0.9),
                            labelStyle: const TextStyle(color: Colors.white),
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Checkbox(
                            value: d.selected,
                            onChanged: (v) => controller.updateDraft(
                              d.localId,
                              (x) => x.copyWith(selected: v ?? false),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextFormField(
                              initialValue: d.name,
                              decoration: const InputDecoration(
                                labelText: 'Name',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) => controller.updateDraft(
                                d.localId,
                                (x) => x.copyWith(name: v),
                              ),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              initialValue:
                                  Labels.categories.containsKey(d.category)
                                  ? d.category
                                  : 'lainnya',
                              decoration: const InputDecoration(
                                labelText: 'Category',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                for (final e in Labels.categories.entries)
                                  DropdownMenuItem(
                                    value: e.key,
                                    child: Text(e.value),
                                  ),
                              ],
                              onChanged: (v) {
                                if (v == null) return;
                                controller.updateDraft(
                                  d.localId,
                                  (x) => x.copyWith(category: v),
                                );
                              },
                            ),
                            const SizedBox(height: 6),
                            if (d.confidence < 0.5)
                              const Chip(
                                label: Text(
                                  'Please check',
                                  style: TextStyle(fontSize: 11),
                                ),
                                backgroundColor: Color(0xFFFFE3A3),
                                visualDensity: VisualDensity.compact,
                              ),
                            if (!d.cutoutOk)
                              const Chip(
                                label: Text(
                                  'No cutout',
                                  style: TextStyle(fontSize: 11),
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                            const Spacer(),
                            Row(
                              children: [
                                IconButton(
                                  tooltip: 'Decrease quantity',
                                  onPressed: d.quantity > 1
                                      ? () => controller.updateDraft(
                                          d.localId,
                                          (x) => x.copyWith(
                                            quantity: x.quantity - 1,
                                          ),
                                        )
                                      : null,
                                  icon: const Icon(Icons.remove, size: 18),
                                ),
                                Text(
                                  '${d.quantity}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Increase quantity',
                                  onPressed: () => controller.updateDraft(
                                    d.localId,
                                    (x) => x.copyWith(quantity: x.quantity + 1),
                                  ),
                                  icon: const Icon(Icons.add, size: 18),
                                ),
                                const Spacer(),
                                IconButton(
                                  tooltip: 'Delete draft',
                                  onPressed: () =>
                                      controller.removeDraft(d.localId),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 19,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => _enrich(d),
                                icon: const Icon(Icons.auto_awesome, size: 15),
                                label: const Text(
                                  'Enrich with AI',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DraftBboxPainter extends CustomPainter {
  final List<BulkDraft> drafts;
  final String? highlightedId;
  final ValueChanged<String>? onTapBox;
  _DraftBboxPainter(this.drafts, {this.highlightedId, this.onTapBox});

  static const _colors = [
    AppColors.primary,
    AppColors.secondary,
    Color(0xFF7C5CFF),
    Color(0xFF0FA3A3),
    Color(0xFFE5484D),
    Color(0xFF2F80ED),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < drafts.length; i++) {
      final d = drafts[i];
      final rect = Rect.fromLTWH(
        d.x * size.width,
        d.y * size.height,
        d.w * size.width,
        d.h * size.height,
      );
      final isHi = highlightedId == d.localId;
      final paint = Paint()
        ..color = _colors[i % _colors.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = isHi ? 4 : 2.2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        paint,
      );
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelRect = Rect.fromLTWH(
        rect.left,
        rect.top,
        textPainter.width + 10,
        18,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(labelRect, const Radius.circular(4)),
        Paint()..color = _colors[i % _colors.length],
      );
      textPainter.paint(canvas, Offset(rect.left + 5, rect.top + 2));
    }
  }

  @override
  bool shouldRepaint(covariant _DraftBboxPainter old) =>
      old.drafts != drafts || old.highlightedId != highlightedId;
}

class Uint8ListHolder {
  final Uint8List bytes;
  Uint8ListHolder(this.bytes);
}
