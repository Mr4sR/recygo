import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient get supabase => Supabase.instance.client;

String? get currentUserId => supabase.auth.currentUser?.id;
