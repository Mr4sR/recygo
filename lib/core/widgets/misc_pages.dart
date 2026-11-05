import 'package:flutter/material.dart';

class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Not Found')),
      body: const Center(child: Text('Page not found.')),
    );
  }
}

class ConfigErrorPage extends StatelessWidget {
  const ConfigErrorPage({super.key});
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Supabase configuration is missing. Run with --dart-define.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
