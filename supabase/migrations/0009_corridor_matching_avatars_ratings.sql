-- =====================================================================================================================
-- GOWITHME migration 0009 (round 5, DRAFT - not applied anywhere): docs/design-roles.md section 12
--   US-21  car Driver<->Rider 'neighbourhood' matching (origin radius + per-Driver-trip trips.max_dropoff_m + overlap + 30 min;
--          match.dest_radius_m no longer applies to car; peer modes unchanged; the corridor rule is kept, OFF by default)
--          + no-match hint RPC (P1, category only, rate limited)
--   US-22  profile photo: private `avatars` bucket (jpeg only, <= 512 KB, one fixed object per user), visibility helpers,
--          partner path RPC, report, purge queue, admin removal
--   US-26  reviews: reviews / review_tags / content_reports tables, blind reveal, aggregate view, RPCs
--   US-25  (P1) vehicle photo: DESIGN ONLY (see design-roles.md section 12.6); nothing is created here.
-- Redefines (latest definitions read first): match_candidates (0006), find_matches (0006), request_match (0006),
--   _accept_match (0006; used by respond_match), purge_expired_data (0006), export_my_data (0008),
--   avatars storage policies (0001). request_account_deletion (0008) is redefined (reviews / reports cleanup).
-- Idempotent: safe to re-run. Every new function is SECURITY DEFINER with a pinned search_path; grants are explicit.
-- =====================================================================================================================

-- 1. Config (single place, is_public = false unless the client needs it) ---------------------------------------------
insert into public.app_config (key, value, description, is_public) values
  ('match.car_rule',                '"neighbourhood"', 'US-21: car rule: neighbourhood (default; anything unknown behaves as neighbourhood) | corridor (backend-only alternative)', false),
  ('match.car_origin_radius_m',     '2000',  'US-21: car - max distance between the two trip origins (m), inclusive', true),
  ('match.car_dest_radius_max_m',   '5000',  'US-21: ceiling of trips.max_dropoff_m (m); effective limit = least(value or 2000, this)', true),
  ('match.car_corridor_m',          '1000',  'US-21 (corridor rule only): rider pickup AND drop-off within this distance of the Driver route (m)', false),
  ('match.car_max_detour_m',        '3000',  'US-21 (corridor rule only): max Driver detour estimate 2*(d_pickup + d_drop) (m)', false),
  ('match.car_min_rider_coverage',  '0.80',  'US-21 (corridor rule only): min fraction of the RIDER route length inside the Driver corridor (0..1)', false),
  ('match.car_weights',             '{"detour":0.4,"time":0.2,"coverage":0.4}', 'US-21 (corridor rule only): car score weights (normalised)', false),
  ('match.hint_radius_m',           '20000', 'US-21 hint: only trips whose ORIGIN is within this distance of mine are considered', false),
  ('throttle.match_hint_per_min',   '6',     'US-21 hint: per-user calls per minute (oracle protection)', false),
  ('avatar.max_bytes',              '524288','US-22: max avatar object size (bytes); bucket file_size_limit uses the same value', true),
  ('throttle.avatar_write_per_hour','20',    'US-22: set/remove avatar calls per user per hour', false),
  ('throttle.report_per_hour',      '10',    'US-22/26: avatar + review reports per user per hour', false),
  ('review.window_days',            '7',     'US-26: review window (days) counted from the first completed trip of the match; also the blind-reveal timeout', true),
  ('review.min_count_for_aggregate','3',     'US-26: min revealed reviews per role before an average is shown', true),
  ('review.max_tags',               '5',     'US-26: max tags per review', true),
  ('review.show_in_search',         'true',  'US-26 open question 2 (PM: true): aggregate readable for any user with a scheduled trip; false = only self / matched pair', false),
  ('throttle.review_write_per_hour','20',    'US-26: submit_review calls per user per hour', false)
on conflict (key) do nothing;

-- 2. trips.max_dropoff_m (US-21 'neighbourhood' rule) + matches.car_rule_checked --------------------------------------------------
-- max_dropoff_m: the Driver's own limit (m) for how far from the DRIVER's destination the Rider's destination may be.
-- NULL = not chosen (legacy driver rows / non-driver trips); the predicate treats NULL on a driver trip as 2000 (_car_dropoff_limit).
-- Only meaningful for role = 'driver' (CHECK), integer metres, multiples of 100, 500..5000 (the effective ceiling is the config
-- match.car_dest_radius_max_m, enforced by the trigger below, so lowering the config never needs a schema change).
alter table public.trips add column if not exists max_dropoff_m integer;
do $$ begin
  alter table public.trips add constraint trips_max_dropoff_chk
    check (max_dropoff_m is null or (role = 'driver' and max_dropoff_m between 500 and 5000 and max_dropoff_m % 100 = 0));
exception when duplicate_object then null; end $$;
-- set on INSERT by the client (like `role`), editable later only while the trip has no pending/accepted match (trigger)
grant insert (max_dropoff_m), update (max_dropoff_m) on public.trips to authenticated;

-- validation + lock. Out-of-range / off-step values are REJECTED (never rounded). A non-integer cannot reach here (column type).
-- Fires after trg_trips_guard (alphabetical) and before trg_trips_role_guard; not reached for the idempotent-retry no-op insert.
create or replace function public.trips_max_dropoff_guard() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if tg_op = 'INSERT' then
    if new.max_dropoff_m is not null and new.role is distinct from 'driver' then
      raise exception 'GWM_DROPOFF_NOT_ALLOWED' using errcode = 'P0001';       -- Rider / peer trips carry no drop-off limit
    end if;
    if new.max_dropoff_m is null and new.role = 'driver' then new.max_dropoff_m := 2000; end if;   -- default
  else
    if new.max_dropoff_m is not distinct from old.max_dropoff_m then return new; end if;
    if auth.uid() is not null then
      if new.role is distinct from 'driver' then raise exception 'GWM_DROPOFF_NOT_ALLOWED' using errcode = 'P0001'; end if;
      if new.max_dropoff_m is null then raise exception 'GWM_DROPOFF_INVALID' using errcode = 'P0001'; end if;
      if old.status <> 'scheduled' then raise exception 'GWM_TRIP_STARTED' using errcode = 'P0001'; end if;
      -- same lock as origin / destination edits (trips_guard, F-5): cancel the request first
      if exists (select 1 from public.matches m
                  where m.status in ('pending','accepted') and old.id in (m.requester_trip_id, m.target_trip_id)) then
        raise exception 'GWM_TRIP_HAS_MATCHES' using errcode = 'P0001';
      end if;
    end if;
  end if;
  if new.max_dropoff_m is not null
     and (new.max_dropoff_m < 500 or new.max_dropoff_m > public.cfg_num('match.car_dest_radius_max_m') or new.max_dropoff_m % 100 <> 0) then
    raise exception 'GWM_DROPOFF_INVALID' using errcode = 'P0001';
  end if;
  return new;
end $$;
drop trigger if exists trg_trips_max_dropoff on public.trips;
create trigger trg_trips_max_dropoff before insert or update of max_dropoff_m on public.trips
  for each row execute function public.trips_max_dropoff_guard();
revoke execute on function public.trips_max_dropoff_guard() from public, anon, authenticated;

-- rows created by the 0009 request_match are re-checked with the SAME predicate when accepted (pre-0009 pending rows are not)
alter table public.matches add column if not exists car_rule_checked boolean not null default false;

-- 3. Car predicates ---------------------------------------------------------------------------------------------------------------
-- 3a. effective drop-off limit of a Driver trip: least(coalesce(value, 2000), match.car_dest_radius_max_m)
create or replace function public._car_dropoff_limit(p_max int) returns int
language sql stable security definer set search_path = public, pg_temp as $$
  select least(coalesce(p_max, 2000), public.cfg_num('match.car_dest_radius_max_m')::int)
$$;
revoke execute on function public._car_dropoff_limit(int) from public, anon, authenticated;

-- 3b. THE car predicate (single definition; used by match_candidates, request_match (through it), _accept_match, get_match_hint).
-- match.car_rule = 'corridor' -> _car_corridor_eval (below); ANY other value (incl. unknown) -> 'neighbourhood':
--   stage 1 far_origin      : ST_Distance(driver origin, rider origin)  > match.car_origin_radius_m
--   stage 2 far_destination : ST_Distance(driver dest,   rider dest)    > effective max_dropoff_m of the DRIVER trip
--   stage 3 overlap         : route_overlap_pct(driver route, rider route, match.route_buffer_m) < match.min_overlap_pct
--   stage 0 = match. Straight-line geography distances, thresholds INCLUSIVE (<=), compared after rounding to 0.1 m
--   (overlap to 0.1 %). Metrics after the first failing stage are NULL. Time window (30 min) is applied by match_candidates.
-- Symmetric: arguments are the Driver's and the Rider's data, never "mine / theirs".
create or replace function public._car_rule_eval(p_d_origin geography, p_d_dest geography, p_d_route geography, p_d_max_dropoff int,
                                                 p_r_origin geography, p_r_dest geography, p_r_route geography)
returns table (stage int, d_o double precision, d_d double precision, ov double precision, detour_m double precision, lim int)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare
  v_ro  double precision := public.cfg_num('match.car_origin_radius_m');
  v_min double precision := public.cfg_num('match.min_overlap_pct');
  v_buf double precision := public.cfg_num('match.route_buffer_m');
begin
  lim := public._car_dropoff_limit(p_d_max_dropoff);
  if (public.cfg('match.car_rule') #>> '{}') = 'corridor' then
    select e.stage, e.d_o, e.d_d, e.coverage_pct, e.detour_m into stage, d_o, d_d, ov, detour_m
      from public._car_corridor_eval(p_d_route, p_r_route, p_r_origin, p_r_dest) e;
    if stage <> 0 then stage := 3; end if;               -- corridor mode has no user-visible reason categories
    return next; return;
  end if;
  d_o := ST_Distance(p_d_origin, p_r_origin);
  d_d := ST_Distance(p_d_dest,   p_r_dest);
  if round(d_o::numeric, 1) > v_ro then stage := 1; return next; return; end if;
  if round(d_d::numeric, 1) > lim  then stage := 2; return next; return; end if;
  ov := public.route_overlap_pct(p_d_route, p_r_route, v_buf);
  if round(ov::numeric, 1) < round(v_min::numeric, 1) then stage := 3; return next; return; end if;
  stage := 0; detour_m := null; return next;
end $$;
revoke execute on function public._car_rule_eval(geography, geography, geography, int, geography, geography, geography) from public, anon, authenticated;

-- 3c. OPTIONAL rule (match.car_rule = 'corridor', OFF by default, backend only, no UI). Does not use max_dropoff_m.
-- OPTIONAL corridor predicate (pure function of geography values), used ONLY through _car_rule_eval when match.car_rule = 'corridor'.
--   d_o / d_d    = distance (m) rider origin / rider destination -> Driver route            (stage 1: both <= car_corridor_m)
--   f_o / f_d    = ST_LineLocatePoint fraction on the Driver route                          (stage 2: f_o < f_d and along >= trip.min_distance_m)
--   coverage_pct = % of the RIDER route length within car_corridor_m of the Driver route    (stage 3: >= car_min_rider_coverage*100)
--   detour_m     = 2*(d_o + d_d) straight-line approximation                                (stage 4: <= car_max_detour_m)
-- Distances compared after rounding to 0.1 m, coverage to 0.1 %. stage = first failing check (0 = ok).
create or replace function public._car_corridor_eval(p_driver_route geography, p_rider_route geography,
                                                    p_rider_origin geography, p_rider_dest geography)
returns table (stage int, d_o double precision, d_d double precision, detour_m double precision,
               coverage_pct double precision, along_m double precision)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare
  v_corr double precision := public.cfg_num('match.car_corridor_m');
  v_det  double precision := public.cfg_num('match.car_max_detour_m');
  v_cov  double precision := public.cfg_num('match.car_min_rider_coverage') * 100.0;
  v_min  double precision := public.cfg_num('trip.min_distance_m');
  f_o double precision; f_d double precision;
begin
  d_o := ST_Distance(p_rider_origin, p_driver_route);
  d_d := ST_Distance(p_rider_dest,   p_driver_route);
  if round(d_o::numeric, 1) > v_corr or round(d_d::numeric, 1) > v_corr then
    stage := 1; return next; return;
  end if;
  f_o := ST_LineLocatePoint(p_driver_route::geometry, p_rider_origin::geometry);
  f_d := ST_LineLocatePoint(p_driver_route::geometry, p_rider_dest::geometry);
  along_m := (f_d - f_o) * ST_Length(p_driver_route);
  if not (f_o < f_d and round(along_m::numeric, 1) >= v_min) then
    stage := 2; return next; return;
  end if;
  coverage_pct := public.route_coverage_pct(p_rider_route, p_driver_route, v_corr);
  if round(coverage_pct::numeric, 1) < round(v_cov::numeric, 1) then
    stage := 3; return next; return;
  end if;
  detour_m := 2.0 * (d_o + d_d);
  if round(detour_m::numeric, 1) > v_det then
    stage := 4; return next; return;
  end if;
  stage := 0; return next;
end $$;
revoke execute on function public._car_corridor_eval(geography, geography, geography, geography) from public, anon, authenticated;



-- 4. match_candidates (same name/args; return type gains detour_m (NULL unless corridor) => drop + create) ----------------------------
-- Peer modes: the 0006 rule byte-for-byte. Car: _car_rule_eval. Car score ('neighbourhood') uses match.weights with
--   distance term = 1 - min(1, (d_origin/car_origin_radius + d_dest/driver_limit)/2); corridor mode uses match.car_weights.
-- Ties: score desc, trips.created_at asc (car only), trip id asc => deterministic.
-- car column mapping: origin_distance_m = origin distance, dest_distance_m = destination distance (INTERNAL), overlap_pct = overlap.
drop function if exists public.match_candidates(uuid, int, uuid);
create function public.match_candidates(p_trip_id uuid, p_limit int default 20, p_only_trip uuid default null)
returns table (candidate_trip_id uuid, candidate_user_id uuid, origin_distance_m double precision,
               dest_distance_m double precision, time_diff_min double precision,
               overlap_pct double precision, score double precision, detour_m double precision)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
#variable_conflict use_column
declare
  v_t      public.trips%rowtype;
  v_car    boolean;
  v_cor    boolean := (public.cfg('match.car_rule') #>> '{}') = 'corridor';
  v_r_o    double precision := public.cfg_num('match.origin_radius_m');
  v_r_d    double precision := public.cfg_num('match.dest_radius_m');
  v_roc    double precision := public.cfg_num('match.car_origin_radius_m');
  v_dmax   double precision := public.cfg_num('match.car_dest_radius_max_m');
  v_win    double precision := public.cfg_num('match.time_window_min');
  v_min_ov double precision := public.cfg_num('match.min_overlap_pct');
  v_max    int              := public.cfg_num('match.max_matches_per_trip')::int;
  v_buf    double precision := public.cfg_num('match.route_buffer_m');
  v_corr   double precision := public.cfg_num('match.car_corridor_m');
  v_det    double precision := public.cfg_num('match.car_max_detour_m');
  v_w      jsonb            := public.cfg('match.weights');
  v_cw     jsonb            := public.cfg('match.car_weights');
  v_compat jsonb            := public.cfg('match.mode_compat');
  v_wd double precision := (v_w ->> 'distance')::double precision;
  v_wt double precision := (v_w ->> 'time')::double precision;
  v_wo double precision := (v_w ->> 'overlap')::double precision;
  v_cd double precision := (v_cw ->> 'detour')::double precision;
  v_ct double precision := (v_cw ->> 'time')::double precision;
  v_cc double precision := (v_cw ->> 'coverage')::double precision;
  v_cutoff timestamptz      := now() - public.cfg_num('trip.expire_after_min') * interval '1 minute';
  v_lim    int;
begin
  select * into v_t from public.trips where id = p_trip_id and deleted_at is null;
  if not found or v_t.status <> 'scheduled' or v_t.depart_at <= v_cutoff then return; end if;
  v_car := (v_t.mode = 'car');
  if v_car and v_t.role is null then return; end if;              -- legacy role-less car trips are never matched
  v_lim := case when v_car then public.car_seats() else v_max end;
  if (select count(*) from public.matches m where m.status = 'accepted'
        and v_t.id in (m.requester_trip_id, m.target_trip_id)) >= v_lim then return; end if;

  return query
  with cand as (
    select o.id as tid, o.user_id as uid, o.created_at as cat, o.route as route, o.origin as oo, o.dest as od,
           o.max_dropoff_m as mdo,
           ST_Distance(o.origin, v_t.origin) as p_d_o,
           ST_Distance(o.dest,   v_t.dest)   as p_d_d,
           (abs(extract(epoch from (o.depart_at - v_t.depart_at))) / 60.0)::double precision as dt
      from public.trips o
      join public.profiles p on p.id = o.user_id and p.deleted_at is null
     where o.status = 'scheduled' and o.deleted_at is null
       and o.depart_at > v_cutoff
       and o.user_id <> v_t.user_id
       and (p_only_trip is null or o.id = p_only_trip)
       and case when v_car and v_cor then ST_DWithin(o.route, v_t.route, v_corr)                     -- cheap necessary pre-filters (GiST);
                when v_car then ST_DWithin(o.origin, v_t.origin, v_roc) and ST_DWithin(o.dest, v_t.dest, v_dmax)   -- the real test is _car_rule_eval
                else ST_DWithin(o.origin, v_t.origin, v_r_o) and ST_DWithin(o.dest, v_t.dest, v_r_d) end
       and o.depart_at between v_t.depart_at - v_win * interval '1 minute'
                           and v_t.depart_at + v_win * interval '1 minute'
       and case when v_car
                then o.mode = 'car' and o.role is not null and o.role <> v_t.role          -- Driver<->Rider only
                else o.mode <> 'car' and (v_compat -> v_t.mode::text) @> to_jsonb(o.mode::text)
           end
       and not exists (select 1 from public.blocks b
                        where (b.blocker_id = v_t.user_id and b.blocked_id = o.user_id)
                           or (b.blocker_id = o.user_id  and b.blocked_id = v_t.user_id))
       and not exists (select 1 from public.matches m
                        where m.status <> 'pending' and not (m.status = 'cancelled' and m.auto_closed)
                          and ((m.requester_trip_id = v_t.id and m.target_trip_id = o.id)
                            or (m.requester_trip_id = o.id  and m.target_trip_id = v_t.id)))
       and (select count(*) from public.matches m where m.status = 'accepted'
              and o.id in (m.requester_trip_id, m.target_trip_id)) < v_lim
  ), scored as (
    select c.tid, c.uid, c.cat, c.dt,
           case when v_car then ev.d_o else c.p_d_o end as d_o,
           case when v_car then ev.d_d else c.p_d_d end as d_d,
           case when v_car then ev.ov
                else public.route_overlap_pct(v_t.route, c.route, v_buf) end as ov,
           ev.detour_m as dm, ev.stage as stage, ev.lim as dlim
      from cand c
      left join lateral (
        select e.* from public._car_rule_eval(
                 case when v_t.role = 'driver' then v_t.origin else c.oo end,          -- symmetric: the ROLES decide, never the searcher
                 case when v_t.role = 'driver' then v_t.dest   else c.od end,
                 case when v_t.role = 'driver' then v_t.route  else c.route end,
                 case when v_t.role = 'driver' then v_t.max_dropoff_m else c.mdo end,
                 case when v_t.role = 'driver' then c.oo       else v_t.origin end,
                 case when v_t.role = 'driver' then c.od       else v_t.dest end,
                 case when v_t.role = 'driver' then c.route    else v_t.route end) e
         where v_car) ev on true
  )
  select s.tid, s.uid, s.d_o, s.d_d, s.dt, s.ov,
         case when v_car and v_cor then
                100.0 * ( v_cd * (1 - least(1.0, s.dm / nullif(v_det, 0)))
                        + v_ct * (1 - s.dt / nullif(v_win, 0))
                        + v_cc * (s.ov / 100.0) ) / nullif(v_cd + v_ct + v_cc, 0)
              when v_car then
                100.0 * ( v_wd * (1 - least(1.0, (s.d_o / nullif(v_roc, 0) + s.d_d / nullif(s.dlim, 0)) / 2.0))
                        + v_wt * (1 - s.dt / nullif(v_win, 0))
                        + v_wo * (s.ov / 100.0) ) / nullif(v_wd + v_wt + v_wo, 0)
              else
                100.0 * ( v_wd * (1 - least(1.0, (s.d_o / v_r_o + s.d_d / v_r_d) / 2.0))
                        + v_wt * (1 - s.dt / nullif(v_win, 0))
                        + v_wo * (s.ov / 100.0) ) / nullif(v_wd + v_wt + v_wo, 0)
         end as score,
         s.dm
    from scored s
   where case when v_car then s.stage = 0 else s.ov >= v_min_ov end
   order by 7 desc, (case when v_car then s.cat end) asc, s.tid asc
   limit p_limit;
end $$;
revoke execute on function public.match_candidates(uuid, int, uuid) from public, anon, authenticated;

-- 5. find_matches. FINAL COLUMN LIST (Dart must match):
--   trip_id, display_name, badges, mode, depart_at, time_diff_min, overlap_pct, approx_distance_m, score,
--   approx_origin_lat, approx_origin_lng, approx_dest_lat, approx_dest_lng, request_status, role, max_dropoff_m
-- approx_detour_m is REMOVED. max_dropoff_m = the candidate DRIVER's effective limit (only when the candidate is a car Driver, i.e.
-- for a Rider searching; NULL otherwise). PRIVACY: for a car RIDER candidate (a Driver is searching) approx_dest_lat/lng are NULL -
-- the Rider's destination never reaches the Driver (blurred or not). Car overlap_pct is rounded to 5 %.
drop function if exists public.find_matches(uuid, int);
create function public.find_matches(p_trip_id uuid, p_limit int default 20)
returns table (trip_id uuid, display_name text, badges jsonb, mode public.travel_mode, depart_at timestamptz,
               time_diff_min int, overlap_pct int, approx_distance_m int, score numeric,
               approx_origin_lat double precision, approx_origin_lng double precision,
               approx_dest_lat double precision, approx_dest_lng double precision,
               request_status public.match_status, role public.trip_role, max_dropoff_m int)
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
         round(c.time_diff_min)::int,
         (case when o.mode = 'car' then (round(c.overlap_pct / 5.0) * 5) else round(c.overlap_pct) end)::int,
         (greatest(1, round(c.origin_distance_m / 500.0)) * 500)::int,
         (round(c.score::numeric / 5.0) * 5)::numeric,
         ST_Y(public.blur_point(o.origin)::geometry), ST_X(public.blur_point(o.origin)::geometry),
         case when o.mode = 'car' and o.role = 'rider' then null else ST_Y(public.blur_point(o.dest)::geometry) end,
         case when o.mode = 'car' and o.role = 'rider' then null else ST_X(public.blur_point(o.dest)::geometry) end,
         (select case when m.auto_closed then null else m.status end from public.matches m
           where (m.requester_trip_id = p_trip_id and m.target_trip_id = o.id)
              or (m.requester_trip_id = o.id and m.target_trip_id = p_trip_id) limit 1),
         o.role,
         case when o.mode = 'car' and o.role = 'driver' then public._car_dropoff_limit(o.max_dropoff_m) end
    from public.match_candidates(p_trip_id, p_limit) c
    join public.trips o     on o.id  = c.candidate_trip_id
    join public.profiles pr on pr.id = c.candidate_user_id
   order by c.score desc, o.id;
end $$;
-- The visible score is rounded; equal rounded scores order by trip id here. match_candidates itself is fully deterministic.

-- 5b. get_trip_card (0006 body): a car Rider's destination is never returned to the other party (the Driver)
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
         case when t.mode = 'car' and t.role = 'rider' and t.user_id <> auth.uid() then null else ST_Y(public.blur_point(t.dest)::geometry) end,
         case when t.mode = 'car' and t.role = 'rider' and t.user_id <> auth.uid() then null else ST_X(public.blur_point(t.dest)::geometry) end,
         t.role
    from public.trips t join public.profiles pr on pr.id = t.user_id
   where t.id = p_trip_id;
end $$;

-- 6. request_match: 0006 body; changes: (a) the inserted match remembers it was checked with the car predicate (car_rule_checked),
-- (b) matches.dest_distance_m is NOT stored for car (it would tell a Driver how far the Rider's destination is) ----------------------
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

  delete from public.matches m
   where m.status = 'cancelled' and m.auto_closed
     and ((m.requester_trip_id = p_my_trip and m.target_trip_id = p_target_trip)
       or (m.requester_trip_id = p_target_trip and m.target_trip_id = p_my_trip));

  select * into v_dup from public.matches
   where requester_trip_id = p_my_trip and target_trip_id = p_target_trip and requester_id = v_uid;
  if found then
    if v_dup.status in ('pending','accepted') then return v_dup.id; end if;
    raise exception 'GWM_ALREADY_REQUESTED' using errcode = 'P0001';
  end if;

  -- re-check eligibility server-side with the SAME function the search uses (car predicate for car, peer rule otherwise)
  select * into v_c from public.match_candidates(p_my_trip, 1, p_target_trip);
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
                                score, overlap_pct, origin_distance_m, dest_distance_m, time_diff_min, car_rule_checked)
    values (p_my_trip, p_target_trip, v_uid, v_c.candidate_user_id,
            (round(v_c.score::numeric / 5.0) * 5), round(v_c.overlap_pct::numeric, 0),
            (round(v_c.origin_distance_m / 500.0) * 500)::int,
            case when v_me.mode = 'car' then null else (round(v_c.dest_distance_m / 500.0) * 500)::int end,
            round(v_c.time_diff_min::numeric, 1), (v_me.mode = 'car'))
    returning id into v_id;
  exception when unique_violation then
    raise exception 'GWM_ALREADY_REQUESTED' using errcode = 'P0001';
  end;
  return v_id;
end $$;

-- 7. _accept_match (used by respond_match AND by the reverse-request path of request_match): 0006 body + predicate re-check ----------
-- Only rows created by the 0009 request_match (car_rule_checked) are re-evaluated (with the CURRENT config and trip values);
-- older pending rows are honoured as they were.
create or replace function public._accept_match(p_match_id uuid) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_m public.matches%rowtype; v_max int := public.cfg_num('match.max_matches_per_trip')::int;
  v_car boolean; v_lim int; v_rr public.trip_role; v_tr public.trip_role; v_stage int;
begin
  select * into v_m from public.matches where id = p_match_id and status = 'pending';
  if not found then raise exception 'GWM_MATCH_NOT_PENDING' using errcode = 'P0001'; end if;
  perform 1 from public.trips where id in (v_m.requester_trip_id, v_m.target_trip_id) order by id for update;
  select * into v_m from public.matches where id = p_match_id and status = 'pending' for update;
  if not found then raise exception 'GWM_MATCH_NOT_PENDING' using errcode = 'P0001'; end if;
  if exists (select 1 from public.trips where id in (v_m.requester_trip_id, v_m.target_trip_id)
                and (status <> 'scheduled' or deleted_at is not null)) then
    raise exception 'GWM_TRIP_UNAVAILABLE' using errcode = 'P0001';
  end if;

  select (rt.mode = 'car'), rt.role, tt.role into v_car, v_rr, v_tr
    from public.trips rt, public.trips tt where rt.id = v_m.requester_trip_id and tt.id = v_m.target_trip_id;
  if v_car and (v_rr is null or v_tr is null or v_rr = v_tr) then
    raise exception 'GWM_NOT_ELIGIBLE' using errcode = 'P0001';
  end if;
  if v_car and v_m.car_rule_checked then                                   -- NEW (0009): same predicate as the search
    select e.stage into v_stage
      from public.trips d, public.trips r,
           lateral public._car_rule_eval(d.origin, d.dest, d.route, d.max_dropoff_m, r.origin, r.dest, r.route) e
     where d.id = v_m.driver_trip_id and r.id = v_m.rider_trip_id;
    if v_stage is distinct from 0 then raise exception 'GWM_NOT_ELIGIBLE' using errcode = 'P0001'; end if;
  end if;
  v_lim := case when v_car then public.car_seats() else v_max end;

  if (select count(*) from public.matches x where x.status = 'accepted'
        and v_m.requester_trip_id in (x.requester_trip_id, x.target_trip_id)) >= v_lim
  or (select count(*) from public.matches x where x.status = 'accepted'
        and v_m.target_trip_id in (x.requester_trip_id, x.target_trip_id)) >= v_lim then
    raise exception 'GWM_MATCH_LIMIT' using errcode = 'P0001';
  end if;

  update public.matches set status = 'accepted', responded_at = now() where id = p_match_id;
  if v_car then
    update public.matches set status = 'cancelled', responded_at = now(), auto_closed = true
     where status = 'pending' and id <> p_match_id
       and (requester_trip_id in (v_m.requester_trip_id, v_m.target_trip_id)
         or target_trip_id    in (v_m.requester_trip_id, v_m.target_trip_id));
  end if;
  insert into public.chat_messages (match_id, sender_id, kind, body) values (p_match_id, null, 'system', 'system.matched');
end $$;
revoke execute on function public._accept_match(uuid) from public, anon, authenticated;
-- respond_match (0006) is unchanged: accept => _accept_match (same predicate); decline needs no predicate.

-- 8. No-match hint (P1): ONE category, read-only, rate limited ------------------------------------------------------------------
-- returns: 'has_results' | 'none_found' | 'far_destination' | 'far_origin'   (priority far_destination > far_origin > none_found)
-- Considers only trips INSIDE the time window (nothing about trips outside it can be inferred), of the opposite role / compatible
-- mode, not blocked, whose origin lies within match.hint_radius_m of mine. far_destination = some such trip has an acceptable
-- origin but its destination exceeds the applicable limit (car: the DRIVER trip's effective max_dropoff_m; peer: dest radius);
-- far_origin = some such trip has an origin beyond the origin radius. No numbers. In match.car_rule = 'corridor' mode: none_found.
create or replace function public.get_match_hint(p_trip_id uuid) returns text
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
#variable_conflict use_column
declare
  v_uid uuid := auth.uid(); v_t public.trips%rowtype; v_car boolean;
  v_win double precision := public.cfg_num('match.time_window_min');
  v_hrad double precision := public.cfg_num('match.hint_radius_m');
  v_r_o double precision; v_r_d double precision := public.cfg_num('match.dest_radius_m');
  v_compat jsonb := public.cfg('match.mode_compat');
  v_cutoff timestamptz := now() - public.cfg_num('trip.expire_after_min') * interval '1 minute';
  v_fd boolean; v_fo boolean;
begin
  if v_uid is null then raise exception 'GWM_UNAUTHENTICATED' using errcode = '42501'; end if;
  perform public._throttle('match_hint', public.cfg_num('throttle.match_hint_per_min')::int, 60);
  select * into v_t from public.trips where id = p_trip_id and user_id = v_uid and deleted_at is null;
  if not found or v_t.status <> 'scheduled' then raise exception 'GWM_TRIP_NOT_FOUND' using errcode = 'P0001'; end if;
  v_car := (v_t.mode = 'car');
  if v_car and v_t.role is null then return 'none_found'; end if;
  if exists (select 1 from public.match_candidates(p_trip_id, 1)) then return 'has_results'; end if;
  if v_car and (public.cfg('match.car_rule') #>> '{}') = 'corridor' then return 'none_found'; end if;
  v_r_o := case when v_car then public.cfg_num('match.car_origin_radius_m') else public.cfg_num('match.origin_radius_m') end;

  select coalesce(bool_or(not x.far_o and x.far_d), false), coalesce(bool_or(x.far_o), false) into v_fd, v_fo
  from (
    select ST_Distance(o.origin, v_t.origin) > v_r_o as far_o,
           ST_Distance(o.dest, v_t.dest) >
             case when not v_car then v_r_d
                  when v_t.role = 'driver' then public._car_dropoff_limit(v_t.max_dropoff_m)
                  else public._car_dropoff_limit(o.max_dropoff_m) end as far_d
      from public.trips o
      join public.profiles p on p.id = o.user_id and p.deleted_at is null
     where o.status = 'scheduled' and o.deleted_at is null and o.depart_at > v_cutoff and o.user_id <> v_uid
       and o.depart_at between v_t.depart_at - v_win * interval '1 minute' and v_t.depart_at + v_win * interval '1 minute'
       and ST_DWithin(o.origin, v_t.origin, v_hrad)
       and case when v_car then o.mode = 'car' and o.role is not null and o.role <> v_t.role
                else o.mode <> 'car' and (v_compat -> v_t.mode::text) @> to_jsonb(o.mode::text) end
       and not exists (select 1 from public.blocks b
                        where (b.blocker_id = v_uid and b.blocked_id = o.user_id) or (b.blocker_id = o.user_id and b.blocked_id = v_uid))
  ) x;
  return case when v_fd then 'far_destination' when v_fo then 'far_origin' else 'none_found' end;
end $$;

-- 9. US-22 avatars ---------------------------------------------------------------------------------------------------------------
-- 9a. purge queue: the DATABASE must not delete storage objects itself (Supabase blocks direct storage.objects deletes and the
-- blob would be orphaned). Rows are drained by a service-role job through the Storage API (claim -> remove -> complete).
create table if not exists public.storage_purge_queue (
  id         uuid primary key default gen_random_uuid(),
  bucket     text not null check (bucket in ('avatars','vehicle-photos')),
  path       text not null,
  reason     text not null check (reason in ('avatar_cleared','account_deleted','moderation')),
  claimed_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.storage_purge_queue enable row level security;
revoke all on public.storage_purge_queue from anon, authenticated;
create index if not exists storage_purge_queue_open_idx on public.storage_purge_queue (created_at);

-- rows whose path is referenced again (user re-uploaded the fixed avatar path) are skipped and dropped, never deleted from storage
create or replace function public.claim_storage_purge(p_limit int default 50)
returns table (id uuid, bucket text, path text)
language plpgsql volatile security definer set search_path = public, pg_temp as $$
begin
  delete from public.storage_purge_queue q
   where q.bucket = 'avatars' and exists (select 1 from public.profiles p where p.avatar_path = q.path);
  return query
  with c as (
    select q.id from public.storage_purge_queue q
     where q.claimed_at is null or q.claimed_at < now() - interval '15 minutes'
     order by q.created_at limit least(greatest(coalesce(p_limit, 50), 1), 500) for update skip locked)
  update public.storage_purge_queue q set claimed_at = now() from c where q.id = c.id
  returning q.id, q.bucket, q.path;
end $$;
create or replace function public.complete_storage_purge(p_ids uuid[]) returns int
language sql volatile security definer set search_path = public, pg_temp as $$
  with d as (delete from public.storage_purge_queue where id = any (p_ids) returning 1) select count(*)::int from d
$$;
revoke execute on function public.claim_storage_purge(int), public.complete_storage_purge(uuid[]) from public, anon, authenticated;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.claim_storage_purge(int), public.complete_storage_purge(uuid[]) to service_role;
  end if;
end $$;

-- 9b. profiles.avatar_path guard: fixed object name "<uid>/avatar.jpg" (one photo per user; replace = overwrite => no stale file);
-- a NEW path must point at an existing image/jpeg object <= avatar.max_bytes (checked only when storage.objects has metadata).
-- Clearing / replacing to NULL enqueues the storage delete (also runs for request_account_deletion, which nulls the column).
create or replace function public.profiles_avatar_guard() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_mime text; v_size bigint; v_found boolean := false;
begin
  if new.avatar_path is not distinct from old.avatar_path then return new; end if;
  if new.avatar_path is not null then
    if new.avatar_path <> new.id::text || '/avatar.jpg' then raise exception 'GWM_AVATAR_INVALID' using errcode = 'P0001'; end if;
    if to_regclass('storage.objects') is not null then
      execute 'select true, o.metadata ->> ''mimetype'', nullif(o.metadata ->> ''size'', '''')::bigint from storage.objects o where o.bucket_id = ''avatars'' and o.name = $1'
        into v_found, v_mime, v_size using new.avatar_path;
      if not coalesce(v_found, false) then raise exception 'GWM_AVATAR_INVALID' using errcode = 'P0001'; end if;
      if (v_mime is not null and v_mime <> 'image/jpeg')
         or (v_size is not null and v_size > public.cfg_num('avatar.max_bytes')) then
        raise exception 'GWM_AVATAR_INVALID' using errcode = 'P0001';
      end if;
    end if;
  end if;
  if new.avatar_path is null and old.avatar_path is not null then
    insert into public.storage_purge_queue (bucket, path, reason) values ('avatars', old.avatar_path, 'avatar_cleared');
  end if;
  return new;
end $$;
drop trigger if exists trg_profiles_avatar_guard on public.profiles;
create trigger trg_profiles_avatar_guard before update of avatar_path on public.profiles
  for each row execute function public.profiles_avatar_guard();
revoke execute on function public.profiles_avatar_guard() from public, anon, authenticated;

-- 9c. content_reports (avatar + review reports; also the reporting channel shared by US-22 / US-26)
do $$ begin create type public.content_report_kind as enum ('avatar','review'); exception when duplicate_object then null; end $$;
do $$ begin create type public.content_report_status as enum ('open','upheld','dismissed'); exception when duplicate_object then null; end $$;
create table if not exists public.content_reports (
  id               uuid primary key default gen_random_uuid(),
  kind             public.content_report_kind not null,
  reporter_id      uuid references public.profiles(id) on delete set null,    -- NULLed on the reporter's account deletion
  reported_user_id uuid references public.profiles(id) on delete cascade,     -- avatar: owner; review: NULL (reviewer stays anonymous)
  match_id         uuid references public.matches(id) on delete set null,
  review_id         uuid,                                                      -- FK added after reviews exists
  reason           public.report_reason not null,
  status           public.content_report_status not null default 'open',
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  resolved_at      timestamptz,
  check ((kind = 'avatar' and reported_user_id is not null and review_id is null)
      or (kind = 'review' and review_id is not null))
);
alter table public.content_reports enable row level security;
revoke all on public.content_reports from anon, authenticated;
grant select on public.content_reports to authenticated;
drop policy if exists content_reports_select on public.content_reports;
create policy content_reports_select on public.content_reports for select to authenticated
  using (reporter_id = (select auth.uid()) or public.is_admin());
create unique index if not exists content_reports_avatar_uq on public.content_reports (reporter_id, reported_user_id) where kind = 'avatar';
create unique index if not exists content_reports_review_uq on public.content_reports (reporter_id, review_id) where kind = 'review';
create index if not exists content_reports_open_idx on public.content_reports (created_at) where status = 'open';   -- moderator queue
create index if not exists content_reports_reporter_idx on public.content_reports (reporter_id) where reporter_id is not null;   -- FK (+ reporter's own list)
create index if not exists content_reports_reported_idx on public.content_reports (reported_user_id) where reported_user_id is not null;   -- FK (cascade on account hard-delete)
create index if not exists content_reports_match_idx on public.content_reports (match_id) where match_id is not null;   -- FK
drop trigger if exists trg_content_reports_updated_at on public.content_reports;
create trigger trg_content_reports_updated_at before update on public.content_reports
  for each row execute function public.update_updated_at();

-- 9d. visibility: the SAME window as are_matched (accepted match, both trips active or ended <= 24 h) + no block + not hidden
-- by the viewer's own report + owner has a photo. Search results / pending / declined / cancelled-before-boarding never qualify.
create or replace function public.can_view_avatar(p_owner uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select auth.uid() is not null and p_owner is not null and p_owner <> auth.uid()
     and exists (select 1 from public.profiles p where p.id = p_owner and p.deleted_at is null and p.avatar_path is not null)
     and public.are_matched(auth.uid(), p_owner)
     and not exists (select 1 from public.blocks b
                      where (b.blocker_id = p_owner and b.blocked_id = auth.uid())
                         or (b.blocker_id = auth.uid() and b.blocked_id = p_owner))
     and not exists (select 1 from public.content_reports r
                      where r.kind = 'avatar' and r.reporter_id = auth.uid() and r.reported_user_id = p_owner)
$$;

-- storage SELECT: owner reads own folder; a partner reads ONLY the object currently referenced by the owner's avatar_path
create or replace function public._avatar_object_visible(p_name text) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select split_part(p_name, '/', 1) = auth.uid()::text
      or (public.can_view_avatar(public.safe_uuid(split_part(p_name, '/', 1)))
          and exists (select 1 from public.profiles p
                       where p.id = public.safe_uuid(split_part(p_name, '/', 1)) and p.avatar_path = p_name))
$$;
grant execute on function public.can_view_avatar(uuid), public._avatar_object_visible(text) to authenticated;
revoke execute on function public.can_view_avatar(uuid), public._avatar_object_visible(text) from public, anon;

-- 9e. storage bucket + policies (jpeg only, <= 512 KB, fixed name in own folder). The size term of the write policies only
-- applies when the Storage API supplies metadata; the hard limit is the bucket file_size_limit (+ trigger check above).
do $do$
begin
  if to_regclass('storage.buckets') is not null then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('avatars', 'avatars', false, 524288, array['image/jpeg'])
    on conflict (id) do update set public = false, file_size_limit = 524288, allowed_mime_types = array['image/jpeg'];

    drop policy if exists avatars_read_own_or_partner on storage.objects;
    create policy avatars_read_own_or_partner on storage.objects for select to authenticated
      using (bucket_id = 'avatars' and public._avatar_object_visible(name));
    drop policy if exists avatars_write_own on storage.objects;
    create policy avatars_write_own on storage.objects for insert to authenticated
      with check (bucket_id = 'avatars' and name = (select auth.uid())::text || '/avatar.jpg'
                  and coalesce((metadata ->> 'size')::bigint, 0) <= 524288);
    drop policy if exists avatars_update_own on storage.objects;
    create policy avatars_update_own on storage.objects for update to authenticated
      using (bucket_id = 'avatars' and name = (select auth.uid())::text || '/avatar.jpg')
      with check (bucket_id = 'avatars' and name = (select auth.uid())::text || '/avatar.jpg'
                  and coalesce((metadata ->> 'size')::bigint, 0) <= 524288);
    drop policy if exists avatars_delete_own on storage.objects;
    create policy avatars_delete_own on storage.objects for delete to authenticated
      using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
  end if;
end $do$;

-- 9f. RPCs
create or replace function public.set_my_avatar(p_path text default null) returns void
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'GWM_UNAUTHENTICATED' using errcode = '42501'; end if;
  perform public._throttle('avatar_write', public.cfg_num('throttle.avatar_write_per_hour')::int, 3600);
  update public.profiles set avatar_path = p_path where id = v_uid and deleted_at is null;     -- trigger validates / enqueues purge
  if not found then raise exception 'GWM_PROFILE_UNAVAILABLE' using errcode = 'P0001'; end if;
end $$;

-- returns the storage path only while the partner may be seen; otherwise NULL (=> initials fallback). The client then calls
-- Storage createSignedUrl(path, <= 300 s) which the SELECT policy authorises with the same predicate.
create or replace function public.get_partner_avatar_path(p_match_id uuid) returns text
language sql stable security definer set search_path = public, pg_temp as $$
  select p.avatar_path
    from public.matches m
    join public.profiles p on p.id = case when m.requester_id = auth.uid() then m.target_id else m.requester_id end
   where m.id = p_match_id and auth.uid() in (m.requester_id, m.target_id)
     and public.can_view_avatar(p.id)
$$;

create or replace function public.report_avatar(p_match_id uuid, p_reason public.report_reason) returns void
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid(); v_other uuid;
begin
  if v_uid is null then raise exception 'GWM_UNAUTHENTICATED' using errcode = '42501'; end if;
  perform public._throttle('content_report', public.cfg_num('throttle.report_per_hour')::int, 3600);
  select case when m.requester_id = v_uid then m.target_id else m.requester_id end into v_other
    from public.matches m where m.id = p_match_id and v_uid in (m.requester_id, m.target_id);
  -- replay of an already filed report stays a no-op (the photo is hidden after the first report, so can_view_avatar is false by then)
  if v_other is null or not (public.can_view_avatar(v_other) or exists (
       select 1 from public.content_reports r where r.kind = 'avatar' and r.reporter_id = v_uid and r.reported_user_id = v_other)) then
    raise exception 'GWM_REPORT_INVALID' using errcode = 'P0001';
  end if;
  insert into public.content_reports (kind, reporter_id, reported_user_id, match_id, reason)
  values ('avatar', v_uid, v_other, p_match_id, p_reason)
  on conflict (reporter_id, reported_user_id) where kind = 'avatar' do nothing;               -- idempotent; photo is hidden from now on
end $$;

-- moderator (JWT app_metadata.role = admin, same is_admin() as the rest of the app): remove the photo everywhere
create or replace function public.admin_remove_avatar(p_user uuid) returns void
language plpgsql volatile security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'GWM_FORBIDDEN' using errcode = '42501'; end if;
  update public.profiles set avatar_path = null where id = p_user;                            -- trigger enqueues the storage delete
  update public.content_reports set status = 'upheld', resolved_at = now() where kind = 'avatar' and reported_user_id = p_user and status = 'open';
end $$;

-- 10. US-26 reviews ---------------------------------------------------------------------------------------------------------------
create table if not exists public.review_tags (
  tag          text not null check (tag ~ '^[a-z_]{2,30}$'),
  reviewee_role public.trip_role not null,                 -- role of the person being reviewed
  sort         smallint not null default 0,
  primary key (tag, reviewee_role)
);
alter table public.review_tags enable row level security;
revoke all on public.review_tags from anon, authenticated;
grant select on public.review_tags to authenticated;
drop policy if exists review_tags_select on public.review_tags;
create policy review_tags_select on public.review_tags for select to authenticated using (true);
insert into public.review_tags (tag, reviewee_role, sort) values
  ('on_time','driver',1), ('polite','driver',2), ('safe_driving','driver',3), ('vehicle_matches','driver',4), ('late','driver',5), ('not_as_agreed','driver',6),
  ('on_time','rider',1),  ('polite','rider',2),  ('late','rider',5),  ('not_as_agreed','rider',6)
on conflict do nothing;

create table if not exists public.reviews (
  id          uuid primary key default gen_random_uuid(),
  match_id    uuid not null references public.matches(id) on delete cascade,
  reviewer_id uuid references public.profiles(id) on delete set null,    -- NULLed when the reviewer deletes the account
  reviewee_id uuid not null references public.profiles(id) on delete cascade,
  role        public.trip_role not null,                                  -- role of the REVIEWEE in that trip (= direction)
  stars       smallint not null check (stars between 1 and 5),
  comment     text check (comment is null or (char_length(comment) between 1 and 200 and comment !~ '[[:cntrl:]]')),
  reveal_at   timestamptz not null,          -- window close = first completed trip end + review.window_days (also the blind timeout)
  revealed_at timestamptz,                   -- stamped when both directions exist, or by _reveal_due_reviews() at reveal_at
  held_at     timestamptz,                   -- set by report_review: hidden from the reviewee, not counted
  removed_at  timestamptz,                   -- moderator decision: not counted, not shown
  created_at  timestamptz not null default now(),
  check (reviewer_id is null or reviewer_id <> reviewee_id),
  unique (match_id, role),                   -- one review per match per direction
  unique (id, role)                          -- target of the tag junction's composite FK
);
alter table public.reviews enable row level security;
revoke all on public.reviews from anon, authenticated;
drop policy if exists reviews_admin_select on public.reviews;
create policy reviews_admin_select on public.reviews for select to authenticated using (public.is_admin());
-- no client policy / grant: reading and writing go through the RPCs below (no reviewer id ever leaves the server)
create index if not exists reviews_reviewee_idx on public.reviews (reviewee_id, role);              -- FK + received list + aggregate (cascade delete must find removed rows too)
create index if not exists reviews_reviewer_idx on public.reviews (reviewer_id) where reviewer_id is not null;
create index if not exists reviews_reveal_due_idx on public.reviews (reveal_at) where revealed_at is null;

do $$ begin
  alter table public.content_reports add constraint content_reports_review_fk
    foreign key (review_id) references public.reviews(id) on delete cascade;
exception when duplicate_object then null; end $$;
create index if not exists content_reports_review_idx on public.content_reports (review_id) where review_id is not null;   -- FK

-- tags: junction (1NF: no multi-valued column). The composite FKs make the DB itself enforce that a tag belongs to the allow-list
-- of the REVIEWEE role (review_tags) and that `role` here equals reviews.role; the number of tags (<= review.max_tags) and
-- duplicates are checked by submit_review.
create table if not exists public.review_selected_tags (
  review_id uuid not null,
  role      public.trip_role not null,                        -- intentional copy of reviews.role (needed by the two composite FKs)
  tag       text not null,
  primary key (review_id, tag),
  foreign key (review_id, role) references public.reviews (id, role) on delete cascade,
  foreign key (tag, role) references public.review_tags (tag, reviewee_role) on delete restrict
);
alter table public.review_selected_tags enable row level security;
revoke all on public.review_selected_tags from anon, authenticated;
drop policy if exists review_selected_tags_admin_select on public.review_selected_tags;
create policy review_selected_tags_admin_select on public.review_selected_tags for select to authenticated using (public.is_admin());
create index if not exists review_selected_tags_tag_idx on public.review_selected_tags (tag, role);   -- FK to review_tags

-- aggregate per user per role: only REVEALED, not held/removed, >= review.min_count_for_aggregate. INTERNAL (owner only):
-- exposed to clients only through get_user_rating().
create or replace view public.review_aggregates as
  select r.reviewee_id as user_id, r.role, count(*)::int as review_count, round(avg(r.stars)::numeric, 1) as avg_stars
    from public.reviews r
   where (r.revealed_at is not null or r.reveal_at <= now()) and r.held_at is null and r.removed_at is null
   group by r.reviewee_id, r.role
  having count(*) >= public.cfg_num('review.min_count_for_aggregate')::int;
revoke all on public.review_aggregates from anon, authenticated;

-- eligibility helper (single definition used by submit + state): returns the reason category or NULL when allowed
create or replace function public._review_check(p_match_id uuid, p_uid uuid)
returns table (reason text, reviewee uuid, reviewee_role public.trip_role, closes_at timestamptz)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_m public.matches%rowtype; v_dt public.trips%rowtype; v_rt public.trips%rowtype; v_mine public.trips%rowtype; v_open timestamptz;
begin
  select * into v_m from public.matches where id = p_match_id and p_uid in (requester_id, target_id);
  if not found or v_m.driver_trip_id is null or v_m.rider_trip_id is null then reason := 'not_found'; return next; return; end if;
  select * into v_dt from public.trips where id = v_m.driver_trip_id;
  select * into v_rt from public.trips where id = v_m.rider_trip_id;
  v_mine := case when v_dt.user_id = p_uid then v_dt else v_rt end;
  reviewee := case when v_dt.user_id = p_uid then v_rt.user_id else v_dt.user_id end;
  reviewee_role := case when v_dt.user_id = p_uid then 'rider'::public.trip_role else 'driver'::public.trip_role end;
  v_open := least(case when v_dt.status = 'completed' then v_dt.ended_at end, case when v_rt.status = 'completed' then v_rt.ended_at end);
  closes_at := v_open + public.cfg_num('review.window_days') * interval '1 day';
  if v_m.status <> 'accepted' or v_m.boarded_at is null then reason := 'not_boarded';
  elsif v_mine.status <> 'completed' then reason := 'trip_not_completed';
  elsif not exists (select 1 from public.profiles p where p.id = reviewee and p.deleted_at is null) then reason := 'partner_unavailable';
  elsif exists (select 1 from public.reviews r where r.match_id = p_match_id and r.role = reviewee_role) then reason := 'already_submitted';
  elsif now() >= closes_at then reason := 'window_closed';
  else reason := null; end if;
  return next;
end $$;

create or replace function public.submit_review(p_match_id uuid, p_stars int, p_tags text[] default '{}', p_comment text default null)
returns uuid
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid(); v_c record; v_id uuid; v_comment text; v_tags text[]; v_role_other public.trip_role;
begin
  if v_uid is null then raise exception 'GWM_UNAUTHENTICATED' using errcode = '42501'; end if;
  perform public._throttle('review_write', public.cfg_num('throttle.review_write_per_hour')::int, 3600);
  select * into v_c from public._review_check(p_match_id, v_uid);
  if v_c.reason = 'already_submitted' then raise exception 'GWM_REVIEW_DUPLICATE' using errcode = 'P0001'; end if;
  if v_c.reason = 'window_closed' then raise exception 'GWM_REVIEW_WINDOW_CLOSED' using errcode = 'P0001'; end if;
  if v_c.reason is not null then raise exception 'GWM_REVIEW_NOT_ELIGIBLE' using errcode = 'P0001'; end if;

  v_comment := nullif(regexp_replace(btrim(coalesce(p_comment, '')), '\s+', ' ', 'g'), '');
  v_tags := coalesce(p_tags, '{}');
  if p_stars is null or p_stars not between 1 and 5 or char_length(coalesce(v_comment, '')) > 200
     or coalesce(v_comment, '') ~ '[[:cntrl:]]' then
    raise exception 'GWM_REVIEW_INVALID' using errcode = 'P0001';
  end if;
  if cardinality(v_tags) > public.cfg_num('review.max_tags')::int
     or (select count(distinct t) from unnest(v_tags) t) <> cardinality(v_tags) then
    raise exception 'GWM_REVIEW_INVALID' using errcode = 'P0001';
  end if;
  begin
    insert into public.reviews (match_id, reviewer_id, reviewee_id, role, stars, comment, reveal_at)
    values (p_match_id, v_uid, v_c.reviewee, v_c.reviewee_role, p_stars::smallint, v_comment, v_c.closes_at)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'GWM_REVIEW_DUPLICATE' using errcode = 'P0001';
  end;
  begin                                                       -- allow-list enforced by the composite FK to review_tags
    insert into public.review_selected_tags (review_id, role, tag)
    select v_id, v_c.reviewee_role, t from unnest(v_tags) t;
  exception when foreign_key_violation then
    raise exception 'GWM_REVIEW_INVALID' using errcode = 'P0001';
  end;
  v_role_other := case v_c.reviewee_role when 'driver' then 'rider' else 'driver' end;
  if exists (select 1 from public.reviews r where r.match_id = p_match_id and r.role = v_role_other) then      -- both directions in => reveal both
    update public.reviews set revealed_at = now() where match_id = p_match_id and revealed_at is null;
  end if;
  return v_id;
end $$;

-- state for the review screen. Never says whether the OTHER side already submitted (blind).
create or replace function public.get_my_review_state(p_match_id uuid)
returns table (can_review boolean, reason text, closes_at timestamptz, my_stars int, my_tags text[], my_comment text)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_c record;
begin
  if auth.uid() is null then raise exception 'GWM_UNAUTHENTICATED' using errcode = '42501'; end if;
  select * into v_c from public._review_check(p_match_id, auth.uid());
  can_review := v_c.reason is null;
  reason := v_c.reason;
  closes_at := case when v_c.reason = 'not_found' then null else v_c.closes_at end;
  select r.stars, coalesce((select array_agg(st.tag order by st.tag) from public.review_selected_tags st where st.review_id = r.id), '{}'),
         r.comment into my_stars, my_tags, my_comment
    from public.reviews r where r.match_id = p_match_id and r.reviewer_id = auth.uid();
  return next;
end $$;

-- reviews ABOUT me: only revealed, not held/removed; no reviewer id, no match-side data other than the match id
create or replace function public.get_reviews_received(p_limit int default 50)
returns table (review_id uuid, match_id uuid, role public.trip_role, stars int, tags text[], comment text, created_at timestamptz)
language sql stable security definer set search_path = public, pg_temp as $$
  select r.id, r.match_id, r.role, r.stars::int,
         coalesce((select array_agg(st.tag order by st.tag) from public.review_selected_tags st where st.review_id = r.id), '{}'),
         r.comment, r.created_at
    from public.reviews r
   where r.reviewee_id = auth.uid() and (r.revealed_at is not null or r.reveal_at <= now())
     and r.held_at is null and r.removed_at is null
   order by r.created_at desc, r.id
   limit least(greatest(coalesce(p_limit, 50), 1), 100)
$$;

-- aggregate for a user card: one row per role; below the threshold only enough=false (no average, no count)
create or replace function public.get_user_rating(p_user uuid)
returns table (role public.trip_role, enough boolean, review_count int, avg_stars numeric)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'GWM_UNAUTHENTICATED' using errcode = '42501'; end if;
  if not (p_user = auth.uid() or public.is_admin()
          or exists (select 1 from public.matches m where m.status in ('pending','accepted','cancelled')
                       and ((m.requester_id = auth.uid() and m.target_id = p_user) or (m.target_id = auth.uid() and m.requester_id = p_user)))
          or (public.cfg_bool('review.show_in_search')
              and exists (select 1 from public.trips t where t.user_id = p_user and t.status = 'scheduled' and t.deleted_at is null))) then
    raise exception 'GWM_FORBIDDEN' using errcode = '42501';
  end if;
  if exists (select 1 from public.blocks b where (b.blocker_id = p_user and b.blocked_id = auth.uid())
                                             or (b.blocker_id = auth.uid() and b.blocked_id = p_user)) then
    raise exception 'GWM_FORBIDDEN' using errcode = '42501';
  end if;
  return query
  select ro.r, (a.user_id is not null), a.review_count, a.avg_stars
    from (values ('driver'::public.trip_role), ('rider'::public.trip_role)) ro(r)
    left join public.review_aggregates a on a.user_id = p_user and a.role = ro.r;
end $$;

create or replace function public.report_review(p_review_id uuid, p_reason public.report_reason) returns void
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid(); v_match uuid;
begin
  if v_uid is null then raise exception 'GWM_UNAUTHENTICATED' using errcode = '42501'; end if;
  perform public._throttle('content_report', public.cfg_num('throttle.report_per_hour')::int, 3600);
  select r.match_id into v_match from public.reviews r
   where r.id = p_review_id and r.reviewee_id = v_uid and (r.revealed_at is not null or r.reveal_at <= now())
     and r.held_at is null and r.removed_at is null for update;
  if not found then raise exception 'GWM_REPORT_INVALID' using errcode = 'P0001'; end if;
  update public.reviews set held_at = now() where id = p_review_id;
  insert into public.content_reports (kind, reporter_id, reported_user_id, match_id, review_id, reason)
  values ('review', v_uid, null, v_match, p_review_id, p_reason)
  on conflict (reporter_id, review_id) where kind = 'review' do update
    set status = 'open', resolved_at = null, reason = excluded.reason where public.content_reports.status <> 'open';   -- re-report after a dismissal re-opens it (the review is held again, a moderator must decide)
end $$;

create or replace function public.admin_resolve_review_report(p_report_id uuid, p_uphold boolean) returns void
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_rev uuid;
begin
  if not public.is_admin() then raise exception 'GWM_FORBIDDEN' using errcode = '42501'; end if;
  update public.content_reports set status = (case when p_uphold then 'upheld' else 'dismissed' end)::public.content_report_status, resolved_at = now()
   where id = p_report_id and kind = 'review' and status = 'open' returning review_id into v_rev;
  if not found then raise exception 'GWM_REPORT_INVALID' using errcode = 'P0001'; end if;
  if p_uphold then update public.reviews set removed_at = now() where id = v_rev;
  else update public.reviews set held_at = null where id = v_rev; end if;
end $$;

create or replace function public._reveal_due_reviews() returns int
language sql volatile security definer set search_path = public, pg_temp as $$
  with u as (update public.reviews set revealed_at = reveal_at where revealed_at is null and reveal_at <= now() returning 1)
  select count(*)::int from u
$$;
revoke execute on function public._reveal_due_reviews(), public._review_check(uuid, uuid) from public, anon, authenticated;

-- 11. Account deletion (0008 body) + reviews / reports cleanup; avatar file is enqueued by trg_profiles_avatar_guard -----------------
create or replace function public.request_account_deletion() returns void
language plpgsql security definer set search_path = public, auth, pg_temp as $$
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
  -- NEW (0009): reviews ABOUT the user are deleted; reviews BY the user lose the comment and the author link (stars/tags stay
  -- anonymous in the other side's aggregate - legal to confirm); reports about the user's photo are deleted, reports filed by
  -- the user lose the reporter link (row kept for the moderator).
  delete from public.reviews where reviewee_id = v_uid;
  update public.reviews set comment = null, reviewer_id = null where reviewer_id = v_uid;
  delete from public.content_reports where kind = 'avatar' and reported_user_id = v_uid;
  update public.content_reports set reporter_id = null where reporter_id = v_uid;
  update public.profiles set deleted_at = now(), display_name = 'ผู้ใช้ที่ลบบัญชีแล้ว', avatar_path = null,
         driver_registered_at = null, licence_declared_at = null, licence_declaration_version = null, active_role = 'rider'
   where id = v_uid;
  update auth.users set banned_until = now() + interval '100 years' where id = v_uid;
  delete from auth.sessions where user_id = v_uid;
end $$;

-- 12. purge_expired_data (0006 body) + blind-reveal timeout ---------------------------------------------------------------------
create or replace function public.purge_expired_data() returns jsonb
language plpgsql security definer set search_path = public, extensions, auth, pg_temp as $$
declare
  v_loc_days int := public.cfg_num('retention.location_days')::int;
  v_del_days int := public.cfg_num('retention.account_deletion_days')::int;
  v_sos_days int := public.cfg_num('retention.sos_precise_days')::int;
  v_expired int; v_loc int; v_reduced int; v_trips int; v_users int; v_sos int; v_rev int;
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
  update public.sos_events set vehicle_snapshot = null
   where created_at < now() - v_sos_days * interval '1 day' and vehicle_snapshot is not null;

  delete from public.match_outcomes
   where created_at < now() - public.cfg_num('retention.match_outcome_months') * interval '1 month';

  v_rev := public._reveal_due_reviews();                                                 -- NEW (0009): 7-day blind timeout

  delete from public.trips where deleted_at < now() - v_loc_days * interval '1 day';
  get diagnostics v_trips = row_count;

  delete from public.trip_shares where expires_at < now() - interval '30 days' or revoked_at < now() - interval '30 days';
  delete from public.api_throttle where window_start < now() - interval '1 day';

  delete from auth.users u using public.profiles p
   where p.id = u.id and p.deleted_at < now() - v_del_days * interval '1 day';
  get diagnostics v_users = row_count;

  return jsonb_build_object('expired_trips', v_expired, 'deleted_locations', v_loc, 'reduced_trips', v_reduced,
                            'reduced_sos', v_sos, 'deleted_trips', v_trips, 'deleted_users', v_users, 'revealed_reviews', v_rev);
end $$;

-- 13. Export (0008 body) + reviews -------------------------------------------------------------------------------------------------
create or replace function public.export_my_data() returns jsonb
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select jsonb_build_object(
    'profile',  (select to_jsonb(p) - 'driver_registered' - 'driver_registered_at' - 'licence_declared_at'
                        - 'licence_declaration_version' - 'active_role'
                   from public.profiles p where p.id = auth.uid()),
    'driver_registration', (select jsonb_build_object(
                        'registered', p.driver_registered, 'registered_at', p.driver_registered_at,
                        'licence_declared_at', p.licence_declared_at,
                        'licence_declaration_version', p.licence_declaration_version,
                        'active_role', p.active_role)
                   from public.profiles p where p.id = auth.uid()),
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
    'vehicle', (select to_jsonb(v) from public.vehicles v where v.user_id = auth.uid()),
    'reviews_written', coalesce((select jsonb_agg(jsonb_build_object('match_id', r.match_id, 'role_reviewed', r.role, 'stars', r.stars,
                          'tags', coalesce((select array_agg(st.tag order by st.tag) from public.review_selected_tags st where st.review_id = r.id), '{}'), 'comment', r.comment, 'created_at', r.created_at))
                 from public.reviews r where r.reviewer_id = auth.uid()), '[]'),
    'reviews_received', coalesce((select jsonb_agg(jsonb_build_object('match_id', r.match_id, 'role', r.role, 'stars', r.stars,
                          'tags', coalesce((select array_agg(st.tag order by st.tag) from public.review_selected_tags st where st.review_id = r.id), '{}'), 'comment', r.comment, 'created_at', r.created_at))
                 from public.reviews r where r.reviewee_id = auth.uid() and (r.revealed_at is not null or r.reveal_at <= now())
                  and r.held_at is null and r.removed_at is null), '[]'))
$$;

-- 14. Grants (+ index for the neighbourhood predicate) ---------------------------------------------------------------------------------------------------------------------
-- open-trip lookup by mode/role/time (match_candidates + hint): complements the existing partial GiST indexes on origin / dest
create index if not exists trips_open_mode_role_depart_idx on public.trips (mode, role, depart_at) where status = 'scheduled' and deleted_at is null;
revoke execute on function public.get_trip_card(uuid) from public, anon;
grant execute on function public.get_trip_card(uuid) to authenticated;
revoke execute on function public.find_matches(uuid, int), public.get_match_hint(uuid), public.set_my_avatar(text),
                           public.get_partner_avatar_path(uuid), public.report_avatar(uuid, public.report_reason),
                           public.admin_remove_avatar(uuid), public.submit_review(uuid, int, text[], text),
                           public.get_my_review_state(uuid), public.get_reviews_received(int), public.get_user_rating(uuid),
                           public.report_review(uuid, public.report_reason), public.admin_resolve_review_report(uuid, boolean),
                           public.request_match(uuid, uuid), public.request_account_deletion(), public.export_my_data(),
                           public.purge_expired_data() from public, anon;
grant execute on function public.find_matches(uuid, int), public.get_match_hint(uuid), public.set_my_avatar(text),
                          public.get_partner_avatar_path(uuid), public.report_avatar(uuid, public.report_reason),
                          public.admin_remove_avatar(uuid), public.submit_review(uuid, int, text[], text),
                          public.get_my_review_state(uuid), public.get_reviews_received(int), public.get_user_rating(uuid),
                          public.report_review(uuid, public.report_reason), public.admin_resolve_review_report(uuid, boolean),
                          public.request_match(uuid, uuid), public.request_account_deletion(), public.export_my_data() to authenticated;
-- purge_expired_data stays cron/service only (as in 0002/0006): revoked from authenticated too
revoke execute on function public.purge_expired_data() from authenticated;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.purge_expired_data() to service_role;
  end if;
end $$;

notify pgrst, 'reload schema';
