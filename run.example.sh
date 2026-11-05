#!/usr/bin/env bash
# Example run commands for RecyGo (copy to run.local.sh and fill in your values; run.local.sh is gitignored)
#
# Production (Rust backend on Coolify + Supabase Auth/Postgres + RustFS):
# flutter run \
#   --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
#   --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY \
#   --dart-define=BACKEND_BASE_URL=https://api.your-domain.com
#
# Supabase-only (Edge Functions, no Rust backend):
# flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
#
# Demo mode without any credentials:
# flutter run --dart-define=DEMO_MODE=true -d chrome
flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
