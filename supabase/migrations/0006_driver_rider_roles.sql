-- =============================================================================
-- GOWITHME migration 0006: Driver/Rider roles for mode = 'car' (requirements US-16..18, docs/design-roles.md)
-- DRAFT: NOT applied to any remote project. Idempotent (safe to re-run). Run after 0001-0005.
--   * trips.role (driver|rider) only for mode = car; driver seats are a constant (1) - no seat column
--   * vehicles (plate/model/color, consent flag) with RLS: owner + accepted partner only
--   * match_candidates: car = Driver<->Rider only, overlap measured on the RIDER route, 1 accepted per trip
--   * _accept_match auto-cancels the other pending requests of both car trips
--   * matches.boarded_at, match_outcomes (internal reason), report_rider_no_show, mark_boarded
--   * pickup deviation = SOFT warning only (match.pickup_max_deviation_m; never rejected), live location rule after boarding
--   * plate-only share/SOS payload, gated by the Driver's share-consent switch (default OFF, vehicles.share_consent_at)
--   * hard race guard: partial unique indexes = max 1 accepted match per driver trip and per rider trip
-- Non-car behaviour (walk/transit/taxi) is unchanged.
-- =============================================================================
set search_path = public, extensions;

-- 1. Enum + column ------------------------------------------------------------------------
do $$ begin create type public.trip_role as enum ('driver','rider'); exception when duplicate_object then null; end $$;

alter table public.trips add column if not exists role public.trip_role;

do $$ begin
  alter table public.trips add constraint trips_role_only_car check (role is null or mode = 'car');
exception when duplicate_object then null; end $$;
-- NOTE: "mode = car => role not null" is enforced by trigger trg_trips_role_guard on INSERT only, not by a CHECK:
-- legacy dev rows (car, role null) must stay updatable (cancel/complete) but are never matched (match_candidates).

-- 2. Config (all tunables in app_config, ON CONFLICT DO NOTHING) -------------------------------
insert into public.app_config (key, value, description, is_public) values
  ('match.pickup_max_deviation_m',     '500', 'US-18/R3-2: pickup point farther than this from the Driver route triggers a WARNING only (m)', true),
  ('roles.pickup_proposals_per_hour',  '10',  'SECURITY: max pickup proposals per user per match per hour (route-probing oracle)', false),
  ('throttle.vehicle_write_per_hour',  '10',  'per-user upsert/delete vehicle calls per hour', false),
  ('throttle.match_state_per_min',     '20',  'per-user cancel_match / mark_boarded / report_rider_no_show calls per minute', false),
  ('retention.match_outcome_months',   '12',  'PM decision: internal match_outcomes rows are deleted by purge_expired_data after this many months', false)
on conflict (key) do nothing;

-- Driver seats are FIXED (user decision, round 3): a constant, deliberately not a config value or a column.
create or replace function public.car_seats() returns int
language sql immutable set search_path = public, pg_temp as $$ select 1 $$;

-- 3. matches: pickup state + internal outcome table --------------------------------------------
alter table public.matches add column if not exists boarded_at timestamptz;      -- set by the Rider ("ขึ้นรถแล้ว")
-- Role-resolved trip ids of a CAR match (NULL for non-car / legacy). Filled by trigger; with the partial unique indexes below
-- they are the LAST line of defence: at most 1 accepted match per Driver trip and per Rider trip, even if a code path races.
alter table public.matches add column if not exists driver_trip_id uuid references public.trips(id) on delete cascade;
alter table public.matches add column if not exists rider_trip_id  uuid references public.trips(id) on delete cascade;
create unique index if not exists matches_one_accepted_per_driver_trip on public.matches (driver_trip_id) where status = 'accepted' and driver_trip_id is not null;
create unique index if not exists matches_one_accepted_per_rider_trip  on public.matches (rider_trip_id)  where status = 'accepted' and rider_trip_id  is not null;
create index if not exists matches_driver_trip_idx on public.matches (driver_trip_id) where driver_trip_id is not null;
create index if not exists matches_rider_trip_idx  on public.matches (rider_trip_id)  where rider_trip_id  is not null;

create or replace function public.matches_set_car_roles() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_r public.trips%rowtype; v_t public.trips%rowtype;
begin
  select * into v_r from public.trips where id = new.requester_trip_id;
  select * into v_t from public.trips where id = new.target_trip_id;
  if v_r.mode = 'car' and v_t.mode = 'car' and v_r.role is not null and v_t.role is not null and v_r.role <> v_t.role then
    new.driver_trip_id := case when v_r.role = 'driver' then v_r.id else v_t.id end;
    new.rider_trip_id  := case when v_r.role = 'rider'  then v_r.id else v_t.id end;
  else
    new.driver_trip_id := null; new.rider_trip_id := null;
  end if;
  return new;
end $$;
drop trigger if exists trg_matches_set_car_roles on public.matches;
create trigger trg_matches_set_car_roles before insert on public.matches
  for each row execute function public.matches_set_car_roles();

-- true = a PENDING request closed automatically because one of the two car trips got its accepted match (US-16/US-18).
-- Such a pair may send a fresh request later (request_match removes the stale row); a manual cancel/decline may not.
alter table public.matches add column if not exists auto_closed boolean not null default false;

-- Internal reason for an ended car match (cancel / no-show). NOT client-readable (no grant, RLS on, no policy):
-- the other party must never learn that they were reported as a no-show (US-18).
create table if not exists public.match_outcomes (
  match_id   uuid primary key references public.matches(id) on delete cascade,
  reason     text not null check (reason in ('cancelled_by_driver','cancelled_by_rider','rider_no_show','trip_ended','trip_expired')),
  actor_id   uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.match_outcomes enable row level security;
revoke all on public.match_outcomes from anon, authenticated;
create index if not exists match_outcomes_actor_idx on public.match_outcomes (actor_id) where actor_id is not null;

-- 4. vehicles -----------------------------------------------------------------------------------
create table if not exists public.vehicles (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles(id) on delete cascade,
  plate           text not null check (char_length(plate) between 1 and 15 and plate !~ '[[:cntrl:]]'),
  model           text not null check (char_length(model) between 1 and 60 and model !~ '[[:cntrl:]]'),
  color           text not null check (char_length(color) between 1 and 30 and color !~ '[[:cntrl:]]'),
  share_consent_at timestamptz,                         -- R3-1: NULL = OFF (default). Set/cleared only by set_vehicle_share_consent()
  verified_at     timestamptz,                          -- P1 extension point (license/plate verification); NULL = self-declared
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
-- MVP: one vehicle per user. Named so that a later multi-vehicle release can simply drop this index.
create unique index if not exists vehicles_user_uq on public.vehicles (user_id);

drop trigger if exists trg_vehicles_updated_at on public.vehicles;
create trigger trg_vehicles_updated_at before update on public.vehicles
  for each row execute function public.update_updated_at();

alter table public.vehicles enable row level security;

-- Q-2: once the Rider has boarded, access no longer depends on the match/Driver trip: it lasts until the Rider's OWN trip ended + 24 h.
-- Visible to the Rider of an ACCEPTED car match with this Driver (either requester/target direction), while both trips
-- are active or ended < 24 h ago (same window as are_matched) and nobody blocked anybody. Cancel/no-show => match no
-- longer 'accepted' => access ends immediately.
create or replace function public.can_view_vehicle(p_owner uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1
    from public.matches m
    join public.trips td on td.id = case when m.requester_id = p_owner then m.requester_trip_id else m.target_trip_id end
    join public.trips tr on tr.id = case when m.requester_id = p_owner then m.target_trip_id else m.requester_trip_id end
    where (m.status = 'accepted' or (m.status = 'cancelled' and m.boarded_at is not null))   -- Q-2: a BOARDED rider keeps the view
      and ((m.requester_id = p_owner and m.target_id = auth.uid()) or (m.target_id = p_owner and m.requester_id = auth.uid()))
      and td.user_id = p_owner and td.role = 'driver'
      and tr.user_id = auth.uid() and tr.role = 'rider'
      and (td.status in ('scheduled','in_progress') or td.ended_at > now() - interval '24 hours' or m.boarded_at is not null)
      and (tr.status in ('scheduled','in_progress') or tr.ended_at > now() - interval '24 hours')   -- ends with the RIDER's own trip (+24 h)
      and not exists (select 1 from public.blocks b
                       where (b.blocker_id = p_owner and b.blocked_id = auth.uid())
                          or (b.blocker_id = auth.uid() and b.blocked_id = p_owner)))
$$;

drop policy if exists vehicles_select on public.vehicles;
create policy vehicles_select on public.vehicles for select to authenticated
  using (user_id = (select auth.uid()) or public.can_view_vehicle(user_id));
-- no INSERT/UPDATE/DELETE policy and no write grant: only upsert_my_vehicle / delete_my_vehicle (validation + consent)

-- 5. Triggers -------------------------------------------------------------------------------------
-- 5a. trips: role rules. Separate trigger (fires after trg_trips_guard; not reached on the idempotent-retry no-op).
create or replace function public.trips_role_guard() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if tg_op = 'INSERT' then
    if new.mode = 'car' then
      if new.role is null then raise exception 'GWM_ROLE_REQUIRED' using errcode = 'P0001'; end if;
      if new.role = 'driver' and not exists (select 1 from public.vehicles v where v.user_id = new.user_id) then
        raise exception 'GWM_VEHICLE_REQUIRED' using errcode = 'P0001';
      end if;
    elsif new.role is not null then
      raise exception 'GWM_ROLE_NOT_ALLOWED' using errcode = 'P0001';
    end if;
    return new;
  end if;
  -- UPDATE by a client: role never changes; mode cannot move into or out of car (role is bound to the car mode)
  if auth.uid() is not null then
    if new.role is distinct from old.role
       or (new.mode is distinct from old.mode and (old.mode = 'car' or new.mode = 'car')) then
      raise exception 'GWM_ROLE_IMMUTABLE' using errcode = 'P0001';
    end if;
    -- Q-1: a Driver cannot cancel the trip once the Rider of the accepted match boarded (finish with "arrived" instead)
    if new.status = 'cancelled' and old.status is distinct from 'cancelled' and old.role = 'driver'
       and exists (select 1 from public.matches m
                    where m.driver_trip_id = new.id and m.status = 'accepted' and m.boarded_at is not null) then
      raise exception 'GWM_ALREADY_BOARDED' using errcode = 'P0001';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_trips_role_guard on public.trips;
create trigger trg_trips_role_guard before insert or update on public.trips
  for each row execute function public.trips_role_guard();

-- 5b. car trip cancelled/expired => its accepted match ends (match stays 'accepted' otherwise: are_matched only looks at
-- trip status). Fires after trg_trips_after_status (alphabetical), which already posted 'system.trip_<status>'.
create or replace function public.trips_after_status_roles() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if new.mode = 'car' and new.status in ('cancelled','expired') then
    with c as (
      update public.matches set status = 'cancelled', responded_at = now()
       where status = 'accepted' and new.id in (requester_trip_id, target_trip_id)
         and not (new.status = 'expired' and boarded_at is not null)      -- Q-1/Q-8: expiry never closes a boarded match
      returning id)
    insert into public.match_outcomes (match_id, reason, actor_id)
    select c.id,
           case when new.status = 'expired' then 'trip_expired'
                when new.role = 'driver' then 'cancelled_by_driver'
                when new.role = 'rider' then 'cancelled_by_rider'
                else 'trip_ended' end,
           case when new.status = 'expired' then null else new.user_id end
      from c
    on conflict (match_id) do nothing;
  end if;
  return null;
end $$;
drop trigger if exists trg_trips_after_status_roles on public.trips;
create trigger trg_trips_after_status_roles after update of status on public.trips
  for each row when (old.status is distinct from new.status) execute function public.trips_after_status_roles();

-- 5c. vehicle cannot be deleted by a client while a Driver trip is active (trip must always show a vehicle to the Rider)
create or replace function public.vehicles_delete_guard() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is not null and exists (
       select 1 from public.trips t
        where t.user_id = old.user_id and t.role = 'driver' and t.status in ('scheduled','in_progress') and t.deleted_at is null) then
    raise exception 'GWM_VEHICLE_IN_USE' using errcode = 'P0001';
  end if;
  return old;
end $$;
drop trigger if exists trg_vehicles_delete_guard on public.vehicles;
create trigger trg_vehicles_delete_guard before delete on public.vehicles
  for each row execute function public.vehicles_delete_guard();

-- 5d. soft account deletion (request_account_deletion sets profiles.deleted_at) => vehicle data erased immediately
-- (trips are already cancelled at that point). Hard delete is covered by ON DELETE CASCADE.
create or replace function public.profiles_delete_vehicle() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  delete from public.vehicles where user_id = new.id;
  return null;
end $$;
drop trigger if exists trg_profiles_delete_vehicle on public.profiles;
create trigger trg_profiles_delete_vehicle after update of deleted_at on public.profiles
  for each row when (new.deleted_at is not null and old.deleted_at is null) execute function public.profiles_delete_vehicle();

-- 6. Geometry helpers -------------------------------------------------------------------------------
-- Directional coverage: % of p_covered's length lying within p_buffer_m of p_by. For car: covered = RIDER route, by = DRIVER route.
create or replace function public.route_coverage_pct(p_covered geography, p_by geography, p_buffer_m double precision)
returns double precision language sql stable set search_path = public, extensions, pg_temp as $$
  select least(100.0, coalesce(
    100.0 * ST_Length(ST_Intersection(p_covered, ST_Buffer(p_by, p_buffer_m))) / nullif(ST_Length(p_covered), 0), 0))
$$;

-- R3-2: SOFT check. TRUE = the point is farther than match.pickup_max_deviation_m from the Driver's route (warn only).
-- Returns a boolean, never the distance (a distance would let a Rider map the Driver's exact route). Internal (no grant).
create or replace function public._pickup_beyond_limit(p_driver_trip uuid, p_lng double precision, p_lat double precision) returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select coalesce(ST_Distance(ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography, t.route)
                    > public.cfg_num('match.pickup_max_deviation_m'), false)
    from public.trips t where t.id = p_driver_trip
$$;

-- 7. match_candidates (same signature/return as 0005) ---------------------------------------------------
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
  v_cutoff timestamptz      := now() - public.cfg_num('trip.expire_after_min') * interval '1 minute';
  v_lim    int;
begin
  select * into v_t from public.trips where id = p_trip_id and deleted_at is null;
  if not found or v_t.status <> 'scheduled' or v_t.depart_at <= v_cutoff then return; end if;
  -- car: role is mandatory (legacy role-less car trips are never matched); accepted limit is the constant car_seats() (1)
  if v_t.mode = 'car' and v_t.role is null then return; end if;
  v_lim := case when v_t.mode = 'car' then public.car_seats() else v_max end;
  if (select count(*) from public.matches m where m.status = 'accepted'
        and v_t.id in (m.requester_trip_id, m.target_trip_id)) >= v_lim then return; end if;

  return query
  with cand as (
    select o.id as tid, o.user_id as uid, o.route as route,
           ST_Distance(o.origin, v_t.origin) as d_o,
           ST_Distance(o.dest,   v_t.dest)   as d_d,
           (abs(extract(epoch from (o.depart_at - v_t.depart_at))) / 60.0)::double precision as dt
      from public.trips o
      join public.profiles p on p.id = o.user_id and p.deleted_at is null
     where o.status = 'scheduled' and o.deleted_at is null
       and o.depart_at > v_cutoff
       and o.user_id <> v_t.user_id
       and (p_only_trip is null or o.id = p_only_trip)
       and ST_DWithin(o.origin, v_t.origin, v_r_o)
       and ST_DWithin(o.dest,   v_t.dest,   v_r_d)
       and o.depart_at between v_t.depart_at - v_win * interval '1 minute'
                           and v_t.depart_at + v_win * interval '1 minute'
       and case when v_t.mode = 'car'
                then o.mode = 'car' and o.role is not null and o.role <> v_t.role          -- Driver<->Rider only
                else o.mode <> 'car' and (v_compat -> v_t.mode::text) @> to_jsonb(o.mode::text)
           end
       and not exists (select 1 from public.blocks b
                        where (b.blocker_id = v_t.user_id and b.blocked_id = o.user_id)
                           or (b.blocker_id = o.user_id  and b.blocked_id = v_t.user_id))
       and not exists (select 1 from public.matches m              -- only a still-pending pair stays visible (=> no re-request after cancel)
                        where m.status <> 'pending' and not (m.status = 'cancelled' and m.auto_closed)   -- auto-closed pending: may re-request
                          and ((m.requester_trip_id = v_t.id and m.target_trip_id = o.id)
                            or (m.requester_trip_id = o.id  and m.target_trip_id = v_t.id)))
       and (select count(*) from public.matches m where m.status = 'accepted'
              and o.id in (m.requester_trip_id, m.target_trip_id)) < v_lim   -- accepted Driver / Rider hidden
  ), scored as (
    select c.tid, c.uid, c.d_o, c.d_d, c.dt,
           case when v_t.mode = 'car' then
                  case when v_t.role = 'rider' then public.route_coverage_pct(v_t.route, c.route, v_buf)   -- my (rider) route covered by driver
                       else public.route_coverage_pct(c.route, v_t.route, v_buf) end                        -- candidate (rider) route covered by me
                else public.route_overlap_pct(v_t.route, c.route, v_buf) end as ov
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
revoke execute on function public.match_candidates(uuid, int, uuid) from public, anon, authenticated;

-- 8. find_matches / get_trip_card: add `role` (return type changes => drop + create) -----------------------
drop function if exists public.find_matches(uuid, int);
create function public.find_matches(p_trip_id uuid, p_limit int default 20)
returns table (trip_id uuid, display_name text, badges jsonb, mode public.travel_mode, depart_at timestamptz,
               time_diff_min int, overlap_pct int, approx_distance_m int, score numeric,
               approx_origin_lat double precision, approx_origin_lng double precision,
               approx_dest_lat double precision, approx_dest_lng double precision,
               request_status public.match_status, role public.trip_role)
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
#variable_conflict use_column
begin
  perform public._throttle('find_matches', public.cfg_num('throttle.find_matches_per_min')::int, 60);
  p_limit := least(greatest(coalesce(p_limit, 20), 1), 50);
  if not exists (select 1 from public.trips t where t.id = p_trip_id and t.user_id = auth.uid() and t.deleted_at is null) then
    raise exception 'GWM_TRIP_NOT_FOUND' using errcode = '42501';
  end if;
  return query
  select o.id, pr.display_name, public.user_badges(o.user_id), o.mode, o.depart_at,
         round(c.time_diff_min)::int, round(c.overlap_pct)::int,
         (greatest(1, round(c.origin_distance_m / 500.0)) * 500)::int,
         (round(c.score::numeric / 5.0) * 5)::numeric,
         ST_Y(public.blur_point(o.origin)::geometry), ST_X(public.blur_point(o.origin)::geometry),
         ST_Y(public.blur_point(o.dest)::geometry),   ST_X(public.blur_point(o.dest)::geometry),
         (select case when m.auto_closed then null else m.status end from public.matches m
           where (m.requester_trip_id = p_trip_id and m.target_trip_id = o.id)
              or (m.requester_trip_id = o.id and m.target_trip_id = p_trip_id) limit 1),
         o.role
    from public.match_candidates(p_trip_id, p_limit) c
    join public.trips o     on o.id  = c.candidate_trip_id
    join public.profiles pr on pr.id = c.candidate_user_id
   order by c.score desc, o.id;
end $$;

drop function if exists public.get_trip_card(uuid);
create function public.get_trip_card(p_trip_id uuid)
returns table (trip_id uuid, display_name text, badges jsonb, mode public.travel_mode, depart_at timestamptz, status public.trip_status,
               approx_origin_lat double precision, approx_origin_lng double precision,
               approx_dest_lat double precision, approx_dest_lng double precision, role public.trip_role)
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
         ST_Y(public.blur_point(t.dest)::geometry),   ST_X(public.blur_point(t.dest)::geometry),
         t.role
    from public.trips t join public.profiles pr on pr.id = t.user_id
   where t.id = p_trip_id;
end $$;

-- 9. Match lifecycle -------------------------------------------------------------------------------------
-- request_match: 0002 body + ONE change: a stale AUTO-CLOSED pair row is removed first so the pair can request again.
-- Role/mode eligibility ("either side may request", Driver<->Rider only) comes from match_candidates; "no re-request after
-- a manual cancel/decline" comes from match_candidates + v_dup/v_rev below + the unordered-pair unique index.
create or replace function public.request_match(p_my_trip uuid, p_target_trip uuid) returns uuid
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare
  v_uid uuid := auth.uid(); v_me public.trips%rowtype; v_c record;
  v_rev public.matches%rowtype; v_dup public.matches%rowtype; v_id uuid;
begin
  if v_uid is null then raise exception 'GWM_UNAUTHENTICATED' using errcode = '42501'; end if;
  perform public._throttle('request_match', public.cfg_num('throttle.request_match_per_min')::int, 60);

  if public.cfg_bool('auth.require_verified_email')
     and not exists (select 1 from public.verifications v where v.user_id = v_uid and v.kind = 'email' and v.status = 'verified') then
    raise exception 'GWM_EMAIL_NOT_VERIFIED' using errcode = 'P0001';
  end if;

  select * into v_me from public.trips where id = p_my_trip and user_id = v_uid and deleted_at is null for update;
  if not found or v_me.status <> 'scheduled' then raise exception 'GWM_TRIP_NOT_FOUND' using errcode = 'P0001'; end if;

  delete from public.matches m                                   -- NEW (0006): only rows closed by the auto-cancel rule
   where m.status = 'cancelled' and m.auto_closed
     and ((m.requester_trip_id = p_my_trip and m.target_trip_id = p_target_trip)
       or (m.requester_trip_id = p_target_trip and m.target_trip_id = p_my_trip));

  select * into v_dup from public.matches
   where requester_trip_id = p_my_trip and target_trip_id = p_target_trip and requester_id = v_uid;
  if found then
    if v_dup.status in ('pending','accepted') then return v_dup.id; end if;
    raise exception 'GWM_ALREADY_REQUESTED' using errcode = 'P0001';
  end if;

  select * into v_c from public.match_candidates(p_my_trip, 1, p_target_trip);   -- re-check eligibility server-side
  if not found then raise exception 'GWM_NOT_ELIGIBLE' using errcode = 'P0001'; end if;

  select * into v_rev from public.matches where requester_trip_id = p_target_trip and target_trip_id = p_my_trip for update;
  if found then
    if v_rev.status = 'pending' then perform public._accept_match(v_rev.id); return v_rev.id; end if;
    raise exception 'GWM_ALREADY_EXISTS' using errcode = 'P0001';
  end if;

  if (select count(*) from public.matches m where m.requester_trip_id = p_my_trip and m.status = 'pending')
       >= public.cfg_num('match.max_pending_per_trip')::int then
    raise exception 'GWM_PENDING_LIMIT' using errcode = 'P0001';
  end if;

  begin
    insert into public.matches (requester_trip_id, target_trip_id, requester_id, target_id,
                                score, overlap_pct, origin_distance_m, dest_distance_m, time_diff_min)
    values (p_my_trip, p_target_trip, v_uid, v_c.candidate_user_id,
            (round(v_c.score::numeric / 5.0) * 5), round(v_c.overlap_pct::numeric, 0),
            (round(v_c.origin_distance_m / 500.0) * 500)::int, (round(v_c.dest_distance_m / 500.0) * 500)::int,
            round(v_c.time_diff_min::numeric, 1))
    returning id into v_id;
  exception when unique_violation then
    raise exception 'GWM_ALREADY_REQUESTED' using errcode = 'P0001';
  end;
  return v_id;
end $$;

-- Lock order everywhere: TRIPS (ordered by id) first, then the match row. (respond_match no longer locks the match first,
-- otherwise the auto-cancel below could deadlock against a concurrent respond on a sibling request.)
create or replace function public._accept_match(p_match_id uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_m public.matches%rowtype; v_max int := public.cfg_num('match.max_matches_per_trip')::int;
  v_car boolean; v_lim int; v_rr public.trip_role; v_tr public.trip_role;
begin
  select * into v_m from public.matches where id = p_match_id and status = 'pending';          -- peek, no lock
  if not found then raise exception 'GWM_MATCH_NOT_PENDING' using errcode = 'P0001'; end if;
  perform 1 from public.trips where id in (v_m.requester_trip_id, v_m.target_trip_id) order by id for update;
  select * into v_m from public.matches where id = p_match_id and status = 'pending' for update; -- now lock (re-check after waiting)
  if not found then raise exception 'GWM_MATCH_NOT_PENDING' using errcode = 'P0001'; end if;
  if exists (select 1 from public.trips where id in (v_m.requester_trip_id, v_m.target_trip_id)
                and (status <> 'scheduled' or deleted_at is not null)) then
    raise exception 'GWM_TRIP_UNAVAILABLE' using errcode = 'P0001';
  end if;

  select (rt.mode = 'car'), rt.role, tt.role into v_car, v_rr, v_tr
    from public.trips rt, public.trips tt where rt.id = v_m.requester_trip_id and tt.id = v_m.target_trip_id;
  if v_car and (v_rr is null or v_tr is null or v_rr = v_tr) then
    raise exception 'GWM_NOT_ELIGIBLE' using errcode = 'P0001';                                  -- defence in depth
  end if;
  v_lim := case when v_car then public.car_seats() else v_max end;

  if (select count(*) from public.matches x where x.status = 'accepted'
        and v_m.requester_trip_id in (x.requester_trip_id, x.target_trip_id)) >= v_lim
  or (select count(*) from public.matches x where x.status = 'accepted'
        and v_m.target_trip_id in (x.requester_trip_id, x.target_trip_id)) >= v_lim then
    raise exception 'GWM_MATCH_LIMIT' using errcode = 'P0001';
  end if;

  update public.matches set status = 'accepted', responded_at = now() where id = p_match_id;
  if v_car then   -- US-16: the accepted Driver/Rider pair is closed: every other pending request of BOTH trips is cancelled
    update public.matches set status = 'cancelled', responded_at = now(), auto_closed = true
     where status = 'pending' and id <> p_match_id
       and (requester_trip_id in (v_m.requester_trip_id, v_m.target_trip_id)
         or target_trip_id    in (v_m.requester_trip_id, v_m.target_trip_id));
  end if;
  insert into public.chat_messages (match_id, sender_id, kind, body) values (p_match_id, null, 'system', 'system.matched');
end $$;

create or replace function public.respond_match(p_match_id uuid, p_accept boolean,
    p_meet_lng double precision default null, p_meet_lat double precision default null, p_meet_label text default null)
returns public.match_status
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare v_uid uuid := auth.uid(); v_m public.matches%rowtype; v_my public.trips%rowtype; v_other public.trips%rowtype;
begin
  select * into v_m from public.matches where id = p_match_id and target_id = v_uid and status = 'pending';   -- no lock (see _accept_match)
  if not found then raise exception 'GWM_MATCH_NOT_FOUND' using errcode = 'P0001'; end if;
  if not p_accept then
    update public.matches set status = 'declined', responded_at = now() where id = p_match_id and status = 'pending';
    if not found then raise exception 'GWM_MATCH_NOT_FOUND' using errcode = 'P0001'; end if;
    return 'declined';
  end if;
  perform public._accept_match(p_match_id);
  if public._valid_point(p_meet_lng, p_meet_lat) then
    select * into v_my    from public.trips where id = v_m.target_trip_id;
    select * into v_other from public.trips where id = v_m.requester_trip_id;
    if v_my.mode = 'car' then
      -- car: only the Driver opens the pickup proposal; a Rider's point at accept time is ignored
      if v_my.role = 'driver' then
        update public.matches set meeting_proposed_by = v_uid,
               meeting_proposed_point = ST_SetSRID(ST_MakePoint(p_meet_lng, p_meet_lat), 4326)::geography,
               meeting_proposed_label = left(p_meet_label, 120), meeting_proposed_at = now()
         where id = p_match_id;
      end if;
    else
      update public.matches set meeting_proposed_by = v_uid,
             meeting_proposed_point = ST_SetSRID(ST_MakePoint(p_meet_lng, p_meet_lat), 4326)::geography,
             meeting_proposed_label = left(p_meet_label, 120), meeting_proposed_at = now()
       where id = p_match_id;
    end if;
  end if;
  return 'accepted';
end $$;

-- cancel_match: same contract as 0001 + car rules (no cancel after pickup, internal outcome, in-trip system message)
create or replace function public.cancel_match(p_match_id uuid) returns void
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid(); v_m public.matches%rowtype; v_car boolean; v_role public.trip_role; v_started boolean;
begin
  if v_uid is null then raise exception 'GWM_UNAUTHENTICATED' using errcode = '42501'; end if;
  perform public._throttle('match_state', public.cfg_num('throttle.match_state_per_min')::int, 60);
  select * into v_m from public.matches
   where id = p_match_id and status in ('pending','accepted') and v_uid in (requester_id, target_id) for update;
  if not found then raise exception 'GWM_MATCH_NOT_FOUND' using errcode = 'P0001'; end if;

  if v_m.status = 'pending' then
    update public.matches set status = 'cancelled', responded_at = now() where id = p_match_id;
    return;
  end if;

  select (t.mode = 'car'), t.role into v_car, v_role
    from public.trips t where t.id = case when v_m.requester_id = v_uid then v_m.requester_trip_id else v_m.target_trip_id end;
  if v_car and v_m.boarded_at is not null then raise exception 'GWM_ALREADY_BOARDED' using errcode = 'P0001'; end if;

  update public.matches set status = 'cancelled', responded_at = now() where id = p_match_id;
  if v_car then
    insert into public.match_outcomes (match_id, reason, actor_id)
    values (p_match_id, case v_role when 'driver' then 'cancelled_by_driver' when 'rider' then 'cancelled_by_rider' else 'trip_ended' end, v_uid)
    on conflict (match_id) do nothing;
  end if;
  select exists (select 1 from public.trips t where t.id in (v_m.requester_trip_id, v_m.target_trip_id) and t.status = 'in_progress')
    into v_started;
  insert into public.chat_messages (match_id, sender_id, kind, body)
  values (p_match_id, null, 'system',
          case when v_car and v_started then 'system.match_cancelled_in_trip' else 'system.match_cancelled' end);
end $$;

-- Rider: "ขึ้นรถแล้ว". Idempotent (returns the first timestamp). Both trips must be in_progress.
create or replace function public.mark_boarded(p_match_id uuid) returns timestamptz
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid(); v_m public.matches%rowtype; v_my public.trips%rowtype; v_other public.trips%rowtype; v_pu timestamptz;
begin
  if v_uid is null then raise exception 'GWM_UNAUTHENTICATED' using errcode = '42501'; end if;
  perform public._throttle('match_state', public.cfg_num('throttle.match_state_per_min')::int, 60);
  select * into v_m from public.matches where id = p_match_id and status = 'accepted' and v_uid in (requester_id, target_id) for update;
  if not found then raise exception 'GWM_MATCH_NOT_FOUND' using errcode = 'P0001'; end if;
  select * into v_my    from public.trips where id = case when v_m.requester_id = v_uid then v_m.requester_trip_id else v_m.target_trip_id end;
  select * into v_other from public.trips where id = case when v_m.requester_id = v_uid then v_m.target_trip_id else v_m.requester_trip_id end;
  if v_my.mode <> 'car' or v_my.role is distinct from 'rider' then raise exception 'GWM_NOT_RIDER' using errcode = 'P0001'; end if;
  if v_m.boarded_at is not null then return v_m.boarded_at; end if;
  if v_my.status <> 'in_progress' or v_other.status <> 'in_progress' then
    raise exception 'GWM_TRIP_NOT_STARTED' using errcode = 'P0001';
  end if;
  update public.matches set boarded_at = now() where id = p_match_id returning boarded_at into v_pu;
  insert into public.chat_messages (match_id, sender_id, kind, body) values (p_match_id, null, 'system', 'system.boarded');
  return v_pu;
end $$;

-- R3-3: only the Driver can report a no-show (Rider no-show): Driver trip in_progress, match accepted, Rider not boarded.
-- A Driver no-show is handled by the Rider cancelling (cancel_match). No timers, no penalties; the reason is internal.
create or replace function public.report_rider_no_show(p_match_id uuid) returns void
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid(); v_m public.matches%rowtype; v_my public.trips%rowtype;
begin
  if v_uid is null then raise exception 'GWM_UNAUTHENTICATED' using errcode = '42501'; end if;
  perform public._throttle('match_state', public.cfg_num('throttle.match_state_per_min')::int, 60);
  select * into v_m from public.matches where id = p_match_id and status = 'accepted' and v_uid in (requester_id, target_id) for update;
  if not found then raise exception 'GWM_MATCH_NOT_FOUND' using errcode = 'P0001'; end if;
  select * into v_my from public.trips where id = case when v_m.requester_id = v_uid then v_m.requester_trip_id else v_m.target_trip_id end;
  if v_my.mode <> 'car' or v_my.role is distinct from 'driver' then raise exception 'GWM_NO_SHOW_NOT_ALLOWED' using errcode = 'P0001'; end if;
  if v_m.boarded_at is not null then raise exception 'GWM_ALREADY_BOARDED' using errcode = 'P0001'; end if;
  if v_my.status <> 'in_progress' then raise exception 'GWM_NO_SHOW_NOT_ALLOWED' using errcode = 'P0001'; end if;
  update public.matches set status = 'cancelled', responded_at = now() where id = p_match_id;
  insert into public.match_outcomes (match_id, reason, actor_id) values (p_match_id, 'rider_no_show', v_uid)
    on conflict (match_id) do nothing;
  insert into public.chat_messages (match_id, sender_id, kind, body) values (p_match_id, null, 'system', 'system.match_cancelled_in_trip');
end $$;

-- propose_meeting_point: 0002 body + car rules. RETURN TYPE CHANGES (void -> boolean = "beyond deviation limit", warning only).
drop function if exists public.propose_meeting_point(uuid, double precision, double precision, text);
create function public.propose_meeting_point(p_match_id uuid, p_lng double precision, p_lat double precision,
                                             p_label text default null)
returns boolean language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare v_uid uuid := auth.uid(); v_m public.matches%rowtype; v_my public.trips%rowtype; v_warn boolean := false;
begin
  if v_uid is null then raise exception 'GWM_UNAUTHENTICATED' using errcode = '42501'; end if;
  perform public._throttle('meeting', public.cfg_num('throttle.meeting_per_min')::int, 60);
  if not public._valid_point(p_lng, p_lat) then raise exception 'GWM_INVALID_POINT' using errcode = 'P0001'; end if;
  select * into v_m from public.matches m where m.id = p_match_id and m.status = 'accepted' and v_uid in (m.requester_id, m.target_id) for update;
  if not found then raise exception 'GWM_MATCH_NOT_FOUND' using errcode = 'P0001'; end if;
  if not public.is_chat_open(p_match_id) then raise exception 'GWM_MATCH_CLOSED' using errcode = 'P0001'; end if;
  select * into v_my from public.trips where id = case when v_m.requester_id = v_uid then v_m.requester_trip_id else v_m.target_trip_id end;
  if v_my.mode = 'car' then
    if v_m.boarded_at is not null then raise exception 'GWM_ALREADY_BOARDED' using errcode = 'P0001'; end if;
    -- US-18: the Driver opens the pickup proposal; the Rider confirms or counter-proposes
    if v_my.role = 'rider' and v_m.meeting_point is null and v_m.meeting_proposed_point is null then
      raise exception 'GWM_PICKUP_DRIVER_FIRST' using errcode = 'P0001';
    end if;
    -- SECURITY: even a boolean warning is an oracle on the Driver's exact route => cap attempts per user+match
    perform public._throttle('pickup:' || p_match_id::text, public.cfg_num('roles.pickup_proposals_per_hour')::int, 3600);
    v_warn := public._pickup_beyond_limit(v_m.driver_trip_id, p_lng, p_lat);
  end if;
  update public.matches set meeting_proposed_by = v_uid,
         meeting_proposed_point = ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
         meeting_proposed_label = left(p_label, 120), meeting_proposed_at = now()
   where id = p_match_id;
  return v_warn;   -- the point is ALWAYS stored; the client shows the warning
end $$;

-- get_partner_live_location: 0002 body + "after pickup the Rider's live location stops for the Driver"
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
     and exists (select 1 from public.trips mine
                  where mine.id = case when m.requester_id = auth.uid() then m.requester_trip_id else m.target_trip_id end
                    and mine.status = 'in_progress')
     and not ST_DWithin(t.last_location, t.dest, public.cfg_num('privacy.live_hide_near_dest_m'))
     and not (m.boarded_at is not null and t.role = 'rider')          -- US-18: rider is in the car; stop sharing rider -> driver
     and not exists (select 1 from public.blocks b
                      where (b.blocker_id = m.requester_id and b.blocked_id = m.target_id)
                         or (b.blocker_id = m.target_id    and b.blocked_id = m.requester_id));
end $$;

-- 10. Vehicle RPCs -----------------------------------------------------------------------------------------
-- Vehicle data is saved WITHOUT the share switch (default OFF, optional). Editing keeps the switch as is.
create or replace function public.upsert_my_vehicle(p_plate text, p_model text, p_color text)
returns uuid language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid(); v_plate text; v_model text; v_color text; v_id uuid;
begin
  if v_uid is null then raise exception 'GWM_UNAUTHENTICATED' using errcode = '42501'; end if;
  perform public._throttle('vehicle', public.cfg_num('throttle.vehicle_write_per_hour')::int, 3600);
  if not exists (select 1 from public.profiles p where p.id = v_uid and p.deleted_at is null) then
    raise exception 'GWM_PROFILE_UNAVAILABLE' using errcode = 'P0001';
  end if;
  v_plate := upper(regexp_replace(btrim(coalesce(p_plate, '')), '\s+', ' ', 'g'));
  v_model := regexp_replace(btrim(coalesce(p_model, '')), '\s+', ' ', 'g');
  v_color := regexp_replace(btrim(coalesce(p_color, '')), '\s+', ' ', 'g');
  if char_length(v_plate) not between 1 and 15 or char_length(v_model) not between 1 and 60 or char_length(v_color) not between 1 and 30
     or (v_plate || v_model || v_color) ~ '[[:cntrl:]]' then
    raise exception 'GWM_VEHICLE_INVALID' using errcode = 'P0001';
  end if;
  insert into public.vehicles as v (user_id, plate, model, color)
  values (v_uid, v_plate, v_model, v_color)
  on conflict (user_id) do update
     set plate = excluded.plate, model = excluded.model, color = excluded.color, verified_at = null   -- edited => self-declared again
  returning v.id into v_id;
  -- neutral system message to a matched Rider: "vehicle info changed"
  insert into public.chat_messages (match_id, sender_id, kind, body)
  select m.id, null, 'system', 'system.vehicle_updated'
    from public.matches m join public.trips td on td.id = m.driver_trip_id
   where m.status = 'accepted' and td.user_id = v_uid;
  return v_id;
end $$;

-- R3-1: server-side consent switch. Time is server time; OFF = NULL. Effective immediately for active share links.
create or replace function public.set_vehicle_share_consent(p_on boolean) returns timestamptz
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid(); v_at timestamptz;
begin
  if v_uid is null then raise exception 'GWM_UNAUTHENTICATED' using errcode = '42501'; end if;
  if p_on is null then raise exception 'GWM_VEHICLE_INVALID' using errcode = 'P0001'; end if;
  perform public._throttle('vehicle', public.cfg_num('throttle.vehicle_write_per_hour')::int, 3600);
  update public.vehicles set share_consent_at = case when p_on then now() end
   where user_id = v_uid returning share_consent_at into v_at;
  if not found then raise exception 'GWM_VEHICLE_REQUIRED' using errcode = 'P0001'; end if;
  return v_at;
end $$;

create or replace function public.delete_my_vehicle() returns void
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'GWM_UNAUTHENTICATED' using errcode = '42501'; end if;
  perform public._throttle('vehicle', public.cfg_num('throttle.vehicle_write_per_hour')::int, 3600);
  delete from public.vehicles where user_id = v_uid;      -- no row = success (idempotent); trigger raises GWM_VEHICLE_IN_USE
end $$;

-- Rider's view of the matched Driver's vehicle (+ whether the Driver allows plate forwarding). Same rule as the RLS policy.
create or replace function public.get_match_vehicle(p_match_id uuid)
returns table (plate text, model text, color text, verified boolean, share_allowed boolean)
language plpgsql stable security definer set search_path = public, pg_temp as $$
#variable_conflict use_column
begin
  return query
  select v.plate, v.model, v.color, (v.verified_at is not null), (v.share_consent_at is not null)
    from public.matches m
    join public.vehicles v on v.user_id = case when m.requester_id = auth.uid() then m.target_id else m.requester_id end
   where m.id = p_match_id and auth.uid() in (m.requester_id, m.target_id)
     and public.can_view_vehicle(v.user_id);
end $$;

-- 11. Share page (anon-callable): PLATE ONLY + driver name (R3-1).
--  * Rider's link: matched Driver's plate only while the match is 'accepted', both trips active, and share_consent_at is set
--    (withdrawing consent removes it from live links at once). Driver name is always returned for a matched Rider link.
--  * Driver's own link: own plate (own data, not tied to the switch).
drop function if exists public.get_shared_trip(text);
create function public.get_shared_trip(p_token text)
returns table (display_name text, status public.trip_status, mode public.travel_mode, depart_at timestamptz, eta_at timestamptz,
               approx_dest_lat double precision, approx_dest_lng double precision,
               last_lat double precision, last_lng double precision, last_location_at timestamptz, ended_at timestamptz,
               driver_name text, vehicle_plate text)
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
#variable_conflict use_column
declare
  v_share public.trip_shares%rowtype; v_trip public.trips%rowtype; v_name text;
  v_dn text; v_vp text;
begin
  if p_token is null or char_length(p_token) < 32 or char_length(p_token) > 128 then return; end if;
  select * into v_share from public.trip_shares s
   where s.token_hash = sha256(convert_to(p_token, 'utf8')) and s.revoked_at is null and s.expires_at > now();
  if not found then return; end if;
  select * into v_trip from public.trips where id = v_share.trip_id and deleted_at is null;
  if not found then return; end if;
  select p.display_name into v_name from public.profiles p where p.id = v_trip.user_id and p.deleted_at is null;
  if not found then return; end if;
  if v_trip.status in ('completed','cancelled','expired')
     and v_trip.ended_at < now() - public.cfg_num('share.terminal_grace_min') * interval '1 minute' then return; end if;

  if v_trip.role = 'rider' and v_trip.status in ('scheduled','in_progress') then
    select pr.display_name, case when ve.share_consent_at is not null then ve.plate end into v_dn, v_vp
      from public.matches m
      join public.trips td      on td.id = m.driver_trip_id
      join public.profiles pr   on pr.id = td.user_id and pr.deleted_at is null
      left join public.vehicles ve on ve.user_id = td.user_id
     where m.status = 'accepted' and m.rider_trip_id = v_trip.id
       and td.status in ('scheduled','in_progress')
       and not exists (select 1 from public.blocks b
                        where (b.blocker_id = td.user_id and b.blocked_id = v_trip.user_id)
                           or (b.blocker_id = v_trip.user_id and b.blocked_id = td.user_id))
     limit 1;
  elsif v_trip.role = 'driver' and v_trip.status in ('scheduled','in_progress') then
    select ve.plate into v_vp from public.vehicles ve where ve.user_id = v_trip.user_id;
  end if;

  update public.trip_shares set last_viewed_at = now() where id = v_share.id;
  return query select v_name, v_trip.status, v_trip.mode, v_trip.depart_at,
         coalesce(v_trip.started_at, v_trip.depart_at) + v_trip.route_duration_s * interval '1 second',
         ST_Y(public.blur_point(v_trip.dest)::geometry), ST_X(public.blur_point(v_trip.dest)::geometry),
         case when v_trip.status = 'in_progress' then ST_Y(v_trip.last_location::geometry) end,
         case when v_trip.status = 'in_progress' then ST_X(v_trip.last_location::geometry) end,
         case when v_trip.status = 'in_progress' then v_trip.last_location_at end,
         v_trip.ended_at,
         v_dn, v_vp;
end $$;

-- 11b. SOS: server-side plate-only snapshot (R3-1). The client cannot set it (not in the INSERT column grant).
alter table public.sos_events add column if not exists vehicle_snapshot text;
create or replace function public.sos_vehicle_snapshot() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  new.vehicle_snapshot := null;
  if new.trip_id is not null then
    select case when ve.share_consent_at is not null then ve.plate end into new.vehicle_snapshot
      from public.matches m
      join public.trips rt on rt.id = m.rider_trip_id and rt.user_id = new.user_id
      join public.trips td on td.id = m.driver_trip_id
      left join public.vehicles ve on ve.user_id = td.user_id
     where m.status = 'accepted' and m.rider_trip_id = new.trip_id
     limit 1;
  end if;
  return new;
end $$;
drop trigger if exists trg_sos_vehicle_snapshot on public.sos_events;
create trigger trg_sos_vehicle_snapshot before insert on public.sos_events      -- 'v' fires after trg_sos_events_guard ('e')
  for each row execute function public.sos_vehicle_snapshot();

-- purge_expired_data = 0002 body + clear SOS plate snapshots with the same 90-day rule (F-15)
create or replace function public.purge_expired_data() returns jsonb
language plpgsql security definer set search_path = public, extensions, auth, pg_temp as $$
declare
  v_loc_days int := public.cfg_num('retention.location_days')::int;
  v_del_days int := public.cfg_num('retention.account_deletion_days')::int;
  v_sos_days int := public.cfg_num('retention.sos_precise_days')::int;
  v_expired int; v_loc int; v_reduced int; v_trips int; v_users int; v_sos int;
begin
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

  update public.sos_events set location = public.blur_point(location), precision_reduced_at = now()
   where created_at < now() - v_sos_days * interval '1 day' and precision_reduced_at is null and location is not null;
  get diagnostics v_sos = row_count;
  update public.sos_events set vehicle_snapshot = null                                  -- NEW (0006)
   where created_at < now() - v_sos_days * interval '1 day' and vehicle_snapshot is not null;

  delete from public.match_outcomes                                                     -- NEW (0006): 12-month retention (PM)
   where created_at < now() - public.cfg_num('retention.match_outcome_months') * interval '1 month';

  delete from public.trips where deleted_at < now() - v_loc_days * interval '1 day';
  get diagnostics v_trips = row_count;

  delete from public.trip_shares where expires_at < now() - interval '30 days' or revoked_at < now() - interval '30 days';
  delete from public.api_throttle where window_start < now() - interval '1 day';

  delete from auth.users u using public.profiles p
   where p.id = u.id and p.deleted_at < now() - v_del_days * interval '1 day';
  get diagnostics v_users = row_count;

  return jsonb_build_object('expired_trips', v_expired, 'deleted_locations', v_loc, 'reduced_trips', v_reduced,
                            'reduced_sos', v_sos, 'deleted_trips', v_trips, 'deleted_users', v_users);
end $$;

-- 12. PDPA export includes the vehicle ---------------------------------------------------------------------
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
    'messages_sent', coalesce((select jsonb_agg(to_jsonb(m)) from public.chat_messages m where m.sender_id = auth.uid()), '[]'),
    'vehicle', (select to_jsonb(v) from public.vehicles v where v.user_id = auth.uid()))
$$;

-- 13. Grants (drop/create above lost ACLs; re-assert the whole role surface, idempotent) ------------------
grant select on public.vehicles to authenticated;
grant insert (role) on public.trips to authenticated;                 -- role is set at INSERT only; never updatable
grant execute on function public.can_view_vehicle(uuid) to authenticated;   -- RLS helper runs as invoker
grant execute on function public.find_matches(uuid, int), public.get_trip_card(uuid), public.request_match(uuid, uuid),
                          public.get_partner_live_location(uuid),
                          public.respond_match(uuid, boolean, double precision, double precision, text),
                          public.cancel_match(uuid),
                          public.propose_meeting_point(uuid, double precision, double precision, text),
                          public.mark_boarded(uuid), public.report_rider_no_show(uuid),
                          public.upsert_my_vehicle(text, text, text), public.set_vehicle_share_consent(boolean),
                          public.delete_my_vehicle(), public.get_match_vehicle(uuid),
                          public.export_my_data() to authenticated;
grant execute on function public.get_shared_trip(text) to anon, authenticated;
-- NOT granted (internal): car_seats, route_coverage_pct, _pickup_beyond_limit, sos_vehicle_snapshot, _accept_match, match_candidates, trigger functions.

-- clients only get what is granted above: make sure PUBLIC/anon never keep EXECUTE on the new RPCs / internals
revoke execute on function public.mark_boarded(uuid), public.report_rider_no_show(uuid), public.upsert_my_vehicle(text, text, text),
                           public.set_vehicle_share_consent(boolean), public.delete_my_vehicle(), public.get_match_vehicle(uuid),
                           public.can_view_vehicle(uuid), public.propose_meeting_point(uuid, double precision, double precision, text),
                           public.find_matches(uuid, int), public.get_trip_card(uuid) from public, anon;
revoke execute on function public.car_seats(), public.route_coverage_pct(geography, geography, double precision),
                           public._pickup_beyond_limit(uuid, double precision, double precision), public._accept_match(uuid)
                           from public, anon, authenticated;

notify pgrst, 'reload schema';
