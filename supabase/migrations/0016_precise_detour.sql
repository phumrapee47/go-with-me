-- =====================================================================================================================
-- GOWITHME migration 0016 (round 7 follow-up, Stage D - DRAFT, NOT applied anywhere): docs/design-roles.md section 16
--   BUG-R7-03 (US-50, High): request_match now accepts a client-supplied PRECISE detour distance (computed client-side
--     via OSRM, per docs/flow-us50-detour.md step 3) and validates it server-side against a mathematically SOUND lower
--     bound (see _car_detour_floor_m below - NOT the 2x-perpendicular _car_detour_approx_m, which is only proven to be
--     an ADVISORY estimate, not a monotonic lower bound on the true OSRM route delta - see section 16 proof).
--   BUG-R7-01 (US-44, Medium): find_matches gains vibe_tags/mood_text (same 24h staleness rule as get_trip_card),
--     closing the data-contract gap that left MatchCandidate.fromJson's vibe/mood chips permanently empty.
-- Redefines (latest definitions read first): request_match (0009), _accept_match (0014), find_matches (0010).
-- New: _car_detour_floor_m, matches.detour_precise_m, GWM_DETOUR_IMPLAUSIBLE.
-- Idempotent: safe to re-run. Every new function is SECURITY DEFINER with a pinned search_path; grants are explicit.
-- =====================================================================================================================

-- =====================================================================================================================
-- PART 1 - BUG-R7-03: sound sanity floor + client-supplied precise detour
-- =====================================================================================================================

-- 1. matches.detour_precise_m: the ACCEPTED client-claimed detour distance (metres), stored at request_match time,
--    ONLY when the match was justified via the detour-tolerance path (NULL when justified via the max_dropoff_m
--    radial path, or for non-car matches). Re-validated (not re-asked) at accept time by _accept_match - see PART 1.3.
--    No client grant: only ever written by request_match/SECURITY DEFINER code, never directly by the client.
alter table public.matches add column if not exists detour_precise_m double precision;

-- 2. _car_detour_floor_m: a PROVABLY SOUND lower bound on the true OSRM route-delta for a Driver A->Z who detours via
--    Rider destination M, i.e. a lower bound on  route(A,M,Z) - route(A,Z).
--
--    WHY NOT reuse _car_detour_approx_m (0014) as the floor: that function computes 2 * ST_Distance(M, driver_route) -
--    twice the perpendicular straight-line distance from M to the nearest point on the driver's route. That is a
--    plausible ESTIMATE of the added distance, but it is NOT a proven lower bound on the real OSRM delta: depending on
--    road topology (a river/highway forcing a long detour to reach a bridge/interchange near the perpendicular foot,
--    a one-way system, etc.) the true route(A,M,Z)-route(A,Z) can be SHORTER than 2x the perpendicular distance in some
--    configurations and LONGER in others - it is not monotonic in either direction as a matter of pure geometry. Using
--    it as a strict reject-floor would either falsely reject honest client values or fail to catch some dishonest ones.
--    Per requirement #1 it stays UNCHANGED as the cheap ADVISORY filter inside match_candidates/_car_rule_eval (search
--    stage only - fast, no per-candidate OSRM, still fine to be a loose estimate there since it only decides which
--    candidates get OFFERED, not what gets ACCEPTED).
--
--    THE SOUND BOUND (triangle inequality + an EXACT known value, not another approximation):
--      Let A = driver origin, Z = driver destination, M = rider destination.
--      (a) For ANY real road network, the shortest possible path between two points is never shorter than the
--          straight-line (geodesic) distance between them - this is the defining property of a metric space; a road
--          path is one specific path in that space, so route(X,Y) >= |XY| ALWAYS, for every X,Y, regardless of
--          topology. This holds independently in both directions - it does not depend on which of |AM|+|MZ| vs
--          route(A,Z) happens to be "longer" in a particular case, unlike the 2x-perpendicular estimate above.
--      (b) So route(A,M) >= |AM| and route(M,Z) >= |MZ| (bound (a) applied twice), hence
--          route(A,M,Z) = route(A,M) + route(M,Z) >= |AM| + |MZ|.
--      (c) route(A,Z) is not merely bounded here - it is EXACTLY KNOWN: trips.route is the driver's own precomputed
--          real OSRM route geometry (0001, "OSRM geometry chosen client-side"), so ST_Length(trips.route) IS the real
--          route(A,Z) distance (up to geometry/projection precision), not an approximation of it.
--      (d) Subtracting the EXACT value (c) from the LOWER BOUND (b) preserves the lower-bound direction:
--            true_detour = route(A,M,Z) - route(A,Z) >= (|AM| + |MZ|) - route(A,Z) =: floor_m
--          This is exact/sound for ANY road topology - it never assumes 2D straight-line detours are shorter OR
--          longer than the real road detour; it only uses (a) applied to two independent legs and an exact known
--          quantity for the third. A client-claimed value strictly BELOW floor_m is mathematically impossible on any
--          real road network and is rejected as GWM_DETOUR_IMPLAUSIBLE.
--    (This is tighter and strictly more defensible than substituting the straight-line |AZ| for route(A,Z): since
--    |AZ| <= route(A,Z) always, using |AZ| would SUBTRACT LESS and could push the computed "floor" ABOVE the true
--    detour in some cases, i.e. it would NOT be a safe floor. Using the exact route(A,Z) we already have avoids that.)
--    Returns NULL when any input geometry is missing (fail-closed - caller must treat NULL as "cannot validate", not
--    as "floor is zero").
create or replace function public._car_detour_floor_m(p_d_origin geography, p_d_dest geography, p_d_route geography,
                                                        p_r_dest geography) returns double precision
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select case when p_d_origin is null or p_d_dest is null or p_d_route is null or p_r_dest is null then null
              else greatest(0.0, ST_Distance(p_d_origin, p_r_dest) + ST_Distance(p_r_dest, p_d_dest) - ST_Length(p_d_route)) end
$$;
revoke execute on function public._car_detour_floor_m(geography, geography, geography, geography) from public, anon, authenticated;

-- 3. _car_detour_path_used: true when the Driver<->Rider destination pair only passes via the detour-tolerance OR-path
--    (i.e. the straight-line max_dropoff_m radial check on its own would FAIL), false when the radial path alone
--    already passes (in which case no precise detour value is needed at all - the match is justified independently
--    of detour_tolerance_m, matching _car_rule_eval's own branch order: radial check first, detour-tolerance second).
create or replace function public._car_detour_path_used(p_d_dest geography, p_r_dest geography, p_d_max_dropoff int)
returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select round(ST_Distance(p_d_dest, p_r_dest)::numeric, 1) > public._car_dropoff_limit(p_d_max_dropoff)
$$;
revoke execute on function public._car_detour_path_used(geography, geography, int) from public, anon, authenticated;

-- 4. request_match: 0009 body + new OPTIONAL p_client_detour_m param (only meaningful/required when
--    _car_detour_path_used(...) is true for this Driver/Rider pair - see docs/flow-us50-detour.md step 3). New errors:
--    GWM_DETOUR_IMPLAUSIBLE (P0001: p_client_detour_m < _car_detour_floor_m(...), i.e. below the road-network-sound
--    lower bound - client is lying or badly wrong) | GWM_NOT_ELIGIBLE now ALSO covers: p_client_detour_m omitted when
--    the detour path is the only path that passes, or p_client_detour_m honest-but-plausible yet still exceeds the
--    Driver's current detour_tolerance_m (same code the radial/overlap failures already use - "conditions don't
--    match", not a new failure category from the caller's point of view).
-- A NEW WRAPPING RPC was considered and rejected: request_match already re-runs match_candidates/_car_rule_eval and
-- owns the insert of the matches row + all its other locks (dedupe, pending cap, reverse-pending accept) - splitting
-- the detour validation into a second RPC would require re-doing that same row-locking dance or accepting a race
-- between the two calls, for no benefit (the parameter is optional and inert for every non-detour-path request).
drop function if exists public.request_match(uuid, uuid);
create function public.request_match(p_my_trip uuid, p_target_trip uuid, p_client_detour_m double precision default null)
returns uuid
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare
  v_uid uuid := auth.uid(); v_me public.trips%rowtype; v_tgt public.trips%rowtype; v_c record;
  v_rev public.matches%rowtype; v_dup public.matches%rowtype; v_id uuid;
  v_driver public.trips%rowtype; v_rider public.trips%rowtype;
  v_needs_detour boolean := false; v_floor double precision; v_tol_lim int;
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

  -- US-50/BUG-R7-03: figure out which path made this candidate pass (radial max_dropoff_m vs detour-tolerance OR-path)
  -- by re-running the SAME destination check _car_rule_eval uses, directly - match_candidates only surfaces pass/fail
  -- (stage = 0), not which branch passed, so this cannot be read back off its result row.
  if v_me.mode = 'car' then
    select * into v_tgt from public.trips where id = p_target_trip;
    if v_me.role = 'driver' then v_driver := v_me; v_rider := v_tgt; else v_driver := v_tgt; v_rider := v_me; end if;
    v_needs_detour := public._car_detour_path_used(v_driver.dest, v_rider.dest, v_driver.max_dropoff_m);
  end if;

  if v_needs_detour then
    if p_client_detour_m is null then raise exception 'GWM_NOT_ELIGIBLE' using errcode = 'P0001'; end if;
    v_floor := public._car_detour_floor_m(v_driver.origin, v_driver.dest, v_driver.route, v_rider.dest);
    if v_floor is null or p_client_detour_m < v_floor then                 -- fail-closed: unknown floor => reject
      raise exception 'GWM_DETOUR_IMPLAUSIBLE' using errcode = 'P0001';
    end if;
    v_tol_lim := public._car_detour_tolerance_limit(v_driver.detour_tolerance_m);
    if round(p_client_detour_m::numeric, 1) > v_tol_lim then
      raise exception 'GWM_NOT_ELIGIBLE' using errcode = 'P0001';
    end if;
  end if;

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
                                score, overlap_pct, origin_distance_m, dest_distance_m, time_diff_min, car_rule_checked,
                                detour_precise_m)
    values (p_my_trip, p_target_trip, v_uid, v_c.candidate_user_id,
            (round(v_c.score::numeric / 5.0) * 5), round(v_c.overlap_pct::numeric, 0),
            (round(v_c.origin_distance_m / 500.0) * 500)::int,
            case when v_me.mode = 'car' then null else (round(v_c.dest_distance_m / 500.0) * 500)::int end,
            round(v_c.time_diff_min::numeric, 1), (v_me.mode = 'car'),
            case when v_needs_detour then p_client_detour_m end)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'GWM_ALREADY_REQUESTED' using errcode = 'P0001';
  end;
  return v_id;
end $$;
revoke execute on function public.request_match(uuid, uuid, double precision) from public, anon;
grant execute on function public.request_match(uuid, uuid, double precision) to authenticated;

-- 5. _accept_match: 0014 body + accept-time re-validation of the STORED detour_precise_m (per docs/flow-us50-detour.md
--    step 4 - "server re-checks everything again, conditions can change while a request is pending"). The client is
--    NOT asked again (matches.detour_precise_m from request_match time is reused); only the comparison against the
--    Driver's CURRENT detour_tolerance_m is re-run, same pattern as the existing car_rule_checked/_car_rule_eval
--    re-check just above it. The sound floor is not re-checked here: it depends only on the Driver's origin/dest/
--    route and the Rider's destination, all of which are LOCKED the moment this match is pending (trips_detour_
--    tolerance_guard/trips_max_dropoff_guard-style triggers reject edits to a trip with a pending/accepted match), so
--    a value that passed the floor at request time cannot later become implausible without those locked fields
--    changing - unlike detour_tolerance_m, which the Driver COULD have lowered before this request existed and which
--    this defensive re-check exists to catch (belt-and-braces, same rationale 0009's comment gives for its own re-check).
create or replace function public._accept_match(p_match_id uuid) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_m public.matches%rowtype; v_max int := public.cfg_num('match.max_matches_per_trip')::int;
  v_car boolean; v_lim int; v_rr public.trip_role; v_tr public.trip_role; v_stage int; v_d_tol int;
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
  -- BUG-R7-03/US-50: re-validate the STORED precise detour value against the Driver's CURRENT detour_tolerance_m
  if v_car and v_m.detour_precise_m is not null then
    select detour_tolerance_m into v_d_tol from public.trips where id = v_m.driver_trip_id;
    if round(v_m.detour_precise_m::numeric, 1) > public._car_detour_tolerance_limit(v_d_tol) then
      raise exception 'GWM_NOT_ELIGIBLE' using errcode = 'P0001';
    end if;
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

-- =====================================================================================================================
-- PART 2 - BUG-R7-01: find_matches returns vibe_tags/mood_text (same 24h staleness rule as get_trip_card)
-- =====================================================================================================================

-- 6. find_matches: 0010 body + TWO new OUT columns appended (Dart must match): vibe_tags, mood_text. Sourced straight
--    from the candidate trip (o.vibe_tags/o.mood_text), with the SAME live staleness re-check get_trip_card (0012)
--    already applies (mood_text hidden once mood_set_at is older than 24h, defensive against purge_expired_data not
--    yet having run this cycle - see 0012 section 7's comment). vibe_tags needs no separate staleness check for the
--    same reason get_trip_card's does not: it has no expiry anchor independent of mood_set_at and is cleared in full
--    alongside mood_text by both auto-clear paths (trip-end trigger, 24h purge, 0012 sections 5/6).
--    PRIVACY REGRESSION CHECK (round 5/6 rules, unchanged by this addition): no user id is returned (never was); the
--    car Rider-destination blur/null rule (o.mode='car' and o.role='rider' -> dest columns null) is untouched by this
--    change - vibe_tags/mood_text are user-authored trip labels, not location data, and were already visible to the
--    OTHER party post-match via get_trip_card, so this only moves the SAME data earlier (pre-match, on the deck card)
--    per US-44's AC, not a new category of exposure.
drop function if exists public.find_matches(uuid, int);
create function public.find_matches(p_trip_id uuid, p_limit int default 20)
returns table (trip_id uuid, display_name text, badges jsonb, mode public.travel_mode, depart_at timestamptz,
               time_diff_min int, overlap_pct int, approx_distance_m int, score numeric,
               approx_origin_lat double precision, approx_origin_lng double precision,
               approx_dest_lat double precision, approx_dest_lng double precision,
               request_status public.match_status, role public.trip_role, max_dropoff_m int,
               rating_avg numeric, rating_count int, vibe_tags text[], mood_text text)
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
#variable_conflict use_column
declare v_show boolean; v_min int;
begin
  perform public._throttle('find_matches', public.cfg_num('throttle.find_matches_per_min')::int, 60);
  p_limit := least(greatest(coalesce(p_limit, 20), 1), 50);
  if not exists (select 1 from public.trips t where t.id = p_trip_id and t.user_id = auth.uid() and t.deleted_at is null) then
    raise exception 'GWM_TRIP_NOT_FOUND' using errcode = '42501';
  end if;
  v_show := coalesce(public.cfg_bool('review.show_in_search'), false);
  v_min  := greatest(public.cfg_num('review.min_count_for_aggregate')::int, 1);
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
         case when o.mode = 'car' and o.role = 'driver' then public._car_dropoff_limit(o.max_dropoff_m) end,
         ra.avg_stars,
         ra.cnt,
         o.vibe_tags,
         case when o.mood_text is not null and o.mood_set_at > now() - interval '24 hours' then o.mood_text else null end::text
    from public.match_candidates(p_trip_id, p_limit) c
    join public.trips o     on o.id  = c.candidate_trip_id
    join public.profiles pr on pr.id = c.candidate_user_id
    left join lateral (
      select round(avg(r.stars)::numeric, 1) as avg_stars, count(*)::int as cnt
        from public.reviews r
       where v_show and o.role is not null
         and r.reviewee_id = o.user_id and r.role = o.role
         and (r.revealed_at is not null or r.reveal_at <= now()) and r.held_at is null and r.removed_at is null
      having count(*) >= v_min
    ) ra on true
   order by c.score desc, o.id;
end $$;
revoke execute on function public.find_matches(uuid, int) from public, anon;
grant execute on function public.find_matches(uuid, int) to authenticated;

notify pgrst, 'reload schema';

-- ROLLBACK PLAN (manual, forward-only per project convention - see 0006):
--   drop function public.find_matches(uuid, int);
--   then re-run 0010's find_matches body verbatim to restore the prior (17-column) return type;
--   drop function public._accept_match(uuid); then re-run 0014's _accept_match body verbatim;
--   drop function public.request_match(uuid, uuid, double precision);
--   then re-run 0009's request_match(uuid, uuid) body verbatim to restore the prior signature;
--   drop function public._car_detour_path_used(geography, geography, int);
--   drop function public._car_detour_floor_m(geography, geography, geography, geography);
--   alter table public.matches drop column detour_precise_m;
