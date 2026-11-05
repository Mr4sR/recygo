import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/labels.dart';
import '../../../core/utils/sfx.dart';
import '../../../core/widgets/app_widgets.dart';
import '../data/auth_repository.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            tooltip: 'Edit Profile',
            onPressed: () => context.push('/profile/edit'),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: profile == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Center(
                  child: CircleAvatar(
                    radius: 42,
                    backgroundColor: const Color(0xFFE6F7EE),
                    backgroundImage: profile.avatarUrl != null
                        ? NetworkImage(profile.avatarUrl!)
                        : null,
                    child: profile.avatarUrl == null
                        ? Text(
                            profile.displayName.isNotEmpty
                                ? profile.displayName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  profile.displayName,
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                if (profile.city != null)
                  Text(profile.city!, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                _row(Icons.phone_outlined, 'Phone', profile.phone ?? '—'),
                _row(Icons.chat_outlined, 'WhatsApp', profile.whatsapp ?? '—'),
                _row(Icons.location_on_outlined, 'City', profile.city ?? '—'),
                _row(
                  Icons.pin_drop_outlined,
                  'Location',
                  profile.lat != null
                      ? '${profile.lat!.toStringAsFixed(4)}, ${profile.lng!.toStringAsFixed(4)}'
                      : 'Not set',
                ),
                if (profile.bio != null && profile.bio!.isNotEmpty)
                  _row(Icons.info_outline, 'Bio', profile.bio!),
                const SizedBox(height: 20),
                const _SfxTile(),
                const SizedBox(height: 12),
                AppButton(
                  label: 'Edit Profile',
                  icon: Icons.edit_outlined,
                  onPressed: () => context.push('/profile/edit'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    await ref.read(authControllerProvider.notifier).signOut();
                    if (context.mounted) context.go('/login');
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign Out'),
                ),
              ],
            ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(value),
      dense: true,
    );
  }
}

class _SfxTile extends StatefulWidget {
  const _SfxTile();
  @override
  State<_SfxTile> createState() => _SfxTileState();
}

class _SfxTileState extends State<_SfxTile> {
  bool _enabled = Sfx.instance.enabled;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: const Text('Sound Effects'),
      subtitle: const Text('Play sounds for taps, captures, and success'),
      value: _enabled,
      onChanged: (v) async {
        setState(() => _enabled = v);
        await Sfx.instance.setEnabled(v);
      },
    );
  }
}

class ProfileEditPage extends ConsumerStatefulWidget {
  const ProfileEditPage({super.key});
  @override
  ConsumerState<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends ConsumerState<ProfileEditPage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _whatsapp = TextEditingController();
  final _bio = TextEditingController();
  final _city = TextEditingController();
  bool _inited = false;
  bool _saving = false;
  double? _lat;
  double? _lng;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _whatsapp.dispose();
    _bio.dispose();
    _city.dispose();
    super.dispose();
  }

  void _initFrom(Profile p) {
    if (_inited) return;
    _inited = true;
    _name.text = p.displayName;
    _phone.text = p.phone ?? '';
    _whatsapp.text = p.whatsapp ?? '';
    _bio.text = p.bio ?? '';
    _city.text = p.city ?? '';
    _lat = p.lat;
    _lng = p.lng;
  }

  Future<void> _useMyLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied.')),
          );
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get your location.')),
        );
      }
    }
  }

  Future<void> _save() async {
    final profile = ref.read(currentProfileProvider);
    if (profile == null) return;
    setState(() => _saving = true);
    try {
      String? clean(TextEditingController c) =>
          c.text.trim().isEmpty ? null : c.text.trim();
      final updated = profile.copyWith(
        displayName: _name.text.trim().isEmpty
            ? profile.displayName
            : _name.text.trim(),
        phone: clean(_phone),
        whatsapp: clean(_whatsapp),
        bio: clean(_bio),
        city: clean(_city),
        lat: _lat,
        lng: _lng,
      );
      await ref.read(authControllerProvider.notifier).updateProfile(updated);
      Sfx.instance.success();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile saved.')));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save profile: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider);
    if (profile != null) _initFrom(profile);
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: profile == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                AppTextField(controller: _name, label: 'Display Name'),
                const SizedBox(height: 14),
                AppTextField(
                  controller: _phone,
                  label: 'Phone',
                  hint: 'e.g. 62812xxxxxxx (international, no +)',
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 14),
                AppTextField(
                  controller: _whatsapp,
                  label: 'WhatsApp',
                  hint: 'Used for wa.me contact links',
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 14),
                AppTextField(controller: _city, label: 'City'),
                const SizedBox(height: 14),
                AppTextField(
                  controller: _bio,
                  label: 'Bio (optional)',
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _lat != null
                            ? 'Location: ${_lat!.toStringAsFixed(4)}, ${_lng!.toStringAsFixed(4)}'
                            : 'Location: not set',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _useMyLocation,
                      icon: const Icon(Icons.my_location, size: 18),
                      label: const Text('Use My Location'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                AppButton(
                  label: 'Save Profile',
                  onPressed: _save,
                  loading: _saving,
                ),
              ],
            ),
    );
  }
}
