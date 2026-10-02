-- =====================================================================================================================
-- GOWITHME migration 0010 (round 6, DRAFT - not applied anywhere): docs/design-roles.md section 13
--   US-36 / R6.15  find_matches also returns the candidate's anonymous rating aggregate FOR THE ROLE of the candidate's trip
--                  (rating_avg, rating_count), only when review.show_in_search is true and the candidate has >= review.min_count_for_aggregate (3)
--                  revealed, not held, not removed reviews in that role; otherwise both NULL. No user id, no lookup handle.
--   US-35 / R6.9   cancel_pending_match(match): the undo guard. Cancels ONLY a still-pending match owned by the caller (requester).
-- Redefines (latest definition = 0009): find_matches. New: cancel_pending_match, index reviews_agg_cover_idx.
-- Not touched: match_candidates, request_match (throttle + pending cap), _accept_match, respond_match, cancel_match, get_user_rating,
--              review_aggregates, RLS, enums, tables. Rollback plan at the bottom.
-- =====================================================================================================================

-- 1. Index for the aggregate lookup ------------------------------------------------------------------------------------------------
-- find_matches probes it once per returned candidate (<= 50): equality on (reviewee_id, role); the counted-review predicate (held/removed NULL)
-- is the partial predicate; stars + the two reveal columns are INCLUDEd so the probe can be an index-only scan (no heap visit for a
-- well-vacuumed table). revealed_at is not a key column: the counted predicate is "revealed_at IS NOT NULL OR reveal_at <= now()" (same as
-- review_aggregates), an OR that a btree key on revealed_at could not serve anyway. reviews_reviewee_idx (0009) stays: it is the FK index
-- (cascade delete must also find held/removed rows) and the received-list index.
create index if not exists reviews_agg_cover_idx on public.reviews (reviewee_id, role) include (stars, revealed_at, reveal_at)
  where held_at is null and removed_at is null;

-- 2. find_matches -------------------------------------------------------------------------------------------------------------------
-- FINAL COLUMN LIST (Dart must match; the first 16 are identical to 0009, the last two are APPENDED):
--   trip_id, display_name, badges, mode, depart_at, time_diff_min, overlap_pct, approx_distance_m, score,
--   approx_origin_lat, approx_origin_lng, approx_dest_lat, approx_dest_lng, request_status, role, max_dropoff_m,
--   rating_avg, rating_count
-- rating_avg = round(avg(stars), 1) of the candidate's revealed reviews in the ROLE of the candidate's trip (driver trip -> reviews received
-- as driver; car rider trip -> as rider; peer trips have no role -> NULL). rating_count = how many reviews. Both NULL unless
-- cfg review.show_in_search AND count >= cfg review.min_count_for_aggregate (the same predicate and threshold as the review_aggregates view;
-- the tests assert the two never drift). Ranking, filters, blur, car rounding, the rider-destination-null rule and the throttle are unchanged.
drop function if exists public.find_matches(uuid, int);
create function public.find_matches(p_trip_id uuid, p_limit int default 20)
returns table (trip_id uuid, display_name text, badges jsonb, mode public.travel_mode, depart_at timestamptz,
               time_diff_min int, overlap_pct int, approx_distance_m int, score numeric,
               approx_origin_lat double precision, approx_origin_lng double precision,
               approx_dest_lat double precision, approx_dest_lng double precision,
               request_status public.match_status, role public.trip_role, max_dropoff_m int,
               rating_avg numeric, rating_count int)
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
         ra.cnt
    from public.match_candidates(p_trip_id, p_limit) c
    join public.trips o     on o.id  = c.candidate_trip_id
    join public.profiles pr on pr.id = c.candidate_user_id
    -- per-candidate probe (<= p_limit <= 50 index lookups on reviews_agg_cover_idx). Deliberately NOT a join to the review_aggregates view:
    -- a GROUP BY view over the whole table cannot be relied on to receive the join key as a pushed-down qual. Same predicate as that view.
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
-- The visible score is rounded; equal rounded scores order by trip id here. match_candidates itself is fully deterministic.
-- Privacy note: the aggregate is per (person, role) and only ever returned attached to that person's own scheduled trip card; the response
-- has no user id (trip_id is the only handle, as before), so it cannot be fed to get_user_rating (which needs a user id).

-- 3. cancel_pending_match (undo guard) ---------------------------------------------------------------------------------------------
-- Returns text: 'cancelled' (this call cancelled it) | 'already_cancelled' (idempotent repeat, incl. auto-closed).
-- Errors: GWM_UNAUTHENTICATED (42501) | GWM_MATCH_NOT_FOUND (P0001: no such match OR caller is not its requester - existence is not leaked)
--         | GWM_MATCH_NOT_PENDING (P0001: the other side already accepted/declined; nothing is changed)
--         | GWM_RATE_LIMITED (shared 'match_state' bucket, same as cancel_match).
-- Atomicity: ONE UPDATE ... WHERE id = $1 AND requester_id = auth.uid() AND status = 'pending'. It takes the row lock; a concurrent
-- respond_match/_accept_match (which locks the row FOR UPDATE with status = 'pending') is serialised against it: if the accept commits
-- first, this UPDATE re-checks its WHERE after the lock wait, matches nothing and we report GWM_MATCH_NOT_PENDING; if this commits first,
-- the accept finds no pending row (GWM_MATCH_NOT_FOUND). Only a pending row is ever written, so an accepted match can never be cancelled here.
-- The pending cap (request_match counts status = 'pending') is released by the cancel; request_match and its throttle are untouched, so an
-- undone request still counted against throttle.request_match_per_min when it was sent.
create or replace function public.cancel_pending_match(p_match_id uuid) returns text
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid(); v_id uuid; v_status public.match_status;
begin
  if v_uid is null then raise exception 'GWM_UNAUTHENTICATED' using errcode = '42501'; end if;
  perform public._throttle('match_state', public.cfg_num('throttle.match_state_per_min')::int, 60);
  update public.matches set status = 'cancelled', responded_at = now()
   where id = p_match_id and requester_id = v_uid and status = 'pending'
  returning id into v_id;
  if v_id is not null then return 'cancelled'; end if;
  select m.status into v_status from public.matches m where m.id = p_match_id and m.requester_id = v_uid;
  if not found then raise exception 'GWM_MATCH_NOT_FOUND' using errcode = 'P0001'; end if;
  if v_status = 'cancelled' then return 'already_cancelled'; end if;
  raise exception 'GWM_MATCH_NOT_PENDING' using errcode = 'P0001';
end $$;

-- 4. Grants (dropping find_matches dropped its grants) -----------------------------------------------------------------------------
revoke execute on function public.find_matches(uuid, int), public.cancel_pending_match(uuid) from public, anon;
grant execute on function public.find_matches(uuid, int), public.cancel_pending_match(uuid) to authenticated;
notify pgrst, 'reload schema';

-- ROLLBACK PLAN (manual): drop function public.cancel_pending_match(uuid); drop index if exists public.reviews_agg_cover_idx;
--   drop function public.find_matches(uuid, int); then re-run section 5 of 0009 (find_matches, 16 columns) + its revoke/grant lines.
