import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/config/env.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../community/data/community_models.dart';

class WasteBankRepository {
  Future<List<WasteBank>> fetchWasteBanks() async {
    if (Env.useBackend) {
      final data = await apiClient.getJson('/v1/waste-banks');
      return asJsonList(
        data,
      ).whereType<Map>().map((r) => WasteBank.fromJson(asJsonMap(r))).toList();
    }
    if (Env.demoMode) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return DemoWasteBanks.all();
    }
    final rows = await supabase
        .from('waste_banks')
        .select()
        .order('name')
        .limit(200);
    return (rows as List)
        .map((r) => WasteBank.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<WasteBank?> fetchWasteBank(String id) async {
    if (Env.useBackend) {
      try {
        final data = await apiClient.getJson('/v1/waste-banks/$id');
        return WasteBank.fromJson(asJsonMap(data));
      } on ApiException catch (e) {
        if (e.status == 404) return null;
        rethrow;
      }
    }
    if (Env.demoMode) {
      for (final b in DemoWasteBanks.all()) {
        if (b.id == id) return b;
      }
      return null;
    }
    final rows = await supabase
        .from('waste_banks')
        .select()
        .eq('id', id)
        .limit(1);
    final list = rows as List;
    if (list.isEmpty) return null;
    return WasteBank.fromJson(list.first as Map<String, dynamic>);
  }
}

class DemoWasteBanks {
  static List<WasteBank> all() => const [
    WasteBank(
      id: 'wb-1',
      name: 'Melati Bersih Waste Bank',
      description:
          'Main neighborhood waste bank with pickup for priority members.',
      address: 'Jl. Melati No. 12, Tebet',
      city: 'South Jakarta',
      lat: -6.2383,
      lng: 106.8527,
      phone: '6281200001001',
      whatsapp: '6281200001001',
      openingHours: 'Mon–Sat 08:00–16:00',
      acceptedCategories: ['plastik', 'kertas_kardus', 'logam', 'kaca'],
      priceInfo: 'Plastic Rp1,500/kg, Cardboard Rp1,200/kg, Cans Rp8,000/kg',
    ),
    WasteBank(
      id: 'wb-2',
      name: 'Dahlia Lestari Waste Bank',
      description: 'Accepts sorted waste from households and offices.',
      address: 'Jl. Dahlia Raya No. 4, Pancoran',
      city: 'South Jakarta',
      lat: -6.2505,
      lng: 106.8460,
      phone: '6281200001002',
      whatsapp: '6281200001002',
      openingHours: 'Mon–Fri 08:00–15:00',
      acceptedCategories: ['plastik', 'kertas_kardus', 'elektronik'],
      priceInfo: 'Plastic Rp1,400/kg, HVS Paper Rp2,000/kg',
    ),
    WasteBank(
      id: 'wb-3',
      name: 'Kenanga Hijau Waste Bank',
      description: 'Waste savings program for residents and schools.',
      address: 'Jl. Kenanga No. 21, Cikini',
      city: 'Central Jakarta',
      lat: -6.1905,
      lng: 106.8380,
      phone: '6281200001003',
      whatsapp: '6281200001003',
      openingHours: 'Mon–Sat 07:30–15:30',
      acceptedCategories: ['plastik', 'kertas_kardus', 'kaca', 'logam'],
      priceInfo: 'Glass bottles Rp500/pc, Plastic Rp1,500/kg',
    ),
    WasteBank(
      id: 'wb-4',
      name: 'Anggrek Mandiri Waste Bank',
      description: 'Recycling drop point near a traditional market.',
      address: 'Jl. Anggrek No. 8, Kemayoran',
      city: 'Central Jakarta',
      lat: -6.1680,
      lng: 106.8490,
      phone: '6281200001004',
      whatsapp: '6281200001004',
      openingHours: 'Daily 08:00–17:00',
      acceptedCategories: ['plastik', 'logam', 'kertas_kardus'],
      priceInfo: 'Iron Rp3,500/kg, Cardboard Rp1,100/kg',
    ),
    WasteBank(
      id: 'wb-5',
      name: 'Flamboyan Asri Waste Bank',
      description: 'Accepts used cooking oil and fabric scraps for processing.',
      address: 'Jl. Flamboyan No. 3, Jatinegara',
      city: 'East Jakarta',
      lat: -6.2210,
      lng: 106.8705,
      phone: '6281200001005',
      whatsapp: '6281200001005',
      openingHours: 'Mon–Sat 08:00–16:00',
      acceptedCategories: ['plastik', 'kain_tekstil', 'organik'],
      priceInfo: 'Fabric scraps Rp1,000/kg, Used cooking oil Rp4,000/liter',
    ),
    WasteBank(
      id: 'wb-6',
      name: 'Cempaka Putih Waste Bank',
      description: 'Digital waste bank with transparent weighing.',
      address: 'Jl. Cempaka Putih Raya No. 15',
      city: 'Central Jakarta',
      lat: -6.1765,
      lng: 106.8735,
      phone: '6281200001006',
      whatsapp: '6281200001006',
      openingHours: 'Mon–Fri 09:00–16:00',
      acceptedCategories: ['plastik', 'kertas_kardus', 'logam', 'elektronik'],
      priceInfo: 'Broken electronics Rp5,000/kg, Aluminum Rp12,000/kg',
    ),
    WasteBank(
      id: 'wb-7',
      name: 'Mawar Sejahtera Waste Bank',
      description: 'Focused on recycling plastic packaging and PET bottles.',
      address: 'Jl. Mawar No. 9, Kebayoran Baru',
      city: 'South Jakarta',
      lat: -6.2430,
      lng: 106.7990,
      phone: '6281200001007',
      whatsapp: '6281200001007',
      openingHours: 'Mon–Sat 08:00–15:00',
      acceptedCategories: ['plastik', 'kaca'],
      priceInfo: 'Clean PET bottles Rp2,000/kg',
    ),
    WasteBank(
      id: 'wb-8',
      name: 'Kamboja Recycle Waste Bank',
      description: 'Accepts used wood and pallets for upcycling.',
      address: 'Jl. Kamboja No. 17, Cengkareng',
      city: 'West Jakarta',
      lat: -6.1480,
      lng: 106.7250,
      phone: '6281200001008',
      whatsapp: '6281200001008',
      openingHours: 'Mon–Sat 08:00–16:30',
      acceptedCategories: ['kayu', 'logam', 'plastik'],
      priceInfo: 'Pallet wood Rp800/kg, Iron Rp3,200/kg',
    ),
    WasteBank(
      id: 'wb-9',
      name: 'Sakura Berseri Waste Bank',
      description: 'Waste sorting education program for school children.',
      address: 'Jl. Sakura No. 5, Kelapa Gading',
      city: 'North Jakarta',
      lat: -6.1655,
      lng: 106.9055,
      phone: '6281200001009',
      whatsapp: '6281200001009',
      openingHours: 'Mon–Fri 08:00–15:00',
      acceptedCategories: ['plastik', 'kertas_kardus', 'kaca'],
      priceInfo: 'Cardboard Rp1,300/kg, Plastic Rp1,500/kg',
    ),
    WasteBank(
      id: 'wb-10',
      name: 'Teratai Biru Waste Bank',
      description: 'Large drop point near a small industrial area.',
      address: 'Jl. Teratai No. 30, Cilincing',
      city: 'North Jakarta',
      lat: -6.1050,
      lng: 106.9250,
      phone: '6281200001010',
      whatsapp: '6281200001010',
      openingHours: 'Daily 07:00–17:00',
      acceptedCategories: ['logam', 'elektronik', 'plastik', 'kertas_kardus'],
      priceInfo: 'Copper Rp60,000/kg, Iron Rp3,800/kg',
    ),
  ];
}

final wasteBankRepositoryProvider = Provider<WasteBankRepository>(
  (_) => WasteBankRepository(),
);

final wasteBanksProvider = FutureProvider<List<WasteBank>>((ref) async {
  return ref.read(wasteBankRepositoryProvider).fetchWasteBanks();
});

final wasteBankDetailProvider = FutureProvider.family<WasteBank?, String>((
  ref,
  id,
) async {
  return ref.read(wasteBankRepositoryProvider).fetchWasteBank(id);
});
