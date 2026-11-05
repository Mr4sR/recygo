import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recygo/features/fuse/presentation/fuse_select_page.dart';
import 'package:recygo/features/fuse/data/fuse_repository.dart';
import 'package:recygo/features/inventory/data/item_repository.dart';
import 'package:recygo/features/inventory/presentation/item_form_page.dart';
import 'package:recygo/features/segment/data/bulk_draft.dart';
import 'package:recygo/features/segment/presentation/segment_review_page.dart';

BulkDraft _draft({
  required String id,
  required String prompt,
  required String category,
  bool selected = true,
}) {
  return BulkDraft(
    localId: id,
    prompt: prompt,
    label: prompt,
    categoryGuess: category,
    confidence: 0.9,
    x: 0,
    y: 0,
    w: 0.2,
    h: 0.2,
    maskUrl: '',
    selected: selected,
    name: prompt,
    category: category,
    quantity: 1,
  );
}

void main() {
  testWidgets('item form cannot submit without a photo', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ItemFormPage())),
    );
    await tester.pump();
    expect(
      find.text('Photo is required — an item without a photo cannot be saved.'),
      findsOneWidget,
    );
    await tester.dragUntilVisible(
      find.text('Save Item'),
      find.byType(ListView).first,
      const Offset(0, -200),
    );
    await tester.pump();
    final saveButtons = find.widgetWithText(FilledButton, 'Save Item');
    expect(saveButtons, findsOneWidget);
    expect(tester.widget<FilledButton>(saveButtons).onPressed, isNull);
  });

  testWidgets('fuse button is disabled with fewer than two items selected', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myItemsProvider.overrideWith((ref) async => []),
          myRecipesProvider.overrideWith((ref) async => []),
        ],
        child: const MaterialApp(home: FuseSelectPage()),
      ),
    );
    await tester.pump();
    final fuseButton = find.widgetWithText(
      FilledButton,
      'Fuse with AI (pick at least 2)',
    );
    expect(fuseButton, findsOneWidget);
    expect(tester.widget<FilledButton>(fuseButton).onPressed, isNull);
  });

  testWidgets('bulk review: Save All and merging are disabled', (tester) async {
    final container = ProviderContainer();
    container
        .read(bulkDraftProvider.notifier)
        .setState(
          BulkDraftState(
            batchId: 'b1',
            sourcePhotoUrl: '',
            sourceBytes: Uint8List(0),
            drafts: [
              _draft(
                id: '1',
                prompt: 'plastic bottle',
                category: 'plastik',
                selected: false,
              ),
              _draft(id: '2', prompt: 'tin can', category: 'logam'),
              _draft(id: '3', prompt: 'glass bottle', category: 'kaca'),
            ],
          ),
        );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SegmentReviewPage()),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Save All (2'), findsOneWidget);
    final mergeButton = find.widgetWithText(OutlinedButton, 'Merge Selected');
    expect(mergeButton, findsOneWidget);
    expect(tester.widget<OutlinedButton>(mergeButton).onPressed, isNull);
    expect(find.text('Only similar items can be merged.'), findsOneWidget);

    container.read(bulkDraftProvider.notifier).selectAll(false);
    await tester.pump();
    expect(find.textContaining('Save All (0'), findsOneWidget);
    expect(
      tester
          .widgetList<FilledButton>(find.byType(FilledButton))
          .where((button) => button.onPressed != null),
      isEmpty,
    );
  });

  test(
    'bulk merge: blocked for different prompt AND category, allowed for same category',
    () {
      final container = ProviderContainer();
      final controller = container.read(bulkDraftProvider.notifier);
      controller.setState(
        BulkDraftState(
          batchId: 'b1',
          sourcePhotoUrl: '',
          sourceBytes: Uint8List(0),
          drafts: [
            _draft(id: '1', prompt: 'plastic bottle', category: 'plastik'),
            _draft(id: '2', prompt: 'tin can', category: 'logam'),
          ],
        ),
      );
      expect(controller.canMerge, isFalse);
      controller.setState(
        BulkDraftState(
          batchId: 'b1',
          sourcePhotoUrl: '',
          sourceBytes: Uint8List(0),
          drafts: [
            _draft(id: '1', prompt: 'plastic bottle', category: 'plastik'),
            _draft(id: '2', prompt: 'plastic cup', category: 'plastik'),
          ],
        ),
      );
      expect(controller.canMerge, isTrue);
      final merged = controller.mergeSelected();
      expect(merged!.drafts.length, 1);
      expect(merged.drafts.first.quantity, 2);
    },
  );
}
