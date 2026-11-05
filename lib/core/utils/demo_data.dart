import '../../features/inventory/data/item.dart';
import 'labels.dart';

/// Static fixtures used when DEMO_MODE=true (no Supabase credentials needed).
class DemoData {
  static const String demoUserId = 'demo-user';

  static Profile demoProfile() => const Profile(
    id: demoUserId,
    displayName: 'Demo User',
    phone: '6281200000000',
    whatsapp: '6281200000000',
    city: 'South Jakarta',
    lat: -6.2383,
    lng: 106.8527,
  );

  static List<Item> demoItems() => [
    Item(
      id: 'demo-item-1',
      ownerId: demoUserId,
      name: 'Plastic Bottles (10 pcs)',
      category: 'plastik',
      tags: const ['bottle', 'pet', 'plastic'],
      description: 'Clean PET bottles, labels removed.',
      condition: 'baik',
      brand: null,
      material: 'PET plastic',
      unit: 'paket',
      quantity: 10,
      photoUrls: const [],
      status: 'tersedia',
      isPublished: true,
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
    Item(
      id: 'demo-item-2',
      ownerId: demoUserId,
      name: 'Cardboard Box',
      category: 'kertas_kardus',
      tags: const ['cardboard', 'box'],
      description: 'Sturdy double-wall cardboard box.',
      condition: 'cukup',
      material: 'Cardboard',
      unit: 'satuan',
      quantity: 3,
      photoUrls: const [],
      status: 'tersedia',
      isPublished: false,
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
    Item(
      id: 'demo-item-3',
      ownerId: demoUserId,
      name: 'Fabric Scraps',
      category: 'kain_tekstil',
      tags: const ['fabric', 'cotton'],
      description: 'Mixed cotton fabric scraps for crafts.',
      condition: 'baik',
      material: 'Cotton',
      unit: 'karung',
      quantity: 1,
      photoUrls: const [],
      status: 'tersedia',
      isPublished: false,
      createdAt: DateTime.now(),
    ),
  ];
}
