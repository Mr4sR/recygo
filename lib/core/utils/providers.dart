import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

class UserLocation {
  final double lat;
  final double lng;
  const UserLocation(this.lat, this.lng);
}

class FuseSelectionController extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};

  void toggle(String id) {
    final next = {...state};
    if (next.contains(id)) {
      next.remove(id);
    } else {
      if (next.length >= 6) return;
      next.add(id);
    }
    state = next;
  }

  void add(String id) {
    if (state.contains(id)) return;
    if (state.length >= 6) return;
    state = {...state, id};
  }

  void clear() => state = {};
}

final fuseSelectionProvider =
    NotifierProvider<FuseSelectionController, Set<String>>(
      FuseSelectionController.new,
    );

/// Best-effort device location. Null when permission denied / unavailable.
final deviceLocationProvider = FutureProvider<UserLocation?>((ref) async {
  try {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
      ),
    ).timeout(const Duration(seconds: 8));
    return UserLocation(pos.latitude, pos.longitude);
  } catch (_) {
    return null;
  }
});
