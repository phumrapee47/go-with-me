-- =============================================================================
-- GOWITHME (กลับด้วยกันมั้ย) MVP 0.1 -- initial schema for Supabase Postgres
-- Idempotent-safe: re-running is a no-op (IF NOT EXISTS / CREATE OR REPLACE /
-- DROP ... IF EXISTS / ON CONFLICT DO NOTHING). Design rationale: docs/design-db.md
--
-- Order: extensions -> enums -> config -> tables -> helper fns -> triggers ->
--        RPCs (matching, shares, SOS ...) -> RLS policies -> grants ->
--        realtime -> storage -> cron.
-- Privacy model: the `trips` table (exact geometry) is readable by its OWNER ONLY.
-- Everyone else gets blurred data through SECURITY DEFINER functions.
-- =============================================================================

set search_path = public, extensions;

-- 0. Extensions ---------------------------------------------------------------
create extension if not exists postgis with schema extensions;

-- 1. Enums (small, fixed value sets) ------------------------------------------
do $$ begin create type public.travel_mode         as enum ('walk','transit','car','taxi');                       exception when duplicate_object then null; end $$;
do $$ begin create type public.trip_status         as enum ('scheduled','in_progress','completed','cancelled','expired'); exception when duplicate_object then null; end $$;
do $$ begin create type public.match_status        as enum ('pending','accepted','declined','cancelled');          exception when duplicate_object then null; end $$;
do $$ begin create type public.verification_kind   as enum ('email','organization','phone');                       exception when duplicate_object then null; end $$;
do $$ begin create type public.verification_status as enum ('pending','verified','revoked');                       exception when duplicate_object then null; end $$;
do $$ begin create type public.report_reason       as enum ('harassment','fake_profile','unsafe_behavior','spam','other'); exception when duplicate_object then null; end $$;
do $$ begin create type public.consent_kind        as enum ('privacy_policy','terms','location');                  exception when duplicate_object then null; end $$;
do $$ begin create type public.sos_source          as enum ('trip','chat');                                        exception when duplicate_object then null; end $$;
do $$ begin create type public.message_kind        as enum ('user','system');                                      exception when duplicate_object then null; end $$;

-- 2. Shared trigger fn + central config ---------------------------------------
create or replace function public.update_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ONE place for every tunable threshold (requirements: "ปรับได้ที่จุดเดียว").
-- Change with: update public.app_config set value = '3000' where key = 'match.origin_radius_m';
create table if not exists public.app_config (
  key         text primary key,
  value       jsonb not null,
  description text,
  is_public   boolean not null default false,   -- only is_public rows readable by clients
  updated_at  timestamptz not null default now()
);

insert into public.app_config (key, value, description, is_public) values
  ('match.origin_radius_m',     '2000',  'max distance between two trip origins (m)', true),
  ('match.dest_radius_m',       '2000',  'max distance between two trip destinations (m)', true),
  ('match.time_window_min',     '30',    'max |depart_at difference| (minutes)', true),
  ('match.min_overlap_pct',     '40',    'min route overlap (% of the shorter route)', true),
  ('match.max_matches_per_trip','3',     'max accepted matches per trip', true),
  ('match.route_buffer_m',      '200',   'route A counts as overlapping B when within this buffer (m)', false),
  ('match.weights',             '{"distance":0.3,"time":0.2,"overlap":0.5}', 'score weights (normalised)', false),
  ('match.mode_compat',         '{"walk":["walk"],"transit":["transit"],"car":["car"],"taxi":["taxi"]}', 'compatible travel modes per mode', false),
  ('privacy.blur_cell_m',       '1000',  'grid cell size for blurred locations (m); error <= cell/2 per axis', true),
  ('trip.max_active',           '1',     'max scheduled+in_progress trips per user', true),
  ('trip.min_distance_m',       '200',   'min origin->destination distance (m)', true),
  ('trip.depart_grace_min',     '5',     'depart_at may be this many minutes in the past', false),
  ('trip.expire_after_min',     '120',   'scheduled trips this long past depart_at become expired', false),
  ('share.default_ttl_min',     '720',   'default share-link lifetime (min)', false),
  ('share.max_ttl_min',         '1440',  'max share-link lifetime (min)', false),
  ('share.terminal_grace_min',  '60',    'after trip end, link still shows final status (no location) this long', false),
  ('retention.location_days',   '7',     'precise location kept this long after trip end (days)', false),
  ('retention.account_deletion_days','30','hard-delete accounts this long after deletion request (days)', false),
  ('trip.max_per_day',          '10',    'SECURITY: max trips a user may create per rolling 24h (anti location-probing)', false),
  ('trip.max_geometry_edits',   '3',     'SECURITY: max origin/dest/route edits per trip (anti trilateration probing)', false),
  ('privacy.live_hide_near_dest_m','500', 'SECURITY: partner live location hidden when this close to the destination (home)', false),
  ('emergency.max_contacts',    '3',     'max emergency contacts per user', true),
  ('phone.mock_enabled',        'true',  'MOCK phone OTP; set false in production', false),
  ('phone.mock_code',           '"123456"', 'fixed mock OTP code (never public)', false)
on conflict (key) do nothing;

-- Config readers. SECURITY DEFINER + no client EXECUTE (see grants) so secrets stay private.
create or replace function public.cfg(p_key text) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select value from public.app_config where key = p_key
$$;
create or replace function public.cfg_num(p_key text) returns double precision
language sql stable security definer set search_path = public, pg_temp as $$
  select (value #>> '{}')::double precision from public.app_config where key = p_key
$$;
create or replace function public.cfg_bool(p_key text) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((value #>> '{}')::boolean, false) from public.app_config where key = p_key
$$;

-- 3. Tables --------------------------------------------------------------------
create table if not exists public.org_domains (            -- reference table for org verification
  suffix     text primary key check (suffix = lower(suffix) and suffix ~ '^[a-z0-9][a-z0-9.-]*$'),
  org_name   text not null,
  is_active  boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
insert into public.org_domains (suffix, org_name) values ('ac.th', 'สถาบันการศึกษา (.ac.th)')
on conflict (suffix) do nothing;

create table if not exists public.profiles (               -- 1:1 with auth.users
  id                 uuid primary key references auth.users(id) on delete cascade,
  display_name       text not null check (char_length(btrim(display_name)) between 1 and 60),
  avatar_path        text,                                   -- storage path in bucket `avatars`
  locale             text not null default 'th' check (locale ~ '^[a-z]{2}(-[A-Z]{2})?$'),
  adult_confirmed_at timestamptz,                            -- 18+ declaration
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz                             -- soft delete; hard delete after 30d (purge job)
);

create table if not exists public.consents (               -- append-only PDPA consent log
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references public.profiles(id) on delete cascade,
  kind           public.consent_kind not null,
  granted        boolean not null,                           -- false = withdrawal
  policy_version text not null,
  created_at     timestamptz not null default now()
);

create table if not exists public.verifications (          -- verification records
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  kind        public.verification_kind not null,
  status      public.verification_status not null default 'verified',
  org_suffix  text references public.org_domains(suffix) on delete set null,
  phone_e164  text check (phone_e164 ~ '^\+[0-9]{8,15}$'),
  is_mock     boolean not null default false,                -- MOCK phone OTP badge is distinguishable
  verified_at timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (user_id, kind),
  check (kind = 'phone' or phone_e164 is null),
  check (is_mock = false or kind = 'phone')
);

create table if not exists public.emergency_contacts (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  name       text not null check (char_length(btrim(name)) between 1 and 60),
  phone      text not null check (phone ~ '^\+?[0-9]{8,15}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, phone)
);

create table if not exists public.trips (
  id                   uuid primary key default gen_random_uuid(),
  user_id              uuid not null references public.profiles(id) on delete cascade,
  mode                 public.travel_mode not null,
  status               public.trip_status not null default 'scheduled',
  origin               geography(Point, 4326) not null,
  origin_label         text,
  dest                 geography(Point, 4326) not null,
  dest_label           text,
  route                geography(LineString, 4326) not null,   -- OSRM geometry chosen client-side
  route_distance_m     integer not null check (route_distance_m > 0),   -- denorm (cheap sort/ETA)
  route_duration_s     integer not null check (route_duration_s >= 0),
  depart_at            timestamptz not null,
  started_at           timestamptz,
  ended_at             timestamptz,                            -- completed/cancelled/expired time
  last_location        geography(Point, 4326),                 -- denorm of latest trip_locations row
  last_location_at     timestamptz,
  precision_reduced_at timestamptz,                            -- set when retention job coarsened geometry
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  deleted_at           timestamptz,
  constraint trips_route_min_points check (ST_NPoints(route::geometry) >= 2),
  constraint trips_end_consistency  check ((status in ('completed','cancelled','expired')) = (ended_at is not null)),
  constraint trips_start_consistency check (status <> 'in_progress' or started_at is not null)
);

alter table public.trips add column if not exists geo_edits smallint not null default 0;   -- SECURITY: counts origin/dest/route edits (trips_guard)

do $$ begin
  alter table public.profiles add constraint profiles_avatar_path_own_folder
    check (avatar_path is null or (avatar_path like id::text || '/%' and avatar_path !~ '\.\.'));
exception when duplicate_object then null; end $$;

create table if not exists public.trip_locations (          -- live breadcrumbs, only while in_progress
  id          bigint generated always as identity primary key,
  trip_id     uuid not null references public.trips(id) on delete cascade,
  user_id     uuid not null references public.profiles(id) on delete cascade,  -- denorm for RLS speed
  location    geography(Point, 4326) not null,
  accuracy_m  real check (accuracy_m >= 0),
  recorded_at timestamptz not null default now()
);

create table if not exists public.matches (
  id                uuid primary key default gen_random_uuid(),
  requester_trip_id uuid not null references public.trips(id) on delete cascade,
  target_trip_id    uuid not null references public.trips(id) on delete cascade,
  requester_id      uuid not null references public.profiles(id) on delete cascade,  -- denorm (RLS)
  target_id         uuid not null references public.profiles(id) on delete cascade,  -- denorm (RLS)
  status            public.match_status not null default 'pending',
  score             numeric(5,2),                     -- snapshot at request time
  overlap_pct       numeric(5,2),
  origin_distance_m integer,
  dest_distance_m   integer,
  time_diff_min     numeric(6,1),
  meeting_point     geography(Point, 4326),           -- agreed meet-up (visible to both once matched)
  meeting_label     text,
  responded_at      timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (requester_trip_id, target_trip_id),
  check (requester_trip_id <> target_trip_id),
  check (requester_id <> target_id)
);
-- one match row per UNORDERED trip pair: simultaneous mutual requests -> second insert fails
create unique index if not exists matches_pair_uq
  on public.matches (least(requester_trip_id, target_trip_id), greatest(requester_trip_id, target_trip_id));

create table if not exists public.chat_messages (
  id            uuid primary key default gen_random_uuid(),
  match_id      uuid not null references public.matches(id) on delete cascade,
  sender_id     uuid references public.profiles(id) on delete cascade,   -- null for system messages
  kind          public.message_kind not null default 'user',
  body          text not null check (char_length(btrim(body)) between 1 and 1000),
  client_msg_id uuid,                                  -- idempotent retry from client
  created_at    timestamptz not null default now(),
  check ((kind = 'user') = (sender_id is not null))
);

create table if not exists public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create table if not exists public.reports (
  id               uuid primary key default gen_random_uuid(),
  reporter_id      uuid not null references public.profiles(id) on delete cascade,
  reported_user_id uuid not null references public.profiles(id) on delete cascade,
  match_id         uuid references public.matches(id) on delete set null,
  reason           public.report_reason not null,
  details          text check (char_length(details) <= 1000),
  created_at       timestamptz not null default now(),
  check (reporter_id <> reported_user_id)
);

create table if not exists public.sos_events (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references public.profiles(id) on delete cascade,
  trip_id           uuid references public.trips(id) on delete set null,
  source            public.sos_source not null default 'trip',
  location          geography(Point, 4326),            -- null if GPS unavailable
  note              text check (char_length(note) <= 500),
  client_created_at timestamptz not null default now(),-- when pressed (offline queue)
  created_at        timestamptz not null default now() -- when stored
);

create table if not exists public.trip_shares (
  id             uuid primary key default gen_random_uuid(),
  trip_id        uuid not null references public.trips(id) on delete cascade,
  user_id        uuid not null references public.profiles(id) on delete cascade,
  token_hash     bytea not null unique,                -- sha256(token); raw token only returned once
  expires_at     timestamptz not null,
  revoked_at     timestamptz,
  last_viewed_at timestamptz,
  created_at     timestamptz not null default now()
);

-- 4. Indexes (justification in docs/design-db.md) ------------------------------
create index if not exists org_domains_active_idx        on public.org_domains (suffix) where is_active;
create index if not exists profiles_deleted_idx           on public.profiles (deleted_at) where deleted_at is not null;
create index if not exists consents_user_kind_idx         on public.consents (user_id, kind, created_at desc);
create index if not exists verifications_org_idx          on public.verifications (org_suffix) where org_suffix is not null;
create index if not exists emergency_contacts_user_idx    on public.emergency_contacts (user_id);
create index if not exists trips_user_status_idx          on public.trips (user_id, status, created_at desc);
create index if not exists trips_open_origin_gix          on public.trips using gist (origin) where status = 'scheduled' and deleted_at is null;
create index if not exists trips_open_dest_gix            on public.trips using gist (dest)   where status = 'scheduled' and deleted_at is null;
create index if not exists trips_open_depart_idx          on public.trips (depart_at)         where status = 'scheduled' and deleted_at is null;
create index if not exists trips_ended_retention_idx      on public.trips (ended_at)          where ended_at is not null and precision_reduced_at is null;
create index if not exists trips_deleted_idx              on public.trips (deleted_at)        where deleted_at is not null;
create index if not exists trip_locations_trip_time_idx   on public.trip_locations (trip_id, recorded_at desc);
create index if not exists trip_locations_user_idx        on public.trip_locations (user_id);
create index if not exists matches_req_trip_idx           on public.matches (requester_trip_id);
create index if not exists matches_tgt_trip_idx           on public.matches (target_trip_id);
create index if not exists matches_req_user_idx           on public.matches (requester_id, status);
create index if not exists matches_tgt_user_idx           on public.matches (target_id, status);
create index if not exists matches_accepted_idx           on public.matches (requester_trip_id, target_trip_id) where status = 'accepted';
create index if not exists chat_messages_match_time_idx   on public.chat_messages (match_id, created_at desc);
create index if not exists chat_messages_sender_idx       on public.chat_messages (sender_id) where sender_id is not null;
create unique index if not exists chat_messages_client_uq on public.chat_messages (sender_id, client_msg_id) where client_msg_id is not null;
create index if not exists blocks_blocked_idx             on public.blocks (blocked_id);
create index if not exists reports_reporter_idx           on public.reports (reporter_id);
create index if not exists reports_reported_idx           on public.reports (reported_user_id, created_at desc);
create index if not exists reports_match_idx              on public.reports (match_id) where match_id is not null;
create index if not exists sos_events_user_time_idx       on public.sos_events (user_id, created_at desc);
create index if not exists sos_events_trip_idx            on public.sos_events (trip_id) where trip_id is not null;
create index if not exists trip_shares_trip_idx           on public.trip_shares (trip_id);
create index if not exists trip_shares_user_idx           on public.trip_shares (user_id);
create index if not exists trip_shares_active_idx         on public.trip_shares (expires_at) where revoked_at is null;

-- 5. updated_at triggers -------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['app_config','org_domains','profiles','verifications','emergency_contacts','trips','matches']
  loop
    execute format('drop trigger if exists trg_%1$s_updated_at on public.%1$s', t);
    execute format('create trigger trg_%1$s_updated_at before update on public.%1$s for each row execute function public.update_updated_at()', t);
  end loop;
end $$;

-- 6. Helper functions (used by policies and RPCs) -------------------------------
-- All SECURITY DEFINER (bypass RLS on purpose, narrowly scoped) with pinned search_path.

create or replace function public.is_admin() returns boolean
language sql stable set search_path = public, pg_temp as $$
  select coalesce((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin', false)
$$;

create or replace function public.are_matched(p_a uuid, p_b uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from public.matches m
    where m.status = 'accepted'
      and ((m.requester_id = p_a and m.target_id = p_b) or (m.requester_id = p_b and m.target_id = p_a)))
$$;

-- Chat is open only for an accepted match whose two trips are both still active, and neither user blocked the other.
-- Enforced in the INSERT policy => backend-level, not UI-only (US-8).
create or replace function public.is_chat_open(p_match_id uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1
    from public.matches m
    join public.trips a on a.id = m.requester_trip_id
    join public.trips b on b.id = m.target_trip_id
    where m.id = p_match_id and m.status = 'accepted'
      and auth.uid() in (m.requester_id, m.target_id)
      and a.status in ('scheduled','in_progress') and b.status in ('scheduled','in_progress')
      and not exists (select 1 from public.blocks bl
                      where (bl.blocker_id = m.requester_id and bl.blocked_id = m.target_id)
                         or (bl.blocker_id = m.target_id and bl.blocked_id = m.requester_id)))
$$;

create or replace function public.is_own_trip_in_progress(p_trip_id uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from public.trips t
                 where t.id = p_trip_id and t.user_id = auth.uid() and t.status = 'in_progress' and t.deleted_at is null)
$$;

create or replace function public.has_location_consent() returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((select c.granted from public.consents c
                   where c.user_id = auth.uid() and c.kind = 'location'
                   order by c.created_at desc limit 1), false)
$$;

create or replace function public.safe_uuid(p text) returns uuid
language plpgsql immutable as $$
begin return p::uuid; exception when others then return null; end $$;

-- Deterministic location blur: snap to the centre of a ~blur_cell_m grid cell.
-- Snapping (not random jitter) => repeated queries cannot be averaged to recover the true point.
create or replace function public.blur_point(p_point geography, p_cell_m double precision default null)
returns geography language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare
  v_cell  double precision := coalesce(p_cell_m, public.cfg_num('privacy.blur_cell_m'));
  v_dlat  double precision := v_cell / 111320.0;
  v_lat_c double precision;
  v_dlon  double precision;
begin
  if p_point is null then return null; end if;
  v_lat_c := (floor(ST_Y(p_point::geometry) / v_dlat) + 0.5) * v_dlat;
  v_lat_c := greatest(-89.0, least(89.0, v_lat_c));
  v_dlon  := v_cell / (111320.0 * cos(radians(v_lat_c)));
  return ST_SetSRID(ST_MakePoint((floor(ST_X(p_point::geometry) / v_dlon) + 0.5) * v_dlon, v_lat_c), 4326)::geography;
end $$;

-- Route overlap % = length of the SHORTER route lying within p_buffer_m of the other / its own length.
-- Symmetric (A,B) == (B,A) except exact length ties; deterministic for identical inputs.
create or replace function public.route_overlap_pct(p_a geography, p_b geography, p_buffer_m double precision)
returns double precision language sql stable set search_path = public, extensions, pg_temp as $$
  select least(100.0, coalesce(
    case when ST_Length(p_a) <= ST_Length(p_b)
         then 100.0 * ST_Length(ST_Intersection(p_a, ST_Buffer(p_b, p_buffer_m))) / nullif(ST_Length(p_a), 0)
         else 100.0 * ST_Length(ST_Intersection(p_b, ST_Buffer(p_a, p_buffer_m))) / nullif(ST_Length(p_b), 0)
    end, 0))
$$;

create or replace function public.user_badges(p_user uuid) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object('kind', v.kind, 'is_mock', v.is_mock, 'org_name', od.org_name)
                            order by v.kind), '[]'::jsonb)
  from public.verifications v
  left join public.org_domains od on od.suffix = v.org_suffix
  where v.user_id = p_user and v.status = 'verified'
    and (not v.is_mock or public.cfg_bool('phone.mock_enabled'))   -- mock badge vanishes when disabled in prod
$$;

-- 7. Auth integration: profile + verification sync ------------------------------
create or replace function public.sync_user_verifications(p_uid uuid, p_email text, p_confirmed timestamptz)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_domain text; v_suffix text;
begin
  if p_confirmed is null or p_email is null then
    update public.verifications set status = 'revoked'
     where user_id = p_uid and kind in ('email','organization') and status = 'verified';
    return;
  end if;
  insert into public.verifications (user_id, kind, status, verified_at)
  values (p_uid, 'email', 'verified', p_confirmed)
  on conflict (user_id, kind) do update set status = 'verified', verified_at = excluded.verified_at;

  -- subdomain/alias aware: mail.uni.ac.th matches suffix ac.th, evilac.th does not.
  v_domain := lower(split_part(p_email, '@', 2));
  select o.suffix into v_suffix from public.org_domains o
   where o.is_active and (v_domain = o.suffix or v_domain like '%.' || o.suffix)
   order by length(o.suffix) desc limit 1;

  if v_suffix is not null then
    insert into public.verifications (user_id, kind, status, org_suffix, verified_at)
    values (p_uid, 'organization', 'verified', v_suffix, p_confirmed)
    on conflict (user_id, kind) do update set status = 'verified', org_suffix = excluded.org_suffix, verified_at = excluded.verified_at;
  else
    update public.verifications set status = 'revoked'
     where user_id = p_uid and kind = 'organization' and status = 'verified';
  end if;
end $$;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_name text; v_ver text;
begin
  v_name := left(coalesce(nullif(btrim(new.raw_user_meta_data ->> 'display_name'), ''),
                          nullif(split_part(coalesce(new.email, ''), '@', 1), ''), 'ผู้ใช้'), 60);
  insert into public.profiles (id, display_name, adult_confirmed_at)
  values (new.id, v_name,
          case when new.raw_user_meta_data ->> 'adult_confirmed' = 'true' then now() end)
  on conflict (id) do nothing;

  v_ver := nullif(new.raw_user_meta_data ->> 'policy_version', '');
  if v_ver is not null then
    insert into public.consents (user_id, kind, granted, policy_version)
    values (new.id, 'privacy_policy', true, v_ver), (new.id, 'terms', true, v_ver);
  end if;
  perform public.sync_user_verifications(new.id, new.email, new.email_confirmed_at);
  return new;
end $$;

create or replace function public.handle_auth_user_update() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public.sync_user_verifications(new.id, new.email, new.email_confirmed_at);
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

drop trigger if exists on_auth_user_email_changed on auth.users;
create trigger on_auth_user_email_changed after update of email, email_confirmed_at on auth.users
  for each row when (old.email is distinct from new.email or old.email_confirmed_at is distinct from new.email_confirmed_at)
  execute function public.handle_auth_user_update();

-- 8. Business-rule triggers -----------------------------------------------------
-- Emergency contacts: max N (config) per user.
create or replace function public.emergency_contacts_guard() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform 1 from public.profiles where id = new.user_id for update;   -- serialise concurrent inserts
  if (select count(*) from public.emergency_contacts where user_id = new.user_id) >= public.cfg_num('emergency.max_contacts') then
    raise exception 'GWM_EMERGENCY_CONTACT_LIMIT' using errcode = 'P0001';
  end if;
  return new;
end $$;
drop trigger if exists trg_emergency_contacts_guard on public.emergency_contacts;
create trigger trg_emergency_contacts_guard before insert on public.emergency_contacts
  for each row execute function public.emergency_contacts_guard();

-- Trip state machine + creation rules (US-5, US-9).
--   scheduled -> in_progress | cancelled | expired(system only)
--   in_progress -> completed | cancelled
--   completed / cancelled / expired are terminal.
-- System jobs (pg_cron / service_role) run with auth.uid() IS NULL.
create or replace function public.trips_guard() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_system boolean := auth.uid() is null;
  v_grace  interval := public.cfg_num('trip.depart_grace_min') * interval '1 minute';
  v_terminal public.trip_status[] := array['completed','cancelled','expired']::public.trip_status[];
begin
  if tg_op = 'INSERT' then
    new.status := 'scheduled'; new.started_at := null; new.ended_at := null;
    new.last_location := null; new.last_location_at := null; new.precision_reduced_at := null; new.deleted_at := null; new.geo_edits := 0;

    perform 1 from public.profiles where id = new.user_id and deleted_at is null for update;  -- lock => race-free limit
    if not found then raise exception 'GWM_PROFILE_UNAVAILABLE' using errcode = 'P0001'; end if;
    if new.depart_at < now() - v_grace then
      raise exception 'GWM_DEPART_IN_PAST' using errcode = 'P0001';
    end if;
    if ST_Distance(new.origin, new.dest) < public.cfg_num('trip.min_distance_m') then
      raise exception 'GWM_TRIP_TOO_SHORT' using errcode = 'P0001';
    end if;
    if (select count(*) from public.trips t
         where t.user_id = new.user_id and t.status in ('scheduled','in_progress') and t.deleted_at is null)
       >= public.cfg_num('trip.max_active') then
      raise exception 'GWM_ACTIVE_TRIP_LIMIT' using errcode = 'P0001';
    end if;
    -- SECURITY: cap trip creation per day (each new trip is a fresh probe point for find_matches)
    if (select count(*) from public.trips t where t.user_id = new.user_id and t.created_at > now() - interval '24 hours')
       >= public.cfg_num('trip.max_per_day') then
      raise exception 'GWM_TRIP_RATE_LIMIT' using errcode = 'P0001';
    end if;
    return new;
  end if;

  -- UPDATE
  if new.user_id <> old.user_id then raise exception 'GWM_IMMUTABLE' using errcode = 'P0001'; end if;

  if new.status <> old.status then
    if not ((old.status = 'scheduled'   and new.status in ('in_progress','cancelled','expired'))
         or (old.status = 'in_progress' and new.status in ('completed','cancelled'))) then
      raise exception 'GWM_INVALID_TRIP_TRANSITION' using errcode = 'P0001';
    end if;
    if new.status = 'expired' and not v_system then raise exception 'GWM_INVALID_TRIP_TRANSITION' using errcode = 'P0001'; end if;
    if new.status = 'in_progress' then new.started_at := now(); end if;
    if new.status = any (v_terminal) then new.ended_at := now(); end if;
  end if;

  if not v_system then
    -- SECURITY: cap geometry edits (moving origin to probe find_matches = trilateration of other users)
    if new.origin is distinct from old.origin or new.dest is distinct from old.dest or new.route is distinct from old.route then
      new.geo_edits := old.geo_edits + 1;
      if new.geo_edits > public.cfg_num('trip.max_geometry_edits') then
        raise exception 'GWM_TRIP_EDIT_LIMIT' using errcode = 'P0001';
      end if;
    else
      new.geo_edits := old.geo_edits;
    end if;
    if old.status = any (v_terminal) and (
         new.mode is distinct from old.mode or new.depart_at is distinct from old.depart_at or new.origin is distinct from old.origin
         or new.dest is distinct from old.dest or new.route is distinct from old.route) then
      raise exception 'GWM_TRIP_FINISHED' using errcode = 'P0001';
    end if;
    if old.status = 'in_progress' and (
         new.mode is distinct from old.mode or new.depart_at is distinct from old.depart_at or new.origin is distinct from old.origin
         or new.dest is distinct from old.dest or new.route is distinct from old.route) then
      raise exception 'GWM_TRIP_STARTED' using errcode = 'P0001';
    end if;
    if new.depart_at <> old.depart_at and new.depart_at < now() - v_grace then
      raise exception 'GWM_DEPART_IN_PAST' using errcode = 'P0001';
    end if;
    if new.deleted_at is not null and old.deleted_at is null and new.status <> all (v_terminal) then
      raise exception 'GWM_CANCEL_BEFORE_DELETE' using errcode = 'P0001';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_trips_guard on public.trips;
create trigger trg_trips_guard before insert or update on public.trips
  for each row execute function public.trips_guard();

-- When a trip ends: close pending requests, tell accepted partners via a system chat message.
create or replace function public.trips_after_status() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if new.status in ('completed','cancelled','expired') then
    update public.matches set status = 'cancelled', responded_at = now()
     where status = 'pending' and new.id in (requester_trip_id, target_trip_id);
    insert into public.chat_messages (match_id, sender_id, kind, body)
    select m.id, null, 'system', 'system.trip_' || new.status::text
      from public.matches m
     where m.status = 'accepted' and new.id in (m.requester_trip_id, m.target_trip_id);
  end if;
  return null;
end $$;
drop trigger if exists trg_trips_after_status on public.trips;
create trigger trg_trips_after_status after update of status on public.trips
  for each row when (old.status is distinct from new.status) execute function public.trips_after_status();

-- Live location: mirror latest point onto trips (denorm) for cheap partner/share reads.
create or replace function public.trip_locations_after_insert() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update public.trips set last_location = new.location, last_location_at = new.recorded_at where id = new.trip_id;
  return null;
end $$;
drop trigger if exists trg_trip_locations_after_insert on public.trip_locations;
create trigger trg_trip_locations_after_insert after insert on public.trip_locations
  for each row execute function public.trip_locations_after_insert();

-- Blocking ends any open match between the two users.
create or replace function public.blocks_after_insert() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update public.matches set status = 'cancelled', responded_at = now()
   where status in ('pending','accepted')
     and ((requester_id = new.blocker_id and target_id = new.blocked_id)
       or (requester_id = new.blocked_id and target_id = new.blocker_id));
  return null;
end $$;
drop trigger if exists trg_blocks_after_insert on public.blocks;
create trigger trg_blocks_after_insert after insert on public.blocks
  for each row execute function public.blocks_after_insert();

-- SECURITY: DB-level abuse throttles (defence in depth behind Supabase API rate limits).
create or replace function public.trip_locations_rate_guard() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if exists (select 1 from public.trip_locations where trip_id = new.trip_id and recorded_at > now() - interval '5 seconds') then
    raise exception 'GWM_RATE_LIMITED' using errcode = 'P0001';
  end if;
  return new;
end $$;
drop trigger if exists trg_trip_locations_rate_guard on public.trip_locations;
create trigger trg_trip_locations_rate_guard before insert on public.trip_locations
  for each row execute function public.trip_locations_rate_guard();

create or replace function public.chat_messages_rate_guard() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if new.kind = 'user' and (select count(*) from public.chat_messages
       where match_id = new.match_id and sender_id = new.sender_id and created_at > now() - interval '10 seconds') >= 10 then
    raise exception 'GWM_RATE_LIMITED' using errcode = 'P0001';
  end if;
  return new;
end $$;
drop trigger if exists trg_chat_messages_rate_guard on public.chat_messages;
create trigger trg_chat_messages_rate_guard before insert on public.chat_messages
  for each row execute function public.chat_messages_rate_guard();

-- 9. Matching ---------------------------------------------------------------------
-- Internal engine (no auth check, EXECUTE revoked from clients). Single source of truth for the formula:
--   eligible  <=> both origins within match.origin_radius_m (ST_DWithin, GiST)
--             AND both destinations within match.dest_radius_m
--             AND |depart_at diff| <= match.time_window_min
--             AND overlap% >= match.min_overlap_pct (route buffered by match.route_buffer_m)
--             AND modes compatible (match.mode_compat), not blocked, not deleted,
--             AND neither trip has match.max_matches_per_trip accepted matches.
--   score(0..100) = 100 * (w_d*(1 - avg(d_origin/r_o, d_dest/r_d)) + w_t*(1 - dt/window) + w_o*overlap/100) / (w_d+w_t+w_o)
--   order: score desc, trip id asc  => deterministic.
create or replace function public.match_candidates(p_trip_id uuid, p_limit int default 20, p_only_trip uuid default null)
returns table (candidate_trip_id uuid, candidate_user_id uuid, origin_distance_m double precision,
               dest_distance_m double precision, time_diff_min double precision,
               overlap_pct double precision, score double precision)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
#variable_conflict use_column
declare
  v_t      public.trips%rowtype;
  v_r_o    double precision := public.cfg_num('match.origin_radius_m');
  v_r_d    double precision := public.cfg_num('match.dest_radius_m');
  v_win    double precision := public.cfg_num('match.time_window_min');
  v_min_ov double precision := public.cfg_num('match.min_overlap_pct');
  v_max    int              := public.cfg_num('match.max_matches_per_trip')::int;
  v_buf    double precision := public.cfg_num('match.route_buffer_m');
  v_w      jsonb            := public.cfg('match.weights');
  v_compat jsonb            := public.cfg('match.mode_compat');
  v_wd double precision := (v_w ->> 'distance')::double precision;
  v_wt double precision := (v_w ->> 'time')::double precision;
  v_wo double precision := (v_w ->> 'overlap')::double precision;
begin
  select * into v_t from public.trips where id = p_trip_id and deleted_at is null;
  if not found or v_t.status <> 'scheduled' then return; end if;
  if (select count(*) from public.matches m where m.status = 'accepted'
        and v_t.id in (m.requester_trip_id, m.target_trip_id)) >= v_max then return; end if;

  return query
  with cand as (
    select o.id as tid, o.user_id as uid, o.route as route,
           ST_Distance(o.origin, v_t.origin) as d_o,
           ST_Distance(o.dest,   v_t.dest)   as d_d,
           (abs(extract(epoch from (o.depart_at - v_t.depart_at))) / 60.0)::double precision as dt
      from public.trips o
      join public.profiles p on p.id = o.user_id and p.deleted_at is null
     where o.status = 'scheduled' and o.deleted_at is null
       and o.user_id <> v_t.user_id
       and (p_only_trip is null or o.id = p_only_trip)
       and ST_DWithin(o.origin, v_t.origin, v_r_o)
       and ST_DWithin(o.dest,   v_t.dest,   v_r_d)
       and o.depart_at between v_t.depart_at - v_win * interval '1 minute'
                           and v_t.depart_at + v_win * interval '1 minute'
       and (v_compat -> v_t.mode::text) @> to_jsonb(o.mode::text)
       and not exists (select 1 from public.blocks b
                        where (b.blocker_id = v_t.user_id and b.blocked_id = o.user_id)
                           or (b.blocker_id = o.user_id  and b.blocked_id = v_t.user_id))
       and not exists (select 1 from public.matches m              -- only a still-pending pair stays visible
                        where m.status <> 'pending'
                          and ((m.requester_trip_id = v_t.id and m.target_trip_id = o.id)
                            or (m.requester_trip_id = o.id  and m.target_trip_id = v_t.id)))
       and (select count(*) from public.matches m where m.status = 'accepted'
              and o.id in (m.requester_trip_id, m.target_trip_id)) < v_max
  ), scored as (
    select c.tid, c.uid, c.d_o, c.d_d, c.dt,
           public.route_overlap_pct(v_t.route, c.route, v_buf) as ov
      from cand c
  )
  select s.tid, s.uid, s.d_o, s.d_d, s.dt, s.ov,
         100.0 * ( v_wd * (1 - least(1.0, (s.d_o / v_r_o + s.d_d / v_r_d) / 2.0))
                 + v_wt * (1 - s.dt / nullif(v_win, 0))
                 + v_wo * (s.ov / 100.0) ) / nullif(v_wd + v_wt + v_wo, 0)
    from scored s
   where s.ov >= v_min_ov
   order by 7 desc, s.tid asc
   limit p_limit;
end $$;

-- Client-facing: ONLY blurred data leaves this function.
create or replace function public.find_matches(p_trip_id uuid, p_limit int default 20)
returns table (trip_id uuid, display_name text, badges jsonb, mode public.travel_mode, depart_at timestamptz,
               time_diff_min int, overlap_pct int, approx_distance_m int, score numeric,
               approx_origin_lat double precision, approx_origin_lng double precision,
               approx_dest_lat double precision, approx_dest_lng double precision,
               request_status public.match_status)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
#variable_conflict use_column
begin
  p_limit := least(greatest(coalesce(p_limit, 20), 1), 50);   -- SECURITY: cap result size (scraping)
  if not exists (select 1 from public.trips t where t.id = p_trip_id and t.user_id = auth.uid() and t.deleted_at is null) then
    raise exception 'GWM_TRIP_NOT_FOUND' using errcode = '42501';
  end if;
  return query
  select o.id, pr.display_name, public.user_badges(o.user_id), o.mode, o.depart_at,
         round(c.time_diff_min)::int, round(c.overlap_pct)::int,
         (greatest(1, round(c.origin_distance_m / 500.0)) * 500)::int,       -- SECURITY: 500 m buckets (100 m rounding allowed trilateration of true origin)
         (round(c.score::numeric / 5.0) * 5)::numeric,                        -- SECURITY: score bucketed (fine score leaks distance)
         ST_Y(public.blur_point(o.origin)::geometry), ST_X(public.blur_point(o.origin)::geometry),
         ST_Y(public.blur_point(o.dest)::geometry),   ST_X(public.blur_point(o.dest)::geometry),
         (select m.status from public.matches m
           where (m.requester_trip_id = p_trip_id and m.target_trip_id = o.id)
              or (m.requester_trip_id = o.id and m.target_trip_id = p_trip_id) limit 1)
    from public.match_candidates(p_trip_id, p_limit) c
    join public.trips o     on o.id  = c.candidate_trip_id
    join public.profiles pr on pr.id = c.candidate_user_id
   order by c.score desc, o.id;
end $$;

-- Card for a trip the caller is entitled to see: own, or counter-party in any pending/accepted match. Always blurred.
create or replace function public.get_trip_card(p_trip_id uuid)
returns table (trip_id uuid, display_name text, badges jsonb, mode public.travel_mode, depart_at timestamptz, status public.trip_status,
               approx_origin_lat double precision, approx_origin_lng double precision,
               approx_dest_lat double precision, approx_dest_lng double precision)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
#variable_conflict use_column
begin
  if not exists (
       select 1 from public.trips t where t.id = p_trip_id and t.user_id = auth.uid())
     and not exists (
       select 1 from public.matches m
        where m.status in ('pending','accepted') and auth.uid() in (m.requester_id, m.target_id)
          and p_trip_id in (m.requester_trip_id, m.target_trip_id)) then
    raise exception 'GWM_FORBIDDEN' using errcode = '42501';
  end if;
  return query
  select t.id, pr.display_name, public.user_badges(t.user_id), t.mode, t.depart_at, t.status,
         ST_Y(public.blur_point(t.origin)::geometry), ST_X(public.blur_point(t.origin)::geometry),
         ST_Y(public.blur_point(t.dest)::geometry),   ST_X(public.blur_point(t.dest)::geometry)
    from public.trips t join public.profiles pr on pr.id = t.user_id
   where t.id = p_trip_id;
end $$;

-- Partner live position: only for an accepted match while partner's trip is in_progress.
create or replace function public.get_partner_live_location(p_match_id uuid)
returns table (lat double precision, lng double precision, recorded_at timestamptz)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
#variable_conflict use_column
begin
  return query
  select ST_Y(t.last_location::geometry), ST_X(t.last_location::geometry), t.last_location_at
    from public.matches m
    join public.trips t on t.id = case when m.requester_id = auth.uid() then m.target_trip_id else m.requester_trip_id end
   where m.id = p_match_id and m.status = 'accepted' and auth.uid() in (m.requester_id, m.target_id)
     and t.status = 'in_progress' and t.last_location is not null
     -- SECURITY: viewer must be travelling too (else a matched stalker can watch without ever moving)
     and exists (select 1 from public.trips mine
                  where mine.id = case when m.requester_id = auth.uid() then m.requester_trip_id else m.target_trip_id end
                    and mine.status = 'in_progress')
     -- SECURITY: stop revealing the exact position near the destination (would disclose home)
     and not ST_DWithin(t.last_location, t.dest, public.cfg_num('privacy.live_hide_near_dest_m'));
end $$;

-- 10. Match lifecycle RPCs (matches has no client INSERT/UPDATE policy) ---------------
create or replace function public._accept_match(p_match_id uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_m public.matches%rowtype; v_max int := public.cfg_num('match.max_matches_per_trip')::int;
begin
  select * into v_m from public.matches where id = p_match_id and status = 'pending' for update;
  if not found then raise exception 'GWM_MATCH_NOT_PENDING' using errcode = 'P0001'; end if;
  perform 1 from public.trips where id in (v_m.requester_trip_id, v_m.target_trip_id) order by id for update;  -- ordered lock: no deadlock
  if exists (select 1 from public.trips where id in (v_m.requester_trip_id, v_m.target_trip_id)
                and (status <> 'scheduled' or deleted_at is not null)) then
    raise exception 'GWM_TRIP_UNAVAILABLE' using errcode = 'P0001';
  end if;
  if (select count(*) from public.matches x where x.status = 'accepted'
        and v_m.requester_trip_id in (x.requester_trip_id, x.target_trip_id)) >= v_max
  or (select count(*) from public.matches x where x.status = 'accepted'
        and v_m.target_trip_id in (x.requester_trip_id, x.target_trip_id)) >= v_max then
    raise exception 'GWM_MATCH_LIMIT' using errcode = 'P0001';
  end if;
  update public.matches set status = 'accepted', responded_at = now() where id = p_match_id;
  insert into public.chat_messages (match_id, sender_id, kind, body) values (p_match_id, null, 'system', 'system.matched');
end $$;

create or replace function public.request_match(p_my_trip uuid, p_target_trip uuid) returns uuid
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_uid uuid := auth.uid(); v_me public.trips%rowtype; v_c record; v_rev public.matches%rowtype; v_id uuid;
begin
  if v_uid is null then raise exception 'GWM_UNAUTHENTICATED' using errcode = '42501'; end if;
  select * into v_me from public.trips where id = p_my_trip and user_id = v_uid and deleted_at is null;
  if not found or v_me.status <> 'scheduled' then raise exception 'GWM_TRIP_NOT_FOUND' using errcode = 'P0001'; end if;

  select * into v_c from public.match_candidates(p_my_trip, 1, p_target_trip);   -- re-check eligibility server-side
  if not found then raise exception 'GWM_NOT_ELIGIBLE' using errcode = 'P0001'; end if;

  -- The other side already asked me => mutual interest, accept that request (exactly one match row).
  select * into v_rev from public.matches where requester_trip_id = p_target_trip and target_trip_id = p_my_trip for update;
  if found then
    if v_rev.status = 'pending' then perform public._accept_match(v_rev.id); return v_rev.id; end if;
    raise exception 'GWM_ALREADY_EXISTS' using errcode = 'P0001';
  end if;

  begin
    insert into public.matches (requester_trip_id, target_trip_id, requester_id, target_id,
                                score, overlap_pct, origin_distance_m, dest_distance_m, time_diff_min)
    values (p_my_trip, p_target_trip, v_uid, v_c.candidate_user_id,
            (round(v_c.score::numeric / 5.0) * 5), round(v_c.overlap_pct::numeric, 0),
            (round(v_c.origin_distance_m / 500.0) * 500)::int, (round(v_c.dest_distance_m / 500.0) * 500)::int,   -- SECURITY: bucketed (matches rows are client-readable)
            round(v_c.time_diff_min::numeric, 1))
    returning id into v_id;
  exception when unique_violation then
    raise exception 'GWM_ALREADY_REQUESTED' using errcode = 'P0001';   -- also covers the simultaneous-request race
  end;
  return v_id;
end $$;

create or replace function public.respond_match(p_match_id uuid, p_accept boolean,
    p_meet_lng double precision default null, p_meet_lat double precision default null, p_meet_label text default null)
returns public.match_status
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_uid uuid := auth.uid(); v_m public.matches%rowtype;
begin
  select * into v_m from public.matches where id = p_match_id and target_id = v_uid and status = 'pending' for update;
  if not found then raise exception 'GWM_MATCH_NOT_FOUND' using errcode = 'P0001'; end if;
  if not p_accept then
    update public.matches set status = 'declined', responded_at = now() where id = p_match_id;   -- no reason is stored/sent
    return 'declined';
  end if;
  perform public._accept_match(p_match_id);
  if p_meet_lng is not null and p_meet_lat is not null then
    update public.matches set meeting_point = ST_SetSRID(ST_MakePoint(p_meet_lng, p_meet_lat), 4326)::geography,
                              meeting_label = left(p_meet_label, 120)
     where id = p_match_id;
  end if;
  return 'accepted';
end $$;

create or replace function public.set_meeting_point(p_match_id uuid, p_lng double precision, p_lat double precision, p_label text default null)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  update public.matches set meeting_point = ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography, meeting_label = left(p_label, 120)
   where id = p_match_id and status = 'accepted' and auth.uid() in (requester_id, target_id);
  if not found then raise exception 'GWM_MATCH_NOT_FOUND' using errcode = 'P0001'; end if;
end $$;

create or replace function public.cancel_match(p_match_id uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old public.match_status;
begin
  select status into v_old from public.matches
   where id = p_match_id and status in ('pending','accepted') and auth.uid() in (requester_id, target_id) for update;
  if not found then raise exception 'GWM_MATCH_NOT_FOUND' using errcode = 'P0001'; end if;
  update public.matches set status = 'cancelled', responded_at = now() where id = p_match_id;
  if v_old = 'accepted' then
    insert into public.chat_messages (match_id, sender_id, kind, body) values (p_match_id, null, 'system', 'system.match_cancelled');
  end if;
end $$;

-- 11. Trip sharing (US-11) ------------------------------------------------------------
create or replace function public.create_trip_share(p_trip_id uuid, p_ttl_min int default null)
returns table (share_id uuid, token text, share_expires_at timestamptz)
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid(); v_token text; v_ttl int; v_id uuid; v_exp timestamptz;
begin
  if not exists (select 1 from public.trips t where t.id = p_trip_id and t.user_id = v_uid
                   and t.status in ('scheduled','in_progress') and t.deleted_at is null) then
    raise exception 'GWM_TRIP_NOT_FOUND' using errcode = 'P0001';
  end if;
  if (select count(*) from public.trip_shares s where s.trip_id = p_trip_id and s.revoked_at is null and s.expires_at > now()) >= 10 then
    raise exception 'GWM_SHARE_LIMIT' using errcode = 'P0001';
  end if;
  v_ttl := least(coalesce(p_ttl_min, public.cfg_num('share.default_ttl_min')::int), public.cfg_num('share.max_ttl_min')::int);
  v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');   -- 64 hex chars, ~244 random bits
  insert into public.trip_shares (trip_id, user_id, token_hash, expires_at)
  values (p_trip_id, v_uid, sha256(convert_to(v_token, 'utf8')), now() + v_ttl * interval '1 minute')
  returning id, expires_at into v_id, v_exp;
  return query select v_id, v_token, v_exp;            -- the raw token is never stored
end $$;

create or replace function public.revoke_trip_share(p_share_id uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update public.trip_shares set revoked_at = now() where id = p_share_id and user_id = auth.uid() and revoked_at is null;
end $$;

-- Public (anon) read of a shared trip. Exposes ONLY: display name, status, mode, times, approx destination,
-- latest position (while in_progress). No email/phone/chat/origin/labels. Expired/revoked/unknown => zero rows.
create or replace function public.get_shared_trip(p_token text)
returns table (display_name text, status public.trip_status, mode public.travel_mode, depart_at timestamptz, eta_at timestamptz,
               approx_dest_lat double precision, approx_dest_lng double precision,
               last_lat double precision, last_lng double precision, last_location_at timestamptz, ended_at timestamptz)
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
#variable_conflict use_column
declare v_share public.trip_shares%rowtype; v_trip public.trips%rowtype; v_name text;
begin
  if p_token is null or char_length(p_token) < 32 or char_length(p_token) > 128 then return; end if;
  select * into v_share from public.trip_shares s
   where s.token_hash = sha256(convert_to(p_token, 'utf8')) and s.revoked_at is null and s.expires_at > now();
  if not found then return; end if;
  select * into v_trip from public.trips where id = v_share.trip_id and deleted_at is null;
  if not found then return; end if;
  select p.display_name into v_name from public.profiles p where p.id = v_trip.user_id and p.deleted_at is null;
  if not found then return; end if;
  -- link "expires" when the trip ends: only the final status is visible for a short grace period, never a location
  if v_trip.status in ('completed','cancelled','expired')
     and v_trip.ended_at < now() - public.cfg_num('share.terminal_grace_min') * interval '1 minute' then return; end if;

  update public.trip_shares set last_viewed_at = now() where id = v_share.id;
  return query select v_name, v_trip.status, v_trip.mode, v_trip.depart_at,
         coalesce(v_trip.started_at, v_trip.depart_at) + v_trip.route_duration_s * interval '1 second',
         ST_Y(public.blur_point(v_trip.dest)::geometry), ST_X(public.blur_point(v_trip.dest)::geometry),
         case when v_trip.status = 'in_progress' then ST_Y(v_trip.last_location::geometry) end,
         case when v_trip.status = 'in_progress' then ST_X(v_trip.last_location::geometry) end,
         case when v_trip.status = 'in_progress' then v_trip.last_location_at end,
         v_trip.ended_at;
end $$;

-- 12. Verification (mock OTP), PDPA: export & deletion ---------------------------------
create or replace function public.verify_phone_mock(p_phone text, p_code text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'GWM_UNAUTHENTICATED' using errcode = '42501'; end if;
  if not public.cfg_bool('phone.mock_enabled') then raise exception 'GWM_PHONE_MOCK_DISABLED' using errcode = 'P0001'; end if;
  if p_code is distinct from (public.cfg('phone.mock_code') #>> '{}') or p_phone !~ '^\+[0-9]{8,15}$' then
    raise exception 'GWM_INVALID_CODE' using errcode = 'P0001';
  end if;
  insert into public.verifications (user_id, kind, status, phone_e164, is_mock, verified_at)
  values (auth.uid(), 'phone', 'verified', p_phone, true, now())
  on conflict (user_id, kind) do update set status = 'verified', phone_e164 = excluded.phone_e164, is_mock = true, verified_at = now();
end $$;

-- Withdrawal/grant helper keeps consent log append-only.
create or replace function public.record_consent(p_kind public.consent_kind, p_granted boolean, p_version text) returns void
language sql security definer set search_path = public, pg_temp as $$
  insert into public.consents (user_id, kind, granted, policy_version) values (auth.uid(), p_kind, p_granted, p_version)
$$;

create or replace function public.export_my_data() returns jsonb
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select jsonb_build_object(
    'profile',  (select to_jsonb(p) from public.profiles p where p.id = auth.uid()),
    'consents', coalesce((select jsonb_agg(to_jsonb(c)) from public.consents c where c.user_id = auth.uid()), '[]'),
    'verifications', coalesce((select jsonb_agg(to_jsonb(v)) from public.verifications v where v.user_id = auth.uid()), '[]'),
    'emergency_contacts', coalesce((select jsonb_agg(to_jsonb(e)) from public.emergency_contacts e where e.user_id = auth.uid()), '[]'),
    'trips', coalesce((select jsonb_agg(to_jsonb(t) - 'origin' - 'dest' - 'route' - 'last_location'
                 || jsonb_build_object('origin', ST_AsGeoJSON(t.origin::geometry)::jsonb, 'dest', ST_AsGeoJSON(t.dest::geometry)::jsonb,
                                       'route', ST_AsGeoJSON(t.route::geometry)::jsonb))
                 from public.trips t where t.user_id = auth.uid()), '[]'),
    'sos_events', coalesce((select jsonb_agg(to_jsonb(s) - 'location' || jsonb_build_object('location', ST_AsGeoJSON(s.location::geometry)::jsonb))
                 from public.sos_events s where s.user_id = auth.uid()), '[]'),
    'messages_sent', coalesce((select jsonb_agg(to_jsonb(m)) from public.chat_messages m where m.sender_id = auth.uid()), '[]'))
$$;

-- Account deletion: immediate anonymisation + cancel/close everything; hard delete after retention (purge job).
create or replace function public.request_account_deletion() returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'GWM_UNAUTHENTICATED' using errcode = '42501'; end if;
  update public.trips set status = 'cancelled' where user_id = v_uid and status in ('scheduled','in_progress');
  update public.trips set deleted_at = now() where user_id = v_uid and deleted_at is null;
  update public.matches set status = 'cancelled', responded_at = now()
   where status in ('pending','accepted') and v_uid in (requester_id, target_id);
  update public.trip_shares set revoked_at = now() where user_id = v_uid and revoked_at is null;
  delete from public.trip_locations where user_id = v_uid;
  delete from public.emergency_contacts where user_id = v_uid;
  update public.profiles set deleted_at = now(), display_name = 'ผู้ใช้ที่ลบบัญชีแล้ว', avatar_path = null where id = v_uid;
end $$;

-- 13. Scheduled maintenance (retention, expiry, hard delete) ------------------------------
create or replace function public.purge_expired_data() returns jsonb
language plpgsql security definer set search_path = public, extensions, auth, pg_temp as $$
declare
  v_loc_days int := public.cfg_num('retention.location_days')::int;
  v_del_days int := public.cfg_num('retention.account_deletion_days')::int;
  v_expired int; v_loc int; v_reduced int; v_trips int; v_users int;
begin
  -- called by cron / service_role only => auth.uid() is null => trips_guard allows the 'expired' transition
  update public.trips set status = 'expired'
   where status = 'scheduled' and depart_at < now() - public.cfg_num('trip.expire_after_min') * interval '1 minute';
  get diagnostics v_expired = row_count;

  delete from public.trip_locations tl using public.trips t
   where t.id = tl.trip_id and (t.deleted_at is not null or t.ended_at < now() - v_loc_days * interval '1 day');
  get diagnostics v_loc = row_count;

  update public.trips set origin = public.blur_point(origin), dest = public.blur_point(dest),
         route = ST_MakeLine(public.blur_point(origin)::geometry, public.blur_point(dest)::geometry)::geography,
         origin_label = null, dest_label = null, last_location = null, last_location_at = null, precision_reduced_at = now()
   where ended_at < now() - v_loc_days * interval '1 day' and precision_reduced_at is null;
  get diagnostics v_reduced = row_count;

  delete from public.trips where deleted_at < now() - v_loc_days * interval '1 day';
  get diagnostics v_trips = row_count;

  delete from public.trip_shares where expires_at < now() - interval '30 days' or revoked_at < now() - interval '30 days';

  delete from auth.users u using public.profiles p                       -- cascades to every user-owned row
   where p.id = u.id and p.deleted_at < now() - v_del_days * interval '1 day';
  get diagnostics v_users = row_count;

  return jsonb_build_object('expired_trips', v_expired, 'deleted_locations', v_loc, 'reduced_trips', v_reduced,
                            'deleted_trips', v_trips, 'deleted_users', v_users);
end $$;

-- 14. Row Level Security ----------------------------------------------------------------
alter table public.app_config          enable row level security;
alter table public.org_domains         enable row level security;
alter table public.profiles            enable row level security;
alter table public.consents            enable row level security;
alter table public.verifications       enable row level security;
alter table public.emergency_contacts  enable row level security;
alter table public.trips               enable row level security;
alter table public.trip_locations      enable row level security;
alter table public.matches             enable row level security;
alter table public.chat_messages       enable row level security;
alter table public.blocks              enable row level security;
alter table public.reports             enable row level security;
alter table public.sos_events          enable row level security;
alter table public.trip_shares         enable row level security;

-- app_config: public rows readable; writes only via service_role/SQL editor (bypasses RLS)
drop policy if exists app_config_read_public on public.app_config;
create policy app_config_read_public on public.app_config for select to authenticated using (is_public);

drop policy if exists org_domains_read on public.org_domains;
create policy org_domains_read on public.org_domains for select to authenticated using (is_active);

-- profiles: self, matched partner, admin. Non-matched users see name/badges only through find_matches().
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using (id = (select auth.uid()) or public.are_matched((select auth.uid()), id) or public.is_admin());
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = (select auth.uid()) and deleted_at is null) with check (id = (select auth.uid()));

drop policy if exists consents_select_own on public.consents;
create policy consents_select_own on public.consents for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists consents_insert_own on public.consents;
create policy consents_insert_own on public.consents for insert to authenticated with check (user_id = (select auth.uid()));

drop policy if exists verifications_select on public.verifications;
create policy verifications_select on public.verifications for select to authenticated
  using (user_id = (select auth.uid()) or public.are_matched((select auth.uid()), user_id) or public.is_admin());

drop policy if exists emergency_contacts_select_own on public.emergency_contacts;
create policy emergency_contacts_select_own on public.emergency_contacts for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists emergency_contacts_insert_own on public.emergency_contacts;
create policy emergency_contacts_insert_own on public.emergency_contacts for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists emergency_contacts_update_own on public.emergency_contacts;
create policy emergency_contacts_update_own on public.emergency_contacts for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
drop policy if exists emergency_contacts_delete_own on public.emergency_contacts;
create policy emergency_contacts_delete_own on public.emergency_contacts for delete to authenticated using (user_id = (select auth.uid()));

-- trips: OWNER ONLY (exact geometry never readable by anyone else, not even matched partners or admins).
drop policy if exists trips_select_own on public.trips;
create policy trips_select_own on public.trips for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists trips_insert_own on public.trips;
create policy trips_insert_own on public.trips for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists trips_update_own on public.trips;
create policy trips_update_own on public.trips for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
-- no DELETE policy: users soft-delete (deleted_at) after the trip is terminal.

drop policy if exists trip_locations_select_own on public.trip_locations;
create policy trip_locations_select_own on public.trip_locations for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists trip_locations_insert_own on public.trip_locations;
create policy trip_locations_insert_own on public.trip_locations for insert to authenticated
  with check (user_id = (select auth.uid()) and public.is_own_trip_in_progress(trip_id) and public.has_location_consent());

-- matches: participants read; all writes through RPCs.
drop policy if exists matches_select_participant on public.matches;
create policy matches_select_participant on public.matches for select to authenticated
  using ((select auth.uid()) in (requester_id, target_id));

drop policy if exists chat_select_participant on public.chat_messages;
create policy chat_select_participant on public.chat_messages for select to authenticated
  using (exists (select 1 from public.matches m where m.id = chat_messages.match_id
                   and (select auth.uid()) in (m.requester_id, m.target_id)));
drop policy if exists chat_insert_when_open on public.chat_messages;
create policy chat_insert_when_open on public.chat_messages for insert to authenticated
  with check (sender_id = (select auth.uid()) and kind = 'user' and public.is_chat_open(match_id));

drop policy if exists blocks_select_own on public.blocks;
create policy blocks_select_own on public.blocks for select to authenticated using (blocker_id = (select auth.uid()));
drop policy if exists blocks_insert_own on public.blocks;
create policy blocks_insert_own on public.blocks for insert to authenticated with check (blocker_id = (select auth.uid()));
drop policy if exists blocks_delete_own on public.blocks;
create policy blocks_delete_own on public.blocks for delete to authenticated using (blocker_id = (select auth.uid()));

drop policy if exists reports_select on public.reports;
create policy reports_select on public.reports for select to authenticated using (reporter_id = (select auth.uid()) or public.is_admin());
drop policy if exists reports_insert_own on public.reports;
create policy reports_insert_own on public.reports for insert to authenticated
  with check (reporter_id = (select auth.uid())
              -- SECURITY: match_id must be a match the reporter is in, and reported user must be the counter-party
              and (match_id is null or exists (select 1 from public.matches m
                     where m.id = match_id
                       and ((m.requester_id = reporter_id and m.target_id = reported_user_id)
                         or (m.target_id = reporter_id and m.requester_id = reported_user_id)))));

drop policy if exists sos_select on public.sos_events;
create policy sos_select on public.sos_events for select to authenticated using (user_id = (select auth.uid()) or public.is_admin());
drop policy if exists sos_insert_own on public.sos_events;
create policy sos_insert_own on public.sos_events for insert to authenticated
  with check (user_id = (select auth.uid())
              and (trip_id is null or exists (select 1 from public.trips t where t.id = trip_id and t.user_id = (select auth.uid()))));

drop policy if exists trip_shares_select_own on public.trip_shares;
create policy trip_shares_select_own on public.trip_shares for select to authenticated using (user_id = (select auth.uid()));
-- inserts/revocation only via create_trip_share / revoke_trip_share; anon reads only via get_shared_trip.

-- 15. Grants (least privilege on top of RLS) ----------------------------------------------
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;

revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke execute on all functions in schema public from public, anon, authenticated;

grant usage on schema public to anon, authenticated;

grant select on public.app_config, public.org_domains, public.profiles, public.consents, public.verifications,
                public.emergency_contacts, public.trips, public.trip_locations, public.matches, public.chat_messages,
                public.blocks, public.reports, public.sos_events, public.trip_shares to authenticated;
grant insert (user_id, kind, granted, policy_version) on public.consents to authenticated;   -- SECURITY: no client-set id/created_at (forged consent timestamps)
grant insert (user_id, name, phone) on public.emergency_contacts to authenticated;
grant update (name, phone)          on public.emergency_contacts to authenticated;
grant delete on public.emergency_contacts to authenticated;
grant update (display_name, avatar_path, locale, adult_confirmed_at) on public.profiles to authenticated;
grant insert (user_id, mode, origin, origin_label, dest, dest_label, route, route_distance_m, route_duration_s, depart_at)
  on public.trips to authenticated;
grant update (mode, status, origin, origin_label, dest, dest_label, route, route_distance_m, route_duration_s, depart_at, deleted_at)
  on public.trips to authenticated;
grant insert (trip_id, user_id, location, accuracy_m) on public.trip_locations to authenticated;
grant insert (match_id, sender_id, body, client_msg_id) on public.chat_messages to authenticated;
grant insert (blocker_id, blocked_id) on public.blocks to authenticated;
grant delete on public.blocks to authenticated;
grant insert (reporter_id, reported_user_id, match_id, reason, details) on public.reports to authenticated;
grant insert (user_id, trip_id, source, location, note, client_created_at) on public.sos_events to authenticated;

-- policy helpers must be callable by the invoker while RLS is evaluated
grant execute on function public.is_admin(), public.are_matched(uuid, uuid), public.is_chat_open(uuid),
                          public.is_own_trip_in_progress(uuid), public.has_location_consent() to authenticated;
-- RPC surface for the app
grant execute on function public.find_matches(uuid, int), public.get_trip_card(uuid), public.get_partner_live_location(uuid),
                          public.request_match(uuid, uuid),
                          public.respond_match(uuid, boolean, double precision, double precision, text),
                          public.set_meeting_point(uuid, double precision, double precision, text),
                          public.cancel_match(uuid),
                          public.create_trip_share(uuid, int), public.revoke_trip_share(uuid),
                          public.verify_phone_mock(text, text), public.record_consent(public.consent_kind, boolean, text),
                          public.export_my_data(), public.request_account_deletion() to authenticated;
grant execute on function public.get_shared_trip(text) to anon, authenticated;   -- token-gated public page
-- NOT granted (internal): cfg*, blur_point, match_candidates, _accept_match, sync_user_verifications, purge_expired_data, trigger fns.
grant execute on function public.purge_expired_data() to service_role;

-- 16. Realtime (chat + match status; RLS is applied to change events) -----------------------
do $$
declare t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['chat_messages','matches'] loop
      if not exists (select 1 from pg_publication_tables
                      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end $$;

-- 17. Storage: private `avatars` bucket, path "<user_id>/<file>" ---------------------------------
do $do$
begin
  if to_regclass('storage.buckets') is not null then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('avatars', 'avatars', false, 2097152, array['image/jpeg','image/png','image/webp'])
    on conflict (id) do update set public = false, file_size_limit = 2097152,
                                   allowed_mime_types = array['image/jpeg','image/png','image/webp'];

    drop policy if exists avatars_read_own_or_partner on storage.objects;
    create policy avatars_read_own_or_partner on storage.objects for select to authenticated
      using (bucket_id = 'avatars' and (
               (storage.foldername(name))[1] = (select auth.uid())::text
            or public.are_matched((select auth.uid()), public.safe_uuid((storage.foldername(name))[1]))));
    drop policy if exists avatars_write_own on storage.objects;
    create policy avatars_write_own on storage.objects for insert to authenticated
      with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
    drop policy if exists avatars_update_own on storage.objects;
    create policy avatars_update_own on storage.objects for update to authenticated
      using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text)
      with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
    drop policy if exists avatars_delete_own on storage.objects;
    create policy avatars_delete_own on storage.objects for delete to authenticated
      using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
  end if;
end $do$;
grant execute on function public.safe_uuid(text) to authenticated;

-- 18. Cron (optional: skipped with a NOTICE if pg_cron is unavailable) ---------------------------
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron with schema pg_catalog;
    perform cron.schedule('gwm-purge-expired-data', '*/15 * * * *', 'select public.purge_expired_data()');
  else
    raise notice 'pg_cron not available: schedule public.purge_expired_data() externally (e.g. Edge Function cron)';
  end if;
exception when others then
  raise notice 'pg_cron setup skipped: %', sqlerrm;
end $$;

notify pgrst, 'reload schema';
