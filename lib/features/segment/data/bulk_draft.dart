import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ephemeral description/condition/brand/material applied via "Enrich with AI".
class ItemEnrichment {
  final String? description;
  final String? condition;
  final String? brand;
  final String? material;
  const ItemEnrichment({
    this.description,
    this.condition,
    this.brand,
    this.material,
  });
}

class BulkDraft {
  final String localId;
  final String prompt;
  final String label;
  final String categoryGuess;
  final double confidence;
  final double x, y, w, h;
  final String maskUrl;
  final Uint8List? cutoutBytes;
  final bool cutoutOk;
  final bool selected;
  final String name;
  final String category;
  final List<String> tags;
  final int quantity;
  final ItemEnrichment? enrichment;

  const BulkDraft({
    required this.localId,
    required this.prompt,
    required this.label,
    required this.categoryGuess,
    required this.confidence,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.maskUrl,
    this.cutoutBytes,
    this.cutoutOk = false,
    required this.selected,
    required this.name,
    required this.category,
    this.tags = const [],
    this.quantity = 1,
    this.enrichment,
  });

  BulkDraft copyWith({
    Uint8List? cutoutBytes,
    bool? cutoutOk,
    bool? selected,
    String? name,
    String? category,
    List<String>? tags,
    int? quantity,
    ItemEnrichment? enrichment,
  }) => BulkDraft(
    localId: localId,
    prompt: prompt,
    label: label,
    categoryGuess: categoryGuess,
    confidence: confidence,
    x: x,
    y: y,
    w: w,
    h: h,
    maskUrl: maskUrl,
    cutoutBytes: cutoutBytes ?? this.cutoutBytes,
    cutoutOk: cutoutOk ?? this.cutoutOk,
    selected: selected ?? this.selected,
    name: name ?? this.name,
    category: category ?? this.category,
    tags: tags ?? this.tags,
    quantity: quantity ?? this.quantity,
    enrichment: enrichment ?? this.enrichment,
  );
}

class BulkDraftState {
  final String batchId;
  final String sourcePhotoUrl;
  final Uint8List sourceBytes;
  final List<BulkDraft> drafts;
  final bool usedFallbackPrompts;

  const BulkDraftState({
    required this.batchId,
    required this.sourcePhotoUrl,
    required this.sourceBytes,
    required this.drafts,
    this.usedFallbackPrompts = false,
  });

  int get selectedCount => drafts.where((d) => d.selected).length;

  BulkDraftState copyWith({
    List<BulkDraft>? drafts,
    bool? usedFallbackPrompts,
  }) => BulkDraftState(
    batchId: batchId,
    sourcePhotoUrl: sourcePhotoUrl,
    sourceBytes: sourceBytes,
    drafts: drafts ?? this.drafts,
    usedFallbackPrompts: usedFallbackPrompts ?? this.usedFallbackPrompts,
  );
}

class BulkDraftController extends Notifier<BulkDraftState?> {
  @override
  BulkDraftState? build() => null;

  void setState(BulkDraftState s) => state = s;
  void clear() => state = null;

  void updateDraft(String localId, BulkDraft Function(BulkDraft) fn) {
    final s = state;
    if (s == null) return;
    state = s.copyWith(
      drafts: s.drafts.map((d) => d.localId == localId ? fn(d) : d).toList(),
    );
  }

  void removeDraft(String localId) {
    final s = state;
    if (s == null) return;
    state = s.copyWith(
      drafts: s.drafts.where((d) => d.localId != localId).toList(),
    );
  }

  void selectAll(bool value) {
    final s = state;
    if (s == null) return;
    state = s.copyWith(
      drafts: s.drafts.map((d) => d.copyWith(selected: value)).toList(),
    );
  }

  /// Merge selected drafts (same prompt OR same category) into one.
  /// Returns null when merging is not allowed.
  BulkDraftState? mergeSelected() {
    final s = state;
    if (s == null) return null;
    final sel = s.drafts.where((d) => d.selected).toList();
    if (sel.length < 2) return null;
    final samePrompt = sel.every((d) => d.prompt == sel.first.prompt);
    final sameCategory = sel.every((d) => d.category == sel.first.category);
    if (!samePrompt && !sameCategory) return null;
    final totalQty = sel.fold<int>(0, (sum, d) => sum + d.quantity);
    final merged = sel.first.copyWith(quantity: totalQty, selected: true);
    final remaining = s.drafts.where((d) => !d.selected).toList();
    return state = s.copyWith(drafts: [merged, ...remaining]);
  }

  bool get canMerge {
    final s = state;
    if (s == null) return false;
    final sel = s.drafts.where((d) => d.selected).toList();
    if (sel.length < 2) return false;
    final samePrompt = sel.every((d) => d.prompt == sel.first.prompt);
    final sameCategory = sel.every((d) => d.category == sel.first.category);
    return samePrompt || sameCategory;
  }
}

final bulkDraftProvider =
    NotifierProvider<BulkDraftController, BulkDraftState?>(
      BulkDraftController.new,
    );

/// Fallback prompts when ai-suggest-prompts returns empty/failed.
const List<String> fallbackPrompts = [
  'plastic bottle',
  'cardboard box',
  'tin can',
  'glass bottle',
  'cloth',
  'wooden plank',
  'electronic device',
];
