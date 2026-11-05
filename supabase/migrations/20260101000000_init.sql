-- RecyGo init migration
create extension if not exists pgcrypto;

-- ============ Types ============
create type public.item_category as enum
  ('plastik','kertas_kardus','logam','kaca','kain_tekstil','kayu','elektronik','organik','lainnya');
create type public.item_condition as enum ('baru','baik','cukup','rusak_ringan','rusak_berat');
create type public.item_unit as enum ('satuan','kardus','karung','paket','kilogram','lainnya');
create type public.item_status as enum ('draft','tersedia','diberikan','terjual','habis');
create type public.listing_type as enum ('jual','gratis','ajak_fuse');

-- ============ Tables ============
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  avatar_url text,
  phone text,
  whatsapp text,
  bio text,
  city text,
  lat double precision,
  lng double precision,
  created_at timestamptz not null default now()
);

create table public.items (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  category public.item_category not null default 'lainnya',
  tags text[] not null default '{}',
  description text,
  condition public.item_condition,
  brand text,
  material text,
  unit public.item_unit not null default 'satuan',
  quantity int not null default 1 check (quantity >= 1),
  photo_urls text[] not null default '{}',
  original_photo_url text,
  cutout_photo_url text,
  segmentation jsonb,
  status public.item_status not null default 'tersedia',
  is_published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint items_published_needs_photo check (not is_published or array_length(photo_urls,1) >= 1)
);

create table public.community_listings (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items(id) on delete cascade,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  listing_type public.listing_type not null,
  price numeric(12,0),
  note text,
  lat double precision,
  lng double precision,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint listing_price_rule check (
    (listing_type = 'jual' and price is not null and price >= 0) or
    (listing_type <> 'jual' and price is null)
  )
);

create table public.fuse_recipes (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  description text not null,
  steps text[] not null default '{}',
  difficulty text not null default 'mudah',
  estimated_minutes int,
  image_url text,
  source_item_ids uuid[] not null default '{}',
  used_items jsonb not null default '[]',
  missing_items jsonb not null default '[]',
  created_at timestamptz not null default now()
);

create table public.waste_banks (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  address text not null,
  city text,
  lat double precision not null,
  lng double precision not null,
  phone text,
  whatsapp text,
  opening_hours text,
  accepted_categories text[] not null default '{}',
  price_info text,
  photo_url text,
  is_verified boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.favorites (
  user_id uuid not null references public.profiles(id) on delete cascade,
  listing_id uuid not null references public.community_listings(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, listing_id)
);

-- ============ Indexes ============
create index items_owner_idx on public.items(owner_id);
create index items_published_idx on public.items(is_published) where is_published;
create index listings_active_type_idx on public.community_listings(is_active, listing_type);
create index listings_latlng_idx on public.community_listings(lat, lng);
create index waste_banks_latlng_idx on public.waste_banks(lat, lng);

-- ============ Triggers ============
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', 'User'))
  on conflict (id) do nothing;
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end; $$;

drop trigger if exists items_set_updated_at on public.items;
create trigger items_set_updated_at
  before update on public.items
  for each row execute function public.set_updated_at();

-- ============ RLS ============
alter table public.profiles enable row level security;
alter table public.items enable row level security;
alter table public.community_listings enable row level security;
alter table public.fuse_recipes enable row level security;
alter table public.waste_banks enable row level security;
alter table public.favorites enable row level security;

-- profiles: public read, own write
create policy "profiles_select_public" on public.profiles for select using (true);
create policy "profiles_insert_own" on public.profiles for insert with check (auth.uid() = id);
create policy "profiles_update_own" on public.profiles for update using (auth.uid() = id) with check (auth.uid() = id);
create policy "profiles_delete_own" on public.profiles for delete using (auth.uid() = id);

-- items: own or published read, own write
create policy "items_select_own_or_published" on public.items for select
  using (owner_id = auth.uid() or is_published = true);
create policy "items_insert_own" on public.items for insert with check (owner_id = auth.uid());
create policy "items_update_own" on public.items for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "items_delete_own" on public.items for delete using (owner_id = auth.uid());

-- community_listings: active or own read, own write + item must be owned
create policy "listings_select_active_or_own" on public.community_listings for select
  using (is_active = true or owner_id = auth.uid());
create policy "listings_insert_own" on public.community_listings for insert
  with check (owner_id = auth.uid() and exists (select 1 from public.items i where i.id = item_id and i.owner_id = auth.uid()));
create policy "listings_update_own" on public.community_listings for update
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid() and exists (select 1 from public.items i where i.id = item_id and i.owner_id = auth.uid()));
create policy "listings_delete_own" on public.community_listings for delete using (owner_id = auth.uid());

-- fuse_recipes: own only
create policy "recipes_all_own" on public.fuse_recipes for all
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());

-- waste_banks: public read, service_role write only (no authenticated write policy)
create policy "waste_banks_select_public" on public.waste_banks for select using (true);

-- favorites: own only
create policy "favorites_all_own" on public.favorites for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ============ Storage buckets ============
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('item-photos', 'item-photos', true, 5242880, array['image/jpeg','image/png','image/webp']),
  ('avatars', 'avatars', true, 5242880, array['image/jpeg','image/png','image/webp']),
  ('fuse-images', 'fuse-images', true, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

create policy "storage_public_read" on storage.objects for select
  using (bucket_id in ('item-photos','avatars','fuse-images'));
create policy "storage_insert_own_folder" on storage.objects for insert
  with check (bucket_id in ('item-photos','avatars','fuse-images') and (storage.foldername(name))[1] = auth.uid()::text);
create policy "storage_update_own_folder" on storage.objects for update
  using (bucket_id in ('item-photos','avatars','fuse-images') and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id in ('item-photos','avatars','fuse-images') and (storage.foldername(name))[1] = auth.uid()::text);
create policy "storage_delete_own_folder" on storage.objects for delete
  using (bucket_id in ('item-photos','avatars','fuse-images') and (storage.foldername(name))[1] = auth.uid()::text);
