import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:recygo/core/utils/format.dart';
import 'package:recygo/features/community/data/community_models.dart';
import 'package:recygo/features/fuse/data/fuse_recipe.dart';
import 'package:recygo/features/inventory/data/item.dart';
import 'package:recygo/features/segment/data/segmentation_service.dart';

Uint8List _png(img.Image image) => Uint8List.fromList(img.encodePng(image));

void main() {
  test('formatRupiah formats and handles null', () {
    expect(formatRupiah(25000), contains('25,000'));
    expect(formatRupiah(null), 'Free');
  });

  test('haversineKm: Jakarta to Jakarta is 0, known distance is sane', () {
    expect(haversineKm(-6.2, 106.816, -6.2, 106.816), closeTo(0, 0.001));
    // Jakarta (-6.2,106.816) to Bandung (-6.917,107.619) ~ 118 km straight-line.
    expect(
      haversineKm(-6.2, 106.816, -6.917, 107.619),
      inInclusiveRange(100, 140),
    );
  });

  test('AiItemSuggestion validates enums and clamps confidence', () {
    final s = AiItemSuggestion.fromJson({
      'name': '  Botol  ',
      'category': 'not_a_category',
      'condition': 'weird',
      'unitGuess': 'bad',
      'quantityGuess': 0,
      'confidence': 1.7,
      'tags': [' BOTOL ', '', 'Plastik'],
    });
    expect(s.name, 'Botol');
    expect(s.category, 'lainnya');
    expect(s.condition, isNull);
    expect(s.unitGuess, 'satuan');
    expect(s.quantityGuess, 1);
    expect(s.confidence, 1.0);
    expect(s.tags, ['botol', 'plastik']);
  });

  test('AiItemSuggestion falls back safely for malformed JSON values', () {
    final s = AiItemSuggestion.fromJson({
      'name': 42,
      'category': null,
      'tags': 'not-a-list',
      'description': '   ',
      'condition': 7,
      'brand': false,
      'material': '',
      'unitGuess': null,
      'quantityGuess': 'three',
      'confidence': 'high',
    });
    expect(s.name, 'Used Item');
    expect(s.category, 'lainnya');
    expect(s.tags, isEmpty);
    expect(s.description, isNull);
    expect(s.condition, isNull);
    expect(s.brand, isNull);
    expect(s.material, isNull);
    expect(s.unitGuess, 'satuan');
    expect(s.quantityGuess, 1);
    expect(s.confidence, 0.0);
  });

  test('Item.fromJson parses row and cover prefers cutout', () {
    final item = Item.fromJson({
      'id': '1',
      'owner_id': 'u1',
      'name': 'Bottle',
      'category': 'plastik',
      'tags': ['pet'],
      'photo_urls': ['https://x/cover.jpg'],
      'cutout_photo_url': 'https://x/cutout.png',
      'segmentation': {'source': 'sam31'},
    });
    expect(item.coverUrl, 'https://x/cutout.png');
    expect(item.isSegmented, isTrue);
  });

  test(
    'applyMaskToAlpha: mask >=128 becomes opaque, else transparent (4x4)',
    () {
      final rgb = img.Image(width: 4, height: 4, numChannels: 3);
      final mask = img.Image(width: 4, height: 4, numChannels: 3);
      for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
          rgb.setPixelRgb(x, y, 255, 0, 0);
          final v = (x + y * 4) % 2 == 0 ? 255 : 0; // checkerboard
          mask.setPixelRgb(x, y, v, v, v);
        }
      }
      final out = img.decodeImage(applyMaskToAlpha(_png(rgb), _png(mask)))!;
      for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
          final expectedAlpha = (x + y * 4) % 2 == 0 ? 255 : 0;
          expect(
            out.getPixel(x, y).a.toInt(),
            expectedAlpha,
            reason: 'pixel $x,$y',
          );
        }
      }
    },
  );

  test('backend listing row (FK-hint embed) parses owner + item', () {
    final listing = CommunityListing.fromJson({
      'id': 'l1',
      'item_id': 'i1',
      'owner_id': 'u1',
      'listing_type': 'jual',
      'price': 25000,
      'note': null,
      'lat': -6.2,
      'lng': 106.8,
      'is_active': true,
      'created_at': '2026-01-01T00:00:00Z',
      'items': {
        'id': 'i1',
        'owner_id': 'u1',
        'name': 'Glass Jars',
        'category': 'kaca',
        'photo_urls': [
          'https://api.example.com/v1/media/file/u1/items/x/a.jpg',
        ],
      },
      'profiles': {
        'id': 'u1',
        'display_name': 'Sari',
        'whatsapp': '6281200000000',
      },
    });
    expect(listing.owner?.displayName, 'Sari');
    expect(listing.owner?.contactNumber, '6281200000000');
    expect(listing.item?.name, 'Glass Jars');
    expect(listing.item?.coverUrl, contains('/v1/media/file/'));
    expect(listing.price, 25000);
  });

  test('backend fuse recipe row parses used/missing items', () {
    final recipe = FuseRecipe.fromJson({
      'id': 'r1',
      'owner_id': 'u1',
      'title': 'Planter',
      'description': 'Desc',
      'steps': ['Cut', 'Plant'],
      'difficulty': 'mudah',
      'estimated_minutes': 30,
      'image_url': 'https://api.example.com/v1/media/file/u1/fuse/r1.png',
      'source_item_ids': ['i1'],
      'used_items': [
        {'itemId': 'i1', 'name': 'Bottle', 'role': 'Body'},
      ],
      'missing_items': [
        {'name': 'Seeds', 'category': 'organik', 'suggestion': 'Buy'},
      ],
      'created_at': '2026-01-01T00:00:00Z',
    });
    expect(recipe.usedItems.single.role, 'Body');
    expect(recipe.missingItems.single.category, 'organik');
    expect(recipe.imageUrl, contains('/v1/media/file/'));
  });
}
