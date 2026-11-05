# RecyGo — AI-Powered Recycling App

RecyGo turns a crowded photo of used items into a clean, catalog-ready collection:
AI separates each item, cuts it out (transparent PNG), helps you Fuse items into new
creations, share them with the Community, or sell them to the nearest Waste Bank.

Fully in English. Built with Flutter (Android, iOS, Web) + Supabase + Meta AI
(Muse Spark, Muse Image, SAM 3.1).

## Run it (no credentials needed)

```bash
flutter run --dart-define=DEMO_MODE=true -d chrome
```

Demo mode ships static fixtures (items, listings, waste banks, AI responses) so the
whole UI is demonstrable offline. On the sign-in screen tap **Enter Demo Mode**.

## Run it (real backend)

1. Create a Supabase project.
2. Apply the database schema: paste `supabase/migrations/20260101000000_init.sql`
   into the SQL Editor (or `supabase db push`), then run `supabase/seed.sql`
   (10 sample Jakarta waste banks — replace with real data before launch).
3. Set the Edge Function secret (never put this in the Flutter app):

   ```bash
   supabase secrets set META_API_KEY=your_meta_key
   # optional: supabase secrets set META_API_BASE_URL=https://api.meta.ai/v1
   ```

4. Deploy the functions:

   ```bash
   supabase functions deploy ai-analyze-item ai-suggest-prompts ai-segment ai-fuse ai-fuse-image
   ```

5. Run:

   ```bash
   cp run.example.sh run.local.sh   # fill in your values (gitignored)
   flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
   ```

If Supabase is not configured and demo mode is off, the app shows
"Supabase configuration is missing. Run with --dart-define." instead of crashing.

## Features

- **Photo-first inventory** — photo required, max 5, compressed before upload.
- **SAM 3.1 bulk-add** — 1 photo → Muse Spark suggests object types → SAM 3.1
  segments each instance → client-side transparent cutouts (background isolate) →
  bulk review (merge similar, enrich per card, uncheck, save all at once).
- **AI auto-fill** — Muse Spark fills name/category/tags/description/condition/
  brand/material from photos; preview sheet is fully editable before applying.
- **Fuse** — pick 2–6 items → exactly 3 upcycle ideas with steps, difficulty,
  used/missing materials, and a Muse Image illustration per idea. Missing
  materials deep-link into Community search.
- **Community** — publish For Sale / Free / Fuse Together, feed with filters,
  search, distance sorting, favorites, mini-map, WhatsApp (`wa.me`) & call.
- **Waste Banks & Explore Map** — OpenStreetMap (`flutter_map`, no API key),
  grid clustering, address search via Nominatim, nearest-first waste banks
  with indicative prices, OSM directions.
- **Polish** — Material 3 design system (Plus Jakarta Sans + Inter), light/dark,
  responsive shell (bottom bar / rail / extended rail), Lottie states, sound
  effects with a Profile toggle, reduced-motion support.

## Architecture

```text
lib/
  core/        config (dart-define), theme, router, supabase client, widgets, utils
  features/    auth, inventory, ai, segment, fuse, community, wastebank, map_explore, shell
supabase/
  migrations/  schema, RLS, storage buckets
  functions/   _shared/meta.ts (single Meta adapter) + 5 Edge Functions
test/          unit + widget tests
```

All Meta access goes through `supabase/functions/_shared/meta.ts` — the only place
model IDs (`muse-spark-1.3`, `muse-image-1.0`, `sam-3.1`), the base URL, JWT
verification, and the uniform 400/422/502/504 error mapping live. If the official
Meta API shape differs, adapt only that adapter; the client contract is unchanged.

## Verify

```bash
flutter analyze   # clean
flutter test      # 10 tests
flutter build web --dart-define=DEMO_MODE=true
flutter build apk --debug
```

## Seed demo Community data

`scripts/seed_community.py` creates three demo sellers and nine listings
(3 For Sale / 3 Free / 3 Fuse Together) with bundled photos, so the Community
feed is not empty on a fresh database. It talks to the backend over HTTP using
only the Python standard library, and is idempotent — sellers are matched by
email, items by exact name, and an existing listing is never duplicated.

```bash
python scripts/seed_community.py                 # create what is missing
python scripts/seed_community.py --dry-run       # print the plan, write nothing
python scripts/seed_community.py --reset         # delete the seeded items only
python scripts/seed_community.py --backend http://host:8787
```

Sign in as any demo seller with the printed password to see their listings.
Photo provenance and licenses are listed in `scripts/seed_data/CREDITS.md`.

## Coolify backend (Rust + RustFS)

A single-container Rust API lives in `backend/` for deployment on Coolify. It keeps
Meta keys server-side, verifies Supabase user JWTs, persists to the Supabase
Postgres schema above (PostgREST + service-role, owner checks enforced in the
backend), stores media in S3-compatible RustFS, and proxies Meta AI.

```bash
cd backend
cp .env.example .env   # fill SUPABASE_*, META_API_KEY, RUSTFS_*, BACKEND_PUBLIC_URL
docker compose -f docker-compose.coolify.yml up -d --build
curl http://localhost:8080/health
```

Required env: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`
(all three MUST belong to the same Supabase project), `META_API_KEY`,
`RUSTFS_ENDPOINT`, `RUSTFS_ACCESS_KEY`, `RUSTFS_SECRET_KEY`, and
`BACKEND_PUBLIC_URL` (the public base URL of this backend, e.g.
`https://api.your-domain.com`).

Media: RustFS buckets are private, so stored URLs are stable backend proxy URLs
(`{BACKEND_PUBLIC_URL}/v1/media/file/{userId}/{folder}/...`), never expiring
presigned URLs. AI photos are inlined as data URIs server-side (Meta's fetcher
rejects many origins). SAM 3.1 runs on Meta's `/responses` API; v1 uses the
verified bounding boxes for client cutouts (RLE masks are not decoded yet).

Fused illustrations are asynchronous and idempotent per recipe:
`POST /v1/ai/fuse-image` mirrors the Muse Image result into RustFS and persists
it on the recipe row (`PATCH /v1/recipes/{id}/image` is the same write for a
client that already holds a URL). The Fuse Result screen therefore never assumes
the image exists — it polls the recipe for up to 2 minutes while the
illustration is being generated, shows a "Generating illustration…" panel until
`image_url` arrives, and exposes **Regenerate Illustration** for retries.

Run the app against it:

```bash
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... --dart-define=BACKEND_BASE_URL=https://api.your-domain.com
```

Without `BACKEND_BASE_URL` the app keeps the Supabase Edge Functions flow;
`DEMO_MODE=true` keeps the fully offline demo. A live end-to-end smoke
(throwaway user: upload → AI analyze/suggest/segment → items/listings/favorites
→ Fuse + illustration → cleanup) passes against this backend.
