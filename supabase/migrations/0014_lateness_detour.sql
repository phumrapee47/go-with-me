-- =====================================================================================================================
-- GOWITHME migration 0014 (round 7, Stage C - DRAFT, NOT applied anywhere): docs/design-roles.md section 15
--   US-49  Lateness detection & no-fault cancellation: a NEW distinguishable match_outcomes.reason
--          ('no_fault_lateness') + a NEW RPC cancel_match_no_fault(p_match_id), atomic/idempotent/first-write-wins,
--          server re-verifies "overdue" itself (never trusts the client), reuses the existing push_outbox
--          'match_cancelled' kind (no new push kind).
--   US-50  Route detour tolerance: a NEW trips.detour_tolerance_m column (separate from max_dropoff_m), a NEW
--          PostGIS approximation of the OSRM route-length delta, and an OR-extension of the existing car
--          'neighbourhood' destination check in _car_rule_eval (used by match_candidates / _accept_match, and
--          transitively by request_match via match_candidates(p_only_trip)).
--   US-47  No schema change (see design-roles.md 15.6 - CO2 is a pure client-side calculation).
-- Redefines (latest definitions read first): match_outcomes (0006, CHECK constraint), _car_rule_eval (0009),
--   match_candidates (0012, latest body), _accept_match (0009, latest body).
-- Idempotent: safe to re-run. Every new function is SECURITY DEFINER with a pinned search_path; grants are explicit.
-- Q13 (closed, see docs/design-roles.md #15.1): _review_check (0009) already requires v_m.status = 'accepted' AND
--   v_m.boarded_at IS NOT NULL. A no-fault lateness cancel happens strictly BEFORE boarding (the two sides have not
--   met yet), so boarded_at stays NULL and review eligibility already fails on 'not_boarded' regardless of the
--   match_outcomes.reason value. The new reason value is for AUDIT clarity only; it changes no eligibility logic.
-- =====================================================================================================================

-- =====================================================================================================================
-- PART 1 - US-49: lateness detection & no-fault cancellation
-- =====================================================================================================================

-- 1. Config ------------------------------------------------------------------------------------------------------------
insert into public.app_config (key, value, description, is_public) values
  ('lateness.overdue_min',          '10',   'US-49/Q11(a): overdue when now() > greatest(driver.depart_at, rider.depart_at) + this many minutes', true),
  ('lateness.eta_stall_window_min', '5',    'US-49/Q11(b): look at trip_locations within this many minutes back', false),
  ('lateness.eta_stall_m',          '100',  'US-49/Q11(b): overdue when the straight-line distance to the meeting point has not shrunk by at least this many metres across the last 3 samples in the window', false)
on conflict (key) do nothing;

-- 2. match_outcomes.reason: add 'no_fault_lateness' (distinct from cancelled_by_driver/cancelled_by_rider) ----------------
-- The constraint created in 0006 is unnamed (Postgres auto-named it match_outcomes_reason_check); replace it in place.
alter table public.match_outcomes drop constraint if exists match_outcomes_reason_check;
alter table public.match_outcomes add constraint match_outcomes_reason_check
  check (reason in ('cancelled_by_driver','cancelled_by_rider','rider_no_show','trip_ended','trip_expired','no_fault_lateness'));

-- 3. _match_overdue: server-side, non-client-trusted re-verification of Q11's two conditions -------------------------------
-- Car matches only (driver_trip_id/rider_trip_id, boarded_at are car concepts - see design-roles.md section 1).
-- Both trips must be in_progress (same precondition mark_boarded uses: "waiting to meet" implies both have departed).
-- (a) now() > greatest(driver.depart_at, rider.depart_at) + lateness.overdue_min minutes - the "agreed time" proxy:
--     there is no separate stored pickup TIME (only a pickup/meeting POINT via matches.meeting_point), so the later of
--     the two matched trips' own depart_at is used as the closest available proxy for "when they meant to meet"
--     (documented assumption - see docs/design-roles.md #15.4 open questions).
-- (b) 3 consecutive trip_locations samples (of EITHER trip) inside the window whose straight-line distance to the
--     meeting point (matches.meeting_point, falling back to the rider's origin/pickup point when not yet set) has not
--     shrunk by >= lateness.eta_stall_m metres between the oldest and the newest of those 3 samples.
-- Returns false (never overdue) when the match is not car mode, not accepted, already boarded, or either trip is not
-- in_progress - i.e. this predicate can only ever narrow eligibility, never widen it.
create or replace function public._match_overdue(p_match_id uuid) returns boolean
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare
  v_m public.matches%rowtype;
  v_d public.trips%rowtype;
  v_r public.trips%rowtype;
  v_meet geography;
  v_late_min double precision := public.cfg_num('lateness.overdue_min');
  v_win_min  double precision := public.cfg_num('lateness.eta_stall_window_min');
  v_stall_m  double precision := public.cfg_num('lateness.eta_stall_m');
  v_stalled boolean;
begin
  select * into v_m from public.matches where id = p_match_id and status = 'accepted' and boarded_at is null;
  if not found or v_m.driver_trip_id is null or v_m.rider_trip_id is null then return false; end if;
  select * into v_d from public.trips where id = v_m.driver_trip_id;
  select * into v_r from public.trips where id = v_m.rider_trip_id;
  if v_d.status <> 'in_progress' or v_r.status <> 'in_progress' then return false; end if;

  if now() > greatest(v_d.depart_at, v_r.depart_at) + (v_late_min * interval '1 minute') then
    return true;                                                             -- Q11 (a)
  end if;

  v_meet := coalesce(v_m.meeting_point, v_r.origin);
  with recent as (
    select tl.trip_id, ST_Distance(tl.location, v_meet) as d,
           row_number() over (partition by tl.trip_id order by tl.recorded_at desc) as rn
      from public.trip_locations tl
     where tl.trip_id in (v_d.id, v_r.id)
       and tl.recorded_at >= now() - (v_win_min * interval '1 minute')
  ), picked as (
    select trip_id, count(*) as n,
           max(d) filter (where rn = 1) as d_newest,
           max(d) filter (where rn = 3) as d_oldest
      from recent where rn <= 3
     group by trip_id
  )
  select bool_or(n = 3 and (d_oldest - d_newest) < v_stall_m) into v_stalled from picked;

  return coalesce(v_stalled, false);                                          -- Q11 (b)
end $$;
revoke execute on function public._match_overdue(uuid) from public, anon, authenticated;

-- 4. cancel_match_no_fault: atomic, idempotent, first-write-wins (Q12), callable by either side --------------------------
-- The atomic UPDATE's WHERE clause embeds BOTH the ownership check and the server-side overdue re-verification
-- (_match_overdue), so a client can never force a no-fault cancel merely by calling this RPC - it only succeeds when
-- the server itself confirms the match is overdue at the moment of the call. Race: if both sides call this
-- concurrently, the row lock inside the UPDATE serialises them - the first commit wins and the second's UPDATE
-- matches 0 rows (status is no longer 'accepted'), so it falls through to the idempotent 'already_cancelled' branch
-- (no error, per Q12: "the side that clicks after the outcome is decided sees an explanatory message, not an error").
-- Returns text: 'cancelled' (this call performed the no-fault cancel) | 'already_cancelled' (idempotent repeat).
-- Errors: GWM_UNAUTHENTICATED (42501) | GWM_RATE_LIMITED (shared 'match_state' bucket, same as cancel_match) |
--   GWM_MATCH_NOT_FOUND (P0001: no such match for this caller, not accepted, or already boarded - existence/boarding
--   state is not leaked beyond what cancel_match already leaks) | GWM_NOT_ELIGIBLE (P0001: not a car Driver<->Rider
--   match - peer modes have no boarding/lateness concept) | GWM_NOT_OVERDUE (P0001: the match is still
--   accepted/not-boarded but the server's own re-check does not (yet) consider it overdue - the client asserted
--   lateness the server cannot confirm; the "wait 10 more minutes" choice in the two-option card is purely client-side
--   UI state and needs no RPC/schema - see docs/design-roles.md #15.4).
create or replace function public.cancel_match_no_fault(p_match_id uuid) returns text
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare v_uid uuid := auth.uid(); v_id uuid; v_status public.match_status; v_boarded timestamptz; v_dtid uuid;
begin
  if v_uid is null then raise exception 'GWM_UNAUTHENTICATED' using errcode = '42501'; end if;
  perform public._throttle('match_state', public.cfg_num('throttle.match_state_per_min')::int, 60);

  update public.matches set status = 'cancelled', responded_at = now()
   where id = p_match_id and status = 'accepted' and boarded_at is null
     and v_uid in (requester_id, target_id)
     and public._match_overdue(id)
  returning id into v_id;

  if v_id is not null then
    insert into public.match_outcomes (match_id, reason, actor_id) values (v_id, 'no_fault_lateness', v_uid)
      on conflict (match_id) do nothing;
    -- neutral, no-blame wording (AC: "does not blame either side") - reuses the existing system chat string,
    -- and push_outbox_match_status (0011) already enqueues 'match_cancelled' for BOTH parties on this same
    -- UPDATE OF status trigger - no new push kind needed.
    insert into public.chat_messages (match_id, sender_id, kind, body) values (v_id, null, 'system', 'system.match_cancelled');
    return 'cancelled';
  end if;

  select m.status, m.boarded_at, m.driver_trip_id into v_status, v_boarded, v_dtid
    from public.matches m where m.id = p_match_id and v_uid in (m.requester_id, m.target_id);
  if not found then raise exception 'GWM_MATCH_NOT_FOUND' using errcode = 'P0001'; end if;
  if v_status = 'cancelled' then return 'already_cancelled'; end if;          -- idempotent repeat (Q12)
  if v_dtid is null then raise exception 'GWM_NOT_ELIGIBLE' using errcode = 'P0001'; end if;   -- not a car match
  if v_status <> 'accepted' or v_boarded is not null then raise exception 'GWM_MATCH_NOT_FOUND' using errcode = 'P0001'; end if;
  raise exception 'GWM_NOT_OVERDUE' using errcode = 'P0001';
end $$;
revoke execute on function public.cancel_match_no_fault(uuid) from public, anon;
grant execute on function public.cancel_match_no_fault(uuid) to authenticated;

-- =====================================================================================================================
-- PART 2 - US-50: route detour tolerance (general, any rider destination, no transit_hubs table - see BA final decision)
-- =====================================================================================================================

-- 5. Config: ceiling only (the per-trip 200-2000/step 100/default 500 range is enforced by the trigger below, same
--    least(value, ceiling) pattern as match.car_dest_radius_max_m / trips.max_dropoff_m) ---------------------------------
insert into public.app_config (key, value, description, is_public) values
  ('match.detour_tolerance_max_m', '2000', 'US-50: ceiling of trips.detour_tolerance_m (m); effective limit = least(value or 500, this)', true)
on conflict (key) do nothing;

-- 6. trips.detour_tolerance_m ---------------------------------------------------------------------------------------------
-- Separate from max_dropoff_m (measures a different thing - see requirements US-50 AC2): the extra ROUTE distance
-- (round trip) the Driver accepts to detour to the Rider's destination before continuing to the Driver's own
-- destination. NULL = not chosen (legacy/non-driver rows); the predicate treats NULL on a driver trip as 500
-- (_car_detour_tolerance_limit), mirroring _car_dropoff_limit's NULL -> 2000 pattern.
alter table public.trips add column if not exists detour_tolerance_m integer;
do $$ begin
  alter table public.trips add constraint trips_detour_tolerance_chk
    check (detour_tolerance_m is null or (role = 'driver' and detour_tolerance_m between 200 and 2000 and detour_tolerance_m % 100 = 0));
exception when duplicate_object then null; end $$;
grant insert (detour_tolerance_m), update (detour_tolerance_m) on public.trips to authenticated;

-- validation + lock: byte-for-byte the same shape as trips_max_dropoff_guard (0009), so it behaves identically
-- (default on insert, locked while a pending/accepted match exists, rejects out-of-range/off-step values, never rounds).
create or replace function public.trips_detour_tolerance_guard() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if tg_op = 'INSERT' then
    if new.detour_tolerance_m is not null and new.role is distinct from 'driver' then
      raise exception 'GWM_DETOUR_NOT_ALLOWED' using errcode = 'P0001';
    end if;
    if new.detour_tolerance_m is null and new.role = 'driver' then new.detour_tolerance_m := 500; end if;   -- default
  else
    if new.detour_tolerance_m is not distinct from old.detour_tolerance_m then return new; end if;
    if auth.uid() is not null then
      if new.role is distinct from 'driver' then raise exception 'GWM_DETOUR_NOT_ALLOWED' using errcode = 'P0001'; end if;
      if new.detour_tolerance_m is null then raise exception 'GWM_DETOUR_INVALID' using errcode = 'P0001'; end if;
      if old.status <> 'scheduled' then raise exception 'GWM_TRIP_STARTED' using errcode = 'P0001'; end if;
      if exists (select 1 from public.matches m
                  where m.status in ('pending','accepted') and old.id in (m.requester_trip_id, m.target_trip_id)) then
        raise exception 'GWM_TRIP_HAS_MATCHES' using errcode = 'P0001';
      end if;
    end if;
  end if;
  if new.detour_tolerance_m is not null
     and (new.detour_tolerance_m < 200 or new.detour_tolerance_m > public.cfg_num('match.detour_tolerance_max_m')
          or new.detour_tolerance_m % 100 <> 0) then
    raise exception 'GWM_DETOUR_INVALID' using errcode = 'P0001';
  end if;
  return new;
end $$;
drop trigger if exists trg_trips_detour_tolerance on public.trips;
create trigger trg_trips_detour_tolerance before insert or update of detour_tolerance_m on public.trips
  for each row execute function public.trips_detour_tolerance_guard();
revoke execute on function public.trips_detour_tolerance_guard() from public, anon, authenticated;

-- 7. Effective ceiling helper (mirrors _car_dropoff_limit) -----------------------------------------------------------------
create or replace function public._car_detour_tolerance_limit(p_val int) returns int
language sql stable security definer set search_path = public, pg_temp as $$
  select least(coalesce(p_val, 500), public.cfg_num('match.detour_tolerance_max_m')::int)
$$;
revoke execute on function public._car_detour_tolerance_limit(int) from public, anon, authenticated;

-- 8. Route-length-delta APPROXIMATION (no live OSRM access from SQL - see docs/design-roles.md #15.5 for the
--    error-margin discussion) ------------------------------------------------------------------------------------------
-- True target (AC4): route(origin->rider_dest->destination) - route(origin->destination), via OSRM. We do not have a
-- real route through rider_dest (only the Driver's own precomputed OSRM route, trips.route, from Driver origin to
-- Driver dest - see 0001 "route geography(LineString,4326) ... OSRM geometry chosen client-side"). Following the
-- SAME approximation family 0009's corridor rule already uses for its own detour_m (2*(d_o+d_d), a straight-line
-- "there and back" estimate off the route), we approximate the ADDED route length as:
--   detour_approx_m = 2 * ST_Distance(rider_dest, driver_route)
-- i.e. twice the straight-line distance from the rider's destination to the nearest point on the Driver's route -
-- the cost of a perpendicular there-and-back side trip to reach it and return to the route.
-- Returns NULL when either input is missing (fail-closed floor - see caller).
create or replace function public._car_detour_approx_m(p_driver_route geography, p_rider_dest geography) returns double precision
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select case when p_driver_route is null or p_rider_dest is null then null
              else 2.0 * ST_Distance(p_rider_dest, p_driver_route) end
$$;
revoke execute on function public._car_detour_approx_m(geography, geography) from public, anon, authenticated;

-- 9. _car_rule_eval: add p_d_detour_m (the Driver trip's raw detour_tolerance_m) + detour_tol_m output column.
--    New signature -> must DROP first (adding a parameter is not a valid CREATE OR REPLACE over the 0009 signature).
--    ONLY the neighbourhood branch's stage-2 (far_destination) check changes: when the straight-line dest check
--    fails, this is now a SECOND, independent chance to pass via the detour-tolerance approximation (AC3: "OR",
--    match.max_dropoff_m path is untouched and unblocked by this one - AC9 fail-closed applies to THIS check only).
--    The corridor branch (match.car_rule = 'corridor', OFF by default) is UNCHANGED - detour_tol_m stays NULL there.
drop function if exists public._car_rule_eval(geography, geography, geography, int, geography, geography, geography);
create function public._car_rule_eval(p_d_origin geography, p_d_dest geography, p_d_route geography, p_d_max_dropoff int,
                                       p_d_detour_m int,
                                       p_r_origin geography, p_r_dest geography, p_r_route geography)
returns table (stage int, d_o double precision, d_d double precision, ov double precision, detour_m double precision,
               lim int, detour_tol_m double precision)
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
  if round(d_d::numeric, 1) > lim then
    detour_tol_m := public._car_detour_approx_m(p_d_route, p_r_dest);                         -- US-50: 2nd path (OR)
    if detour_tol_m is null or round(detour_tol_m::numeric, 1) > public._car_detour_tolerance_limit(p_d_detour_m) then
      stage := 2; return next; return;                    -- fails BOTH max_dropoff_m and detour-tolerance (or OSRM/
    end if;                                                -- approximation input missing => fail-closed for THIS check only)
    -- passes via detour tolerance; falls through to the same overlap check (stage 3) the max_dropoff_m path uses
  end if;
  ov := public.route_overlap_pct(p_d_route, p_r_route, v_buf);
  if round(ov::numeric, 1) < round(v_min::numeric, 1) then stage := 3; return next; return; end if;
  stage := 0; detour_m := null; return next;
end $$;
revoke execute on function public._car_rule_eval(geography, geography, geography, int, int, geography, geography, geography) from public, anon, authenticated;

-- 10. match_candidates: 0012 body, unchanged signature/return type, ONE new column threaded through to _car_rule_eval ------
create or replace function public.match_candidates(p_trip_id uuid, p_limit int default 20, p_only_trip uuid default null)
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
  if v_car and v_t.role is null then return; end if;
  v_lim := case when v_car then public.car_seats() else v_max end;
  if (select count(*) from public.matches m where m.status = 'accepted'
        and v_t.id in (m.requester_trip_id, m.target_trip_id)) >= v_lim then return; end if;

  return query
  with cand as (
    select o.id as tid, o.user_id as uid, o.created_at as cat, o.route as route, o.origin as oo, o.dest as od,
           o.max_dropoff_m as mdo, o.detour_tolerance_m as mdt,
           ST_Distance(o.origin, v_t.origin) as p_d_o,
           ST_Distance(o.dest,   v_t.dest)   as p_d_d,
           (abs(extract(epoch from (o.depart_at - v_t.depart_at))) / 60.0)::double precision as dt
      from public.trips o
      join public.profiles p on p.id = o.user_id and p.deleted_at is null
     where o.status = 'scheduled' and o.deleted_at is null
       and o.depart_at > v_cutoff
       and o.user_id <> v_t.user_id
       and (p_only_trip is null or o.id = p_only_trip)
       and case when v_car and v_cor then ST_DWithin(o.route, v_t.route, v_corr)
                when v_car then ST_DWithin(o.origin, v_t.origin, v_roc) and ST_DWithin(o.dest, v_t.dest, v_dmax)
                else ST_DWithin(o.origin, v_t.origin, v_r_o) and ST_DWithin(o.dest, v_t.dest, v_r_d) end
       and o.depart_at between v_t.depart_at - v_win * interval '1 minute'
                           and v_t.depart_at + v_win * interval '1 minute'
       and case when v_car
                then o.mode = 'car' and o.role is not null and o.role <> v_t.role
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
       and public._niche_filters_ok(v_t.id, o.id)
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
                 case when v_t.role = 'driver' then v_t.origin else c.oo end,
                 case when v_t.role = 'driver' then v_t.dest   else c.od end,
                 case when v_t.role = 'driver' then v_t.route  else c.route end,
                 case when v_t.role = 'driver' then v_t.max_dropoff_m else c.mdo end,
                 case when v_t.role = 'driver' then v_t.detour_tolerance_m else c.mdt end,
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

-- 11. _accept_match: 0009 body, unchanged signature, threads trips.detour_tolerance_m into the re-check call -------------
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
  if v_car and v_m.car_rule_checked then                                   -- same predicate as the search
    select e.stage into v_stage
      from public.trips d, public.trips r,
           lateral public._car_rule_eval(d.origin, d.dest, d.route, d.max_dropoff_m, d.detour_tolerance_m,
                                          r.origin, r.dest, r.route) e
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

-- 12. Indexes -----------------------------------------------------------------------------------------------------------
-- trip_locations already has its FK/RLS-speed index from 0001 (trip_id); _match_overdue's window-recency scan
-- (trip_id IN (..) AND recorded_at >= now() - N minutes, ORDER BY recorded_at DESC per trip_id) is well served by a
-- composite (trip_id, recorded_at desc) index - the existing single-column trip_id index does not cover the ORDER BY.
create index if not exists trip_locations_trip_recorded_idx on public.trip_locations (trip_id, recorded_at desc);

-- match_outcomes_actor_idx (0006) already covers actor_id; no new index needed for the reason column (low
-- cardinality CHECK-constrained text, never filtered on alone - it is only ever read together with match_id via the
-- primary key, and match_outcomes has zero client-facing grants so there is no ad-hoc query pattern to optimise for).

notify pgrst, 'reload schema';

-- ROLLBACK PLAN (manual, forward-only per project convention - see 0006):
--   drop function public.cancel_match_no_fault(uuid); drop function public._match_overdue(uuid);
--   drop index if exists public.trip_locations_trip_recorded_idx;
--   alter table public.match_outcomes drop constraint match_outcomes_reason_check;
--   alter table public.match_outcomes add constraint match_outcomes_reason_check
--     check (reason in ('cancelled_by_driver','cancelled_by_rider','rider_no_show','trip_ended','trip_expired'));
--   drop function public._accept_match(uuid); drop function public.match_candidates(uuid,int,uuid);
--   drop function public._car_rule_eval(geography,geography,geography,int,int,geography,geography,geography);
--   then re-run 0009 section 3b/4 and 0012's match_candidates + 0009's _accept_match verbatim to restore prior bodies;
--   drop function public._car_detour_approx_m(geography,geography); drop function public._car_detour_tolerance_limit(int);
--   drop trigger trg_trips_detour_tolerance on public.trips; drop function public.trips_detour_tolerance_guard();
--   alter table public.trips drop constraint trips_detour_tolerance_chk; alter table public.trips drop column detour_tolerance_m;
