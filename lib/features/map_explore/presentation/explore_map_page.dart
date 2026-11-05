import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/labels.dart';
import '../../../core/utils/providers.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../auth/data/auth_repository.dart';
import '../../community/data/community_models.dart';
import '../../community/data/community_repository.dart';
import '../../wastebank/data/wastebank_repository.dart';

const LatLng _jakarta = LatLng(-6.2, 106.816);

class ExploreMapPage extends ConsumerStatefulWidget {
  const ExploreMapPage({super.key});
  @override
  ConsumerState<ExploreMapPage> createState() => _ExploreMapPageState();
}

class _ExploreMapPageState extends ConsumerState<ExploreMapPage>
    with AutomaticKeepAliveClientMixin {
  final MapController _mapController = MapController();
  final _searchCtrl = TextEditingController();
  String _filter = 'all'; // all | bank | jual | gratis | ajak_fuse
  double _zoom = 12;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchAddress() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    try {
      final res = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/search?format=json&limit=1&q=${Uri.encodeQueryComponent(q)}',
        ),
        headers: {'User-Agent': 'RecyGo/1.0'},
      );
      if (res.statusCode != 200) return;
      final list = jsonDecode(res.body) as List;
      if (list.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Address not found.')));
        }
        return;
      }
      final first = list.first as Map<String, dynamic>;
      final lat = double.tryParse(first['lat'].toString());
      final lng = double.tryParse(first['lon'].toString());
      if (lat != null && lng != null) {
        _mapController.move(LatLng(lat, lng), 14);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Address search failed.')));
      }
    }
  }

  List<Marker> _buildMarkers(
    BuildContext context,
    List<WasteBank> banks,
    List<CommunityListing> listings,
    UserLocation? myLoc,
  ) {
    final markers = <Marker>[];
    final showBanks = _filter == 'all' || _filter == 'bank';

    List<({double lat, double lng, VoidCallback onTap, Widget child})> points =
        [];

    if (showBanks) {
      for (final b in banks) {
        points.add((
          lat: b.lat,
          lng: b.lng,
          onTap: () => _showBankSheet(context, b, myLoc),
          child: const CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primary,
            child: Icon(Icons.account_balance, color: Colors.white, size: 17),
          ),
        ));
      }
    }
    for (final l in listings) {
      if (l.lat == null || l.lng == null) continue;
      if (_filter == 'jual' && l.listingType != 'jual') continue;
      if (_filter == 'gratis' && l.listingType != 'gratis') continue;
      if (_filter == 'ajak_fuse' && l.listingType != 'ajak_fuse') continue;
      if (_filter == 'bank') continue;
      final (icon, color) = switch (l.listingType) {
        'jual' => (Icons.sell, AppColors.secondary),
        'gratis' => (Icons.volunteer_activism, AppColors.primary),
        _ => (Icons.auto_awesome, const Color(0xFF7C5CFF)),
      };
      points.add((
        lat: l.lat!,
        lng: l.lng!,
        onTap: () => _showListingSheet(context, l, myLoc),
        child: CircleAvatar(
          radius: 16,
          backgroundColor: color,
          child: Icon(icon, color: Colors.white, size: 17),
        ),
      ));
    }

    // Simple grid clustering when zoomed out with many markers.
    if (_zoom < 12 && points.length > 40) {
      final grid =
          <
            String,
            List<({double lat, double lng, VoidCallback onTap, Widget child})>
          >{};
      for (final p in points) {
        final key = '${(p.lat / 0.05).floor()}:${(p.lng / 0.05).floor()}';
        grid.putIfAbsent(key, () => []).add(p);
      }
      for (final cell in grid.values) {
        if (cell.length == 1) {
          final p = cell.first;
          markers.add(
            Marker(
              point: LatLng(p.lat, p.lng),
              width: 40,
              height: 40,
              child: GestureDetector(onTap: p.onTap, child: p.child),
            ),
          );
        } else {
          final cLat =
              cell.map((p) => p.lat).reduce((a, b) => a + b) / cell.length;
          final cLng =
              cell.map((p) => p.lng).reduce((a, b) => a + b) / cell.length;
          markers.add(
            Marker(
              point: LatLng(cLat, cLng),
              width: 44,
              height: 44,
              child: CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.primaryDark,
                child: Text(
                  '${cell.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          );
        }
      }
    } else {
      for (final p in points) {
        markers.add(
          Marker(
            point: LatLng(p.lat, p.lng),
            width: 40,
            height: 40,
            child: GestureDetector(onTap: p.onTap, child: p.child),
          ),
        );
      }
    }

    if (myLoc != null) {
      markers.add(
        Marker(
          point: LatLng(myLoc.lat, myLoc.lng),
          width: 22,
          height: 22,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
            ),
          ),
        ),
      );
    }
    return markers;
  }

  void _showBankSheet(BuildContext context, WasteBank b, UserLocation? myLoc) {
    final d = myLoc != null
        ? haversineKm(myLoc.lat, myLoc.lng, b.lat, b.lng)
        : null;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(b.name, style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(b.address),
            if (d != null) Text('Distance: ${formatDistance(d)}'),
            const SizedBox(height: 14),
            AppButton(
              label: 'View Details',
              onPressed: () {
                Navigator.pop(ctx);
                context.push('/waste-banks/${b.id}');
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showListingSheet(
    BuildContext context,
    CommunityListing l,
    UserLocation? myLoc,
  ) {
    final d = (myLoc != null && l.lat != null)
        ? haversineKm(myLoc.lat, myLoc.lng, l.lat!, l.lng!)
        : null;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.item?.name ?? 'Used Item',
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              l.listingType == 'jual'
                  ? formatRupiah(l.price)
                  : Labels.listingType(l.listingType),
            ),
            if (d != null) Text('Distance: ${formatDistance(d)}'),
            const SizedBox(height: 14),
            AppButton(
              label: 'View Details',
              onPressed: () {
                Navigator.pop(ctx);
                context.push('/community/${l.id}');
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final banksAsync = ref.watch(wasteBanksProvider);
    final listingsAsync = ref.watch(communityListingsProvider);
    final locAsync = ref.watch(deviceLocationProvider);
    final profile = ref.watch(currentProfileProvider);
    final myLoc =
        locAsync.value ??
        (profile?.lat != null
            ? UserLocation(profile!.lat!, profile.lng!)
            : null);
    final banks = banksAsync.value ?? const <WasteBank>[];
    final listings = listingsAsync.value ?? const <CommunityListing>[];
    final markers = _buildMarkers(context, banks, listings, myLoc);
    final locationDenied = locAsync.value == null && profile?.lat == null;

    return Scaffold(
      appBar: AppBar(title: const Text('Explore Map')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'myLocFab',
        tooltip: 'My location',
        onPressed: () {
          if (myLoc != null) {
            _mapController.move(LatLng(myLoc.lat, myLoc.lng), 14);
          } else {
            ref.invalidate(deviceLocationProvider);
          }
        },
        child: const Icon(Icons.my_location),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: myLoc != null
                  ? LatLng(myLoc.lat, myLoc.lng)
                  : _jakarta,
              initialZoom: 12,
              onPositionChanged: (pos, _) {
                if ((pos.zoom - _zoom).abs() > 0.1) {
                  setState(() => _zoom = pos.zoom);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'id.recygo.recygo',
              ),
              MarkerLayer(markers: markers),
            ],
          ),
          Positioned(
            top: 10,
            left: 12,
            right: 12,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search, size: 20),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Search address…',
                          border: InputBorder.none,
                        ),
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _searchAddress(),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Search',
                      onPressed: _searchAddress,
                      icon: const Icon(Icons.arrow_forward, size: 20),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 76,
            left: 12,
            right: 12,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (value, label) in const [
                    ('all', 'All'),
                    ('bank', 'Waste Banks'),
                    ('jual', 'For Sale'),
                    ('gratis', 'Free'),
                    ('ajak_fuse', 'Fuse Together'),
                  ]) ...[
                    TagChip(
                      label: label,
                      selected: _filter == value,
                      onTap: () => setState(() => _filter = value),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ),
          if (locationDenied)
            Positioned(
              left: 12,
              right: 12,
              bottom: 14,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('Enable location for accurate distances.'),
              ),
            ),
          const Positioned(
            left: 10,
            bottom: 8,
            child: Text(
              '© OpenStreetMap contributors',
              style: TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
