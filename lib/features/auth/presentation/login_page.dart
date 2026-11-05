import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/env.dart';
import '../../../core/widgets/app_widgets.dart';
import '../data/auth_repository.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _googleLoading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'Email is required.';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .signIn(_email.text.trim(), _password.text);
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _google() async {
    setState(() => _googleLoading = true);
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.recycling,
                      size: 64,
                      color: Color(0xFF1B9E6B),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Welcome to RecyGo',
                      style: Theme.of(context).textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Turn used items into something new.',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    AppTextField(
                      controller: _email,
                      label: 'Email',
                      hint: 'you@example.com',
                      keyboardType: TextInputType.emailAddress,
                      validator: _validateEmail,
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      controller: _password,
                      label: 'Password',
                      obscure: true,
                      validator: (v) => (v == null || v.length < 6)
                          ? 'Password must be at least 6 characters.'
                          : null,
                    ),
                    const SizedBox(height: 22),
                    AppButton(
                      label: 'Sign In',
                      onPressed: _submit,
                      loading: _loading,
                    ),
                    const SizedBox(height: 12),
                    AppButton(
                      label: 'Continue with Google',
                      onPressed: _google,
                      loading: _googleLoading,
                      ghost: true,
                      icon: Icons.login,
                    ),
                    if (Env.demoMode) ...[
                      const SizedBox(height: 12),
                      AppButton(
                        label: 'Enter Demo Mode',
                        ghost: true,
                        icon: Icons.play_circle_outline,
                        onPressed: () async {
                          await ref
                              .read(authControllerProvider.notifier)
                              .signInDemo();
                          if (context.mounted) context.go('/home');
                        },
                      ),
                    ],
                    const SizedBox(height: 18),
                    TextButton(
                      onPressed: () => context.go('/register'),
                      child: const Text("Don't have an account? Register"),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
