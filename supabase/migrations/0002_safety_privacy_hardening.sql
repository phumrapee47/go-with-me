-- =============================================================================
-- GOWITHME migration 0002 -- P0 backend hardening (tasks T3.17 - T3.22)
-- Sources: docs/tasks.md "คำตัดสิน PM (รอบ 2)", docs/design-api.md s.13, docs/design-security.md
--   A. T3.17  sos_events / trips client-generated id (idempotent), SOS timestamp guard
--   B. T3.18  request_match: idempotent, pending cap (F-10), email gate; find_matches/request_match throttle;
--             get_partner_live_location stops on block (P-10); block no longer cancels accepted match (P-10)
--   C. T3.19  trips_guard: consent + 18+ (F-9b), no geometry/time edit while match pending/accepted (F-5)
--   D. T3.20  are_matched(): active trip or ended <= 24h (F-11)
--   E. T3.21  config keys, statement_timeout / max rows, SOS coarsening after 90 d (F-15)
--   F. T3.22  chat_state(match_id)
--   G. PM P-2 meeting point: propose + confirm AFTER matching (replaces direct set_meeting_point)
-- Re-runnable: CREATE OR REPLACE / IF NOT EXISTS / ON CONFLICT DO NOTHING.
-- NOTE: like 0001 this has not yet been executed on a real Postgres (see T3.23).
-- =============================================================================

set search_path = public, extensions;

-- 1. Config keys ----------------------------------------------------------------------
insert into public.app_config (key, value, description, is_public) values
  ('client.min_version',            '"0.1.0"', 'minimum supported app version (client shows force-update below this)', true),
  ('share.web_base_url',            '""',      'base URL of the public share page (P1); empty = no web page yet', true),
  ('match.max_pending_per_trip',    '5',       'F-10: max outgoing pending requests per trip', true),
  ('auth.require_verified_email',   'true',    'request_match requires a verified email (defence in depth for P-4); set false only for dev', false),
  ('retention.sos_precise_days',    '90',      'F-15: SOS location kept precise this long, then blurred (days)', false),
  ('sos.client_ts_max_age_h',       '168',     'client_created_at older than this (or in the future) is replaced by server time (hours)', false),
  ('throttle.find_matches_per_min', '30',      'per-user find_matches calls per minute', false),
  ('throttle.request_match_per_min','10',      'per-user request_match calls per minute', false),
  ('throttle.meeting_per_min',      '20',      'per-user meeting propose/confirm calls per minute', false)
on conflict (key) do nothing;

-- 2. Schema additions ------------------------------------------------------------------
alter table public.sos_events add column if not exists precision_reduced_at timestamptz;   -- F-15 marker
create index if not exists sos_events_precise_idx on public.sos_events (created_at)
  where precision_reduced_at is null and location is not null;

alter table public.matches add column if not exists meeting_proposed_by    uuid references public.profiles(id) on delete set null;
alter table public.matches add column if not exists meeting_proposed_point geography(Point, 4326);
alter table public.matches add column if not exists meeting_proposed_label text;
alter table public.matches add column if not exists meeting_proposed_at    timestamptz;

-- Per-user fixed-window counters (server-side throttle behind the client budget). No client access at all.
create table if not exists public.api_throttle (
  user_id      uuid not null references public.profiles(id) on delete cascade,
  bucket       text not null,
  window_start timestamptz not null default now(),
  hits         int not null default 0,
  primary key (user_id, bucket)
);
alter table public.api_throttle enable row level security;      -- no policies => no client rows
revoke all on public.api_throttle from anon, authenticated;

create or replace function public._throttle(p_bucket text, p_limit int, p_window_s int default 60) returns void
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid(); v_hits int;
begin
  if v_uid is null then return; end if;
  insert into public.api_throttle as t (user_id, bucket, window_start, hits)
  values (v_uid, p_bucket, now(), 1)
  on conflict (user_id, bucket) do update
    set hits         = case when t.window_start < now() - make_interval(secs => p_window_s) then 1 else t.hits + 1 end,
        window_start = case when t.window_start < now() - make_interval(secs => p_window_s) then now() else t.window_start end
  returning hits into v_hits;
  if v_hits > p_limit then raise exception 'GWM_RATE_LIMITED' using errcode = 'P0001'; end if;
end $$;

-- 3. A. Client-generated ids (idempotency) ------------------------------------------------
grant insert (id) on public.sos_events to authenticated;   -- client sends on_conflict=id + ignore-duplicates
grant insert (id) on public.trips      to authenticated;

-- SOS must never be rejected: out-of-range client timestamps are replaced with server time instead of raising.
create or replace function public.sos_events_guard() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$   -- definer: cfg_num() is not executable by clients
declare v_max interval := public.cfg_num('sos.client_ts_max_age_h') * interval '1 hour';
begin
  if new.client_created_at is null
     or new.client_created_at < now() - v_max
     or new.client_created_at > now() + interval '5 minutes' then
    new.client_created_at := now();
  end if;
  new.precision_reduced_at := null;
  return new;
end $$;
drop trigger if exists trg_sos_events_guard on public.sos_events;
create trigger trg_sos_events_guard before insert on public.sos_events
  for each row execute function public.sos_events_guard();

-- 4. D. are_matched: active trips, or ended <= 24h (F-11) --------------------------------------
create or replace function public.are_matched(p_a uuid, p_b uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1
    from public.matches m
    join public.trips ta on ta.id = m.requester_trip_id
    join public.trips tb on tb.id = m.target_trip_id
    where m.status = 'accepted'
      and ((m.requester_id = p_a and m.target_id = p_b) or (m.requester_id = p_b and m.target_id = p_a))
      and (ta.status in ('scheduled','in_progress') or ta.ended_at > now() - interval '24 hours')
      and (tb.status in ('scheduled','in_progress') or tb.ended_at > now() - interval '24 hours'))
$$;

-- 5. C. trips_guard: F-9b (consent + 18+), F-5 (no bait-and-switch), idempotent create --------
create or replace function public.trips_guard() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_system boolean := auth.uid() is null;
  v_grace  interval := public.cfg_num('trip.depart_grace_min') * interval '1 minute';
  v_terminal public.trip_status[] := array['completed','cancelled','expired']::public.trip_status[];
  v_adult  timestamptz;
begin
  if tg_op = 'INSERT' then
    -- Idempotent retry (client-generated id): the same user re-sending the same trip is a silent no-op.
    -- (PostgREST returns 201 with an empty body for return=representation; client then re-reads the trip.)
    if new.id is not null and exists (select 1 from public.trips t where t.id = new.id and t.user_id = new.user_id) then
      return null;
    end if;

    new.status := 'scheduled'; new.started_at := null; new.ended_at := null;
    new.last_location := null; new.last_location_at := null; new.precision_reduced_at := null; new.deleted_at := null; new.geo_edits := 0;

    select p.adult_confirmed_at into v_adult from public.profiles p
     where p.id = new.user_id and p.deleted_at is null for update;      -- lock => race-free limit
    if not found then raise exception 'GWM_PROFILE_UNAVAILABLE' using errcode = 'P0001'; end if;
    -- F-9b: PDPA + 18+ enforced server-side (client-side checks can be bypassed by calling GoTrue directly)
    if v_adult is null then raise exception 'GWM_ADULT_REQUIRED' using errcode = 'P0001'; end if;
    if not coalesce((select c.granted from public.consents c
                      where c.user_id = new.user_id and c.kind = 'privacy_policy'
                      order by c.created_at desc limit 1), false) then
      raise exception 'GWM_CONSENT_REQUIRED' using errcode = 'P0001';
    end if;

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
    -- F-5: geometry / departure time / travel mode are frozen while a request is pending or accepted (cancel the request first).
    -- PM round-2 decision: `mode` is locked too (mode drives eligibility via match.mode_compat: bait-and-switch otherwise).
    if (new.origin is distinct from old.origin or new.dest is distinct from old.dest
        or new.route is distinct from old.route or new.depart_at is distinct from old.depart_at
        or new.mode is distinct from old.mode)
       and exists (select 1 from public.matches m
                    where m.status in ('pending','accepted') and old.id in (m.requester_trip_id, m.target_trip_id)) then
      raise exception 'GWM_TRIP_HAS_MATCHES' using errcode = 'P0001';
    end if;

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

-- 6. B/P-10. Block: chat becomes read-only (is_chat_open already checks blocks), match STAYS accepted,
--            the blocker cancels the match themself. Only PENDING requests between the pair are cancelled.
create or replace function public.blocks_after_insert() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update public.matches set status = 'cancelled', responded_at = now()
   where status = 'pending'
     and ((requester_id = new.blocker_id and target_id = new.blocked_id)
       or (requester_id = new.blocked_id and target_id = new.blocker_id));
  return null;
end $$;

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
     -- P-10: a block in either direction stops live location immediately
     and not exists (select 1 from public.blocks b
                      where (b.blocker_id = m.requester_id and b.blocked_id = m.target_id)
                         or (b.blocker_id = m.target_id    and b.blocked_id = m.requester_id));
end $$;

-- 7. B. find_matches (now volatile: throttled) and request_match (idempotent, capped) ---------------
create or replace function public.find_matches(p_trip_id uuid, p_limit int default 20)
returns table (trip_id uuid, display_name text, badges jsonb, mode public.travel_mode, depart_at timestamptz,
               time_diff_min int, overlap_pct int, approx_distance_m int, score numeric,
               approx_origin_lat double precision, approx_origin_lng double precision,
               approx_dest_lat double precision, approx_dest_lng double precision,
               request_status public.match_status)
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
         (select m.status from public.matches m
           where (m.requester_trip_id = p_trip_id and m.target_trip_id = o.id)
              or (m.requester_trip_id = o.id and m.target_trip_id = p_trip_id) limit 1)
    from public.match_candidates(p_trip_id, p_limit) c
    join public.trips o     on o.id  = c.candidate_trip_id
    join public.profiles pr on pr.id = c.candidate_user_id
   order by c.score desc, o.id;
end $$;

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

  -- lock own trip: serialises concurrent requests => the pending cap cannot be raced
  select * into v_me from public.trips where id = p_my_trip and user_id = v_uid and deleted_at is null for update;
  if not found or v_me.status <> 'scheduled' then raise exception 'GWM_TRIP_NOT_FOUND' using errcode = 'P0001'; end if;

  -- Idempotent retry: same requester/trip pair already pending or accepted => return the SAME id.
  select * into v_dup from public.matches
   where requester_trip_id = p_my_trip and target_trip_id = p_target_trip and requester_id = v_uid;
  if found then
    if v_dup.status in ('pending','accepted') then return v_dup.id; end if;
    raise exception 'GWM_ALREADY_REQUESTED' using errcode = 'P0001';
  end if;

  select * into v_c from public.match_candidates(p_my_trip, 1, p_target_trip);   -- re-check eligibility server-side
  if not found then raise exception 'GWM_NOT_ELIGIBLE' using errcode = 'P0001'; end if;

  -- The other side already asked me => mutual interest, accept that request (exactly one match row).
  select * into v_rev from public.matches where requester_trip_id = p_target_trip and target_trip_id = p_my_trip for update;
  if found then
    if v_rev.status = 'pending' then perform public._accept_match(v_rev.id); return v_rev.id; end if;
    raise exception 'GWM_ALREADY_EXISTS' using errcode = 'P0001';
  end if;

  -- F-10: cap outgoing pending requests per trip
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

-- 8. G. Meeting point AFTER matching (P-2): one side proposes, the other confirms ------------------------
-- respond_match keeps its signature; a meeting point passed at accept time becomes a PROPOSAL by the target.
create or replace function public._valid_point(p_lng double precision, p_lat double precision) returns boolean
language sql immutable as $$
  select p_lng is not null and p_lat is not null and p_lng between -180 and 180 and p_lat between -90 and 90
$$;

create or replace function public.respond_match(p_match_id uuid, p_accept boolean,
    p_meet_lng double precision default null, p_meet_lat double precision default null, p_meet_label text default null)
returns public.match_status
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare v_uid uuid := auth.uid(); v_m public.matches%rowtype;
begin
  select * into v_m from public.matches where id = p_match_id and target_id = v_uid and status = 'pending' for update;
  if not found then raise exception 'GWM_MATCH_NOT_FOUND' using errcode = 'P0001'; end if;
  if not p_accept then
    update public.matches set status = 'declined', responded_at = now() where id = p_match_id;
    return 'declined';
  end if;
  perform public._accept_match(p_match_id);
  if public._valid_point(p_meet_lng, p_meet_lat) then
    update public.matches set meeting_proposed_by = v_uid,
           meeting_proposed_point = ST_SetSRID(ST_MakePoint(p_meet_lng, p_meet_lat), 4326)::geography,
           meeting_proposed_label = left(p_meet_label, 120), meeting_proposed_at = now()
     where id = p_match_id;
  end if;
  return 'accepted';
end $$;

create or replace function public.propose_meeting_point(p_match_id uuid, p_lng double precision, p_lat double precision,
                                                        p_label text default null)
returns void language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'GWM_UNAUTHENTICATED' using errcode = '42501'; end if;
  perform public._throttle('meeting', public.cfg_num('throttle.meeting_per_min')::int, 60);
  if not public._valid_point(p_lng, p_lat) then raise exception 'GWM_INVALID_POINT' using errcode = 'P0001'; end if;
  perform 1 from public.matches m where m.id = p_match_id and m.status = 'accepted' and v_uid in (m.requester_id, m.target_id) for update;
  if not found then raise exception 'GWM_MATCH_NOT_FOUND' using errcode = 'P0001'; end if;
  if not public.is_chat_open(p_match_id) then raise exception 'GWM_MATCH_CLOSED' using errcode = 'P0001'; end if;  -- trip ended / blocked
  update public.matches set meeting_proposed_by = v_uid,
         meeting_proposed_point = ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
         meeting_proposed_label = left(p_label, 120), meeting_proposed_at = now()
   where id = p_match_id;                                   -- a new proposal replaces any earlier one (counter-offer)
end $$;

create or replace function public.confirm_meeting_point(p_match_id uuid) returns void
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare v_uid uuid := auth.uid(); v_m public.matches%rowtype;
begin
  if v_uid is null then raise exception 'GWM_UNAUTHENTICATED' using errcode = '42501'; end if;
  perform public._throttle('meeting', public.cfg_num('throttle.meeting_per_min')::int, 60);
  select * into v_m from public.matches m
   where m.id = p_match_id and m.status = 'accepted' and v_uid in (m.requester_id, m.target_id) for update;
  if not found then raise exception 'GWM_MATCH_NOT_FOUND' using errcode = 'P0001'; end if;
  if v_m.meeting_proposed_point is null then raise exception 'GWM_NO_PROPOSAL' using errcode = 'P0001'; end if;
  if v_m.meeting_proposed_by = v_uid then raise exception 'GWM_OWN_PROPOSAL' using errcode = 'P0001'; end if;
  if not public.is_chat_open(p_match_id) then raise exception 'GWM_MATCH_CLOSED' using errcode = 'P0001'; end if;
  update public.matches set meeting_point = meeting_proposed_point, meeting_label = meeting_proposed_label,
         meeting_proposed_by = null, meeting_proposed_point = null, meeting_proposed_label = null, meeting_proposed_at = null
   where id = p_match_id;
end $$;

-- 9. F. chat_state: lets the client tell "chat closed" apart from an RLS denial -----------------------------
-- returns: 'open' | 'blocked' | 'trip_ended' | 'match_closed' | 'not_found'
create or replace function public.chat_state(p_match_id uuid) returns text
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_m public.matches%rowtype;
begin
  select * into v_m from public.matches m where m.id = p_match_id and auth.uid() in (m.requester_id, m.target_id);
  if not found then return 'not_found'; end if;
  if v_m.status <> 'accepted' then return 'match_closed'; end if;
  if exists (select 1 from public.blocks b
              where (b.blocker_id = v_m.requester_id and b.blocked_id = v_m.target_id)
                 or (b.blocker_id = v_m.target_id and b.blocked_id = v_m.requester_id)) then return 'blocked'; end if;
  if not public.is_chat_open(p_match_id) then return 'trip_ended'; end if;
  return 'open';
end $$;

-- 10. E. purge_expired_data + SOS coarsening (F-15) ----------------------------------------------------------
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

  -- F-15: SOS locations are precise for sos days, then snapped to the blur grid
  update public.sos_events set location = public.blur_point(location), precision_reduced_at = now()
   where created_at < now() - v_sos_days * interval '1 day' and precision_reduced_at is null and location is not null;
  get diagnostics v_sos = row_count;

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

-- 11. Grants ----------------------------------------------------------------------------------------------------
-- (create or replace keeps existing ACLs for functions that existed in 0001)
grant execute on function public.propose_meeting_point(uuid, double precision, double precision, text),
                          public.confirm_meeting_point(uuid),
                          public.chat_state(uuid) to authenticated;
-- P-2: no unilateral meeting point; only propose/confirm remain. (function kept for service_role/admin fixes)
revoke execute on function public.set_meeting_point(uuid, double precision, double precision, text) from authenticated;
-- internal only: _throttle, _valid_point, sos_events_guard (no grants)

-- 12. Role settings: statement timeout + max rows (best effort; hosted projects may restrict) ----------------------------
do $$
begin
  execute 'alter role authenticated set statement_timeout = ''8s''';
  execute 'alter role anon set statement_timeout = ''3s''';
exception when others then
  raise notice 'statement_timeout role settings skipped: % (set in Dashboard > Database > Roles)', sqlerrm;
end $$;
do $$
begin
  execute 'alter role authenticator set pgrst.db_max_rows = ''1000''';
exception when others then
  raise notice 'pgrst.db_max_rows skipped: % (set [api] max_rows in config.toml / Dashboard > API settings)', sqlerrm;
end $$;

notify pgrst, 'reload config';
notify pgrst, 'reload schema';
