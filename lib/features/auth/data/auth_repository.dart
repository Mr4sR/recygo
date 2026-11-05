import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/api/api_client.dart';
import '../../../core/config/env.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/demo_data.dart';
import '../../../core/utils/labels.dart';
import '../../inventory/data/item.dart';

/// In-memory stores for DEMO_MODE.
class DemoStore {
  static final List<Item> items = DemoData.demoItems();
  static Profile profile = DemoData.demoProfile();
}

String translateAuthError(Object e) {
  if (e is ApiException) return e.message;
  final msg = e.toString().toLowerCase();
  if (msg.contains('invalid login credentials') ||
      msg.contains('invalid email or password')) {
    return 'Incorrect email or password.';
  }
  if (msg.contains('user already registered') ||
      msg.contains('already been registered')) {
    return 'This email is already registered. Please sign in.';
  }
  if (msg.contains('password should be at least')) {
    return 'Password must be at least 6 characters.';
  }
  if (msg.contains('unable to validate email')) return 'Invalid email address.';
  if (msg.contains('network') || msg.contains('socket')) {
    return 'Network problem. Check your connection and try again.';
  }
  return 'Something went wrong. Please try again.';
}

/// Result of a sign-up. When the Supabase project requires email confirmation
/// the response carries no session, so the client cannot touch RLS-guarded
/// tables yet and the user must confirm the address before signing in.
class RegisterOutcome {
  final Profile? profile;
  final bool emailConfirmationPending;

  const RegisterOutcome.signedIn(Profile this.profile)
    : emailConfirmationPending = false;

  const RegisterOutcome.confirmEmail()
    : profile = null,
      emailConfirmationPending = true;
}

class AuthRepository {
  bool get _demo => Env.demoMode;
  bool get _backend => Env.useBackend;

  Future<Profile> signIn(String email, String password) async {
    if (_demo) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      return DemoStore.profile;
    }
    try {
      final res = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (res.user == null) {
        throw const AuthException('Incorrect email or password.');
      }
      return fetchProfile(res.user!.id);
    } catch (e) {
      throw Exception(translateAuthError(e));
    }
  }

  Future<RegisterOutcome> register(
    String email,
    String password,
    String displayName,
  ) async {
    if (_demo) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      DemoStore.profile = DemoStore.profile.copyWith(displayName: displayName);
      return RegisterOutcome.signedIn(DemoStore.profile);
    }
    // Backend mode: the server holds the service-role key, so it creates an
    // already-confirmed account and we sign in right away - no verification
    // email. Supabase-only mode keeps the standard signUp flow.
    if (_backend) {
      try {
        await apiClient.postJson('/v1/auth/register', {
          'data': {
            'email': email,
            'password': password,
            'displayName': displayName,
          },
        });
        final res = await supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );
        final user = res.user ?? supabase.auth.currentUser;
        if (user == null) {
          throw const AuthException('Registration failed. Please try again.');
        }
        return RegisterOutcome.signedIn(await fetchProfile(user.id));
      } catch (e) {
        throw Exception(translateAuthError(e));
      }
    }
    try {
      final res = await supabase.auth.signUp(
        email: email,
        password: password,
        data: {'display_name': displayName},
        emailRedirectTo: kIsWeb ? Uri.base.origin : null,
      );
      final user = res.user ?? supabase.auth.currentUser;
      if (user == null) {
        throw const AuthException('Registration failed. Please try again.');
      }
      // Supabase returns an obfuscated user with no identities when the address
      // is already taken, instead of an error.
      if ((user.identities ?? const []).isEmpty) {
        throw const AuthException(
          'This email is already registered. Sign in instead.',
        );
      }
      // Project settings require email confirmation: no session yet, so the
      // profile row is created by the handle_new_user trigger, not by us.
      if (res.session == null) {
        return const RegisterOutcome.confirmEmail();
      }
      await supabase.from('profiles').upsert({
        'id': user.id,
        'display_name': displayName,
      });
      return RegisterOutcome.signedIn(await fetchProfile(user.id));
    } catch (e) {
      throw Exception(translateAuthError(e));
    }
  }

  Future<void> signInWithGoogle() async {
    if (_demo) return;
    await supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: Uri.base.origin,
    );
  }

  Future<void> signOut() async {
    if (_demo) return;
    await supabase.auth.signOut();
  }

  Future<Profile> fetchProfile(String uid) async {
    if (Env.useBackend) {
      final data = await apiClient.getJson('/v1/auth/me');
      return Profile.fromJson(asJsonMap(data));
    }
    if (_demo) return DemoStore.profile;
    final row = await supabase.from('profiles').select().eq('id', uid).single();
    return Profile.fromJson(row);
  }

  Future<Profile> updateProfile(Profile p) async {
    if (Env.useBackend) {
      final data = await apiClient.patchJson('/v1/auth/me', {
        'data': p.toUpdateJson(),
      });
      return Profile.fromJson(asJsonMap(data));
    }
    if (_demo) {
      DemoStore.profile = p;
      return p;
    }
    final row = await supabase
        .from('profiles')
        .update(p.toUpdateJson())
        .eq('id', p.id)
        .select()
        .single();
    return Profile.fromJson(row);
  }

  Future<String> uploadAvatar(String uid, Uint8List bytes) async {
    if (Env.useBackend) {
      return apiClient.uploadBytes(
        bytes,
        filename: 'avatar.jpg',
        folder: 'avatars',
        contentType: 'image/jpeg',
      );
    }
    if (_demo) return '';
    final path = '$uid/avatar.jpg';
    await supabase.storage
        .from('avatars')
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/jpeg',
          ),
        );
    return supabase.storage.from('avatars').getPublicUrl(path);
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (_) => AuthRepository(),
);

/// Session state: null = signed out (or unknown while loading).
class AuthState {
  final Profile? profile;
  final bool loading;
  const AuthState({this.profile, this.loading = false});
  bool get isLoggedIn => profile != null;
}

class AuthController extends Notifier<AuthState> {
  StreamSubscription<dynamic>? _sub;

  @override
  AuthState build() {
    if (Env.demoMode) {
      return const AuthState(profile: null, loading: false);
    }
    _sub = supabase.auth.onAuthStateChange.listen((event) async {
      final user = event.session?.user;
      if (user == null) {
        state = const AuthState(profile: null, loading: false);
      } else {
        state = AuthState(profile: state.profile, loading: true);
        try {
          final p = await ref
              .read(authRepositoryProvider)
              .fetchProfile(user.id);
          state = AuthState(profile: p, loading: false);
        } catch (_) {
          state = const AuthState(profile: null, loading: false);
        }
      }
    });
    ref.onDispose(() => _sub?.cancel());
    final user = supabase.auth.currentUser;
    if (user != null) {
      Future.microtask(() async {
        try {
          final p = await ref
              .read(authRepositoryProvider)
              .fetchProfile(user.id);
          state = AuthState(profile: p, loading: false);
        } catch (_) {
          state = const AuthState(profile: null, loading: false);
        }
      });
      return const AuthState(profile: null, loading: true);
    }
    return const AuthState(profile: null, loading: false);
  }

  Future<void> signIn(String email, String password) async {
    state = const AuthState(loading: true);
    try {
      final p = await ref.read(authRepositoryProvider).signIn(email, password);
      state = AuthState(profile: p);
    } catch (e) {
      state = const AuthState();
      rethrow;
    }
  }

  Future<RegisterOutcome> register(
    String email,
    String password,
    String displayName,
  ) async {
    state = const AuthState(loading: true);
    try {
      final outcome = await ref
          .read(authRepositoryProvider)
          .register(email, password, displayName);
      final profile = outcome.profile;
      state = profile == null
          ? const AuthState()
          : AuthState(profile: profile);
      return outcome;
    } catch (e) {
      state = const AuthState();
      rethrow;
    }
  }

  Future<void> signInDemo() async {
    state = AuthState(profile: DemoStore.profile);
  }

  Future<void> refreshProfile() async {
    final uid = state.profile?.id ?? currentUserId;
    if (uid == null) return;
    final p = await ref.read(authRepositoryProvider).fetchProfile(uid);
    state = AuthState(profile: p);
  }

  Future<void> updateProfile(Profile p) async {
    final updated = await ref.read(authRepositoryProvider).updateProfile(p);
    state = AuthState(profile: updated);
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    state = const AuthState();
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

final currentProfileProvider = Provider<Profile?>(
  (ref) => ref.watch(authControllerProvider).profile,
);
