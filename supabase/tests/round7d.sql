-- =============================================================================
-- GOWITHME automated SQL tests for round 7 follow-up migration 0016 (BUG-R7-03 precise detour validation,
-- BUG-R7-01 find_matches vibe/mood). docs/design-roles.md section 16. Same harness as round7.sql/round7c.sql.
-- Run after migrations 0001-0016 (as the postgres superuser role):
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f supabase/tests/round7d.sql
-- One transaction, ROLLED BACK at the end. Prints PASS/FAIL rows, exits non-zero on any FAIL.
-- (Authored without a database at hand: run before applying 0016.)
-- =============================================================================
\set ON_ERROR_STOP on
begin;
set search_path = public, extensions;

-- ---- harness (same as round7c.sql) -------------------------------------------------------------------
create schema gwm_test;
create table gwm_test.results (n serial primary key, label text, ok boolean, detail text);
grant usage on schema gwm_test to public;
grant all on all tables in schema gwm_test to public;
grant all on all sequences in schema gwm_test to public;

create function gwm_test.chk(p_label text, p_ok boolean, p_detail text default null) returns void
language sql as $$ insert into gwm_test.results (label, ok, detail) values (p_label, coalesce(p_ok, false), p_detail) $$;

create function gwm_test.expect_error(p_label text, p_sql text, p_needle text) returns void language plpgsql as $$
begin
  execute p_sql;
  insert into gwm_test.results (label, ok, detail) values (p_label, false, 'no error raised');
exception when others then
  insert into gwm_test.results (label, ok, detail)
  values (p_label, sqlerrm ilike '%' || p_needle || '%' or sqlstate = p_needle, sqlstate || ' ' || sqlerrm);
end $$;

create function gwm_test.expect_ok(p_label text, p_sql text) returns void language plpgsql as $$
begin
  execute p_sql;
  insert into gwm_test.results (label, ok) values (p_label, true);
exception when others then
  insert into gwm_test.results (label, ok, detail) values (p_label, false, sqlstate || ' ' || sqlerrm);
end $$;

create function gwm_test.as_user(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  execute 'set local role authenticated';
end $$;
create function gwm_test.reset() returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
end $$;

create function gwm_test.uid(p_n int) returns uuid language sql immutable as
$$ select ('00000000-0000-4000-8000-' || lpad(p_n::text, 12, '0'))::uuid $$;
create function gwm_test.tid(p_n int) returns uuid language sql immutable as
$$ select ('10000000-0000-4000-8000-' || lpad(p_n::text, 12, '0'))::uuid $$;

create function gwm_test.signup(p_n int) returns void language plpgsql as $$
begin
  insert into auth.users (instance_id, id, aud, role, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', gwm_test.uid(p_n), 'authenticated', 'authenticated',
          'u' || p_n || '@t.test', now(), '{"provider":"email"}'::jsonb,
          jsonb_build_object('display_name', 'user' || p_n, 'adult_confirmed', true,
                             'policy_version', public.cfg('policy.current_version') #>> '{}'),
          now(), now());
end $$;

-- point p_east metres east and p_north metres north of (102.83, p_lat) on the geography
create function gwm_test.pt(p_lat float8, p_east float8, p_north float8 default 0) returns geography language sql immutable as $$
  select ST_Project(ST_Project(ST_SetSRID(ST_MakePoint(102.83, p_lat), 4326)::geography, abs(p_east),
                               case when p_east >= 0 then pi() / 2 else 3 * pi() / 2 end),
                    abs(p_north), case when p_north >= 0 then 0.0 else pi() end)
$$;

create function gwm_test.veh(p_n int) returns void language plpgsql as $$
begin
  insert into public.vehicles (user_id, plate, model, color) values (gwm_test.uid(p_n), 'กข 1234', 'Toyota Vios', 'ขาว')
  on conflict do nothing;
  update public.profiles set driver_registered_at = now(), licence_declared_at = now(), licence_declaration_version = 'd1-draft'
   where id = gwm_test.uid(p_n);
end $$;

-- car trip fixture (superuser). p_via = optional dogleg vertex. p_max = max_dropoff_m. p_det = detour_tolerance_m.
create function gwm_test.rtrip(p_n int, p_role text, p_o geography, p_d geography, p_dep interval,
                               p_via geography default null, p_max int default null, p_det int default null)
returns void language plpgsql as $$
declare v_line geography;
begin
  if p_role = 'driver' then perform gwm_test.veh(p_n); end if;
  v_line := case when p_via is null then ST_MakeLine(p_o::geometry, p_d::geometry)::geography
                 else ST_MakeLine(ARRAY[p_o::geometry, p_via::geometry, p_d::geometry])::geography end;
  insert into public.trips (id, user_id, mode, role, origin, dest, route, route_distance_m, route_duration_s, depart_at,
                            max_dropoff_m, detour_tolerance_m)
  values (gwm_test.tid(p_n), gwm_test.uid(p_n), 'car'::public.travel_mode, p_role::public.trip_role,
          p_o, p_d, v_line, greatest(1, round(ST_Length(v_line))::int), 600, now() + interval '1 hour', p_max, p_det);
  update public.trips set depart_at = now() + p_dep where id = gwm_test.tid(p_n);
end $$;

create function gwm_test.mid(a int, b int) returns uuid language sql as $$
  select id from public.matches
   where least(requester_trip_id, target_trip_id) = least(gwm_test.tid(a), gwm_test.tid(b))
     and greatest(requester_trip_id, target_trip_id) = greatest(gwm_test.tid(a), gwm_test.tid(b)) $$;

update public.app_config set value = '1000'
 where key in ('throttle.find_matches_per_min', 'throttle.request_match_per_min', 'throttle.match_state_per_min');
update public.app_config set value = '100' where key = 'match.max_pending_per_trip';

select gwm_test.signup(i) from generate_series(1, 40) i;

-- =====================================================================================================
-- A. sound floor formula sanity (_car_detour_floor_m) - straight A->Z, M offset north of the midpoint.
--    A = (0,0), Z = (6000,0), M = (3000,1000): |AM| = |MZ| = sqrt(3000^2+1000^2) = 3162.2777, route(A,Z) = 6000
--    floor = 2*3162.2777 - 6000 = 324.5554 (approx; asserted with a wide tolerance for geodesic rounding)
-- =====================================================================================================
select gwm_test.rtrip(1, 'driver', gwm_test.pt(16.60, 0), gwm_test.pt(16.60, 6000), interval '30 minutes',
                       null, 2000, 500);   -- max_dropoff_m=2000 (default range), detour_tolerance_m=500
select gwm_test.chk('A0 floor formula matches hand-computed value within 5 m',
  abs((select public._car_detour_floor_m(origin, dest, route, gwm_test.pt(16.60, 3000, 1000)) from public.trips where id = gwm_test.tid(1))
      - 324.5554) < 5.0);
select gwm_test.chk('A1 floor is NULL (fail-closed) when route is missing',
  public._car_detour_floor_m(gwm_test.pt(16.60,0), gwm_test.pt(16.60,6000), null, gwm_test.pt(16.60,3000,1000)) is null);
select gwm_test.chk('A2 floor never negative (greatest(0, ...) clamp) when M sits almost on the route',
  public._car_detour_floor_m(gwm_test.pt(16.60,0), gwm_test.pt(16.60,6000),
    ST_MakeLine(gwm_test.pt(16.60,0)::geometry, gwm_test.pt(16.60,6000)::geometry)::geography,
    gwm_test.pt(16.60, 3000, 0)) >= 0);

-- =====================================================================================================
-- B. request_match: honest-and-passes / implausibly-low / honest-but-over-tolerance, on the SAME geometry
--    Rider destination M = pt(16.60, 3000, 200): dest_distance(driver,rider) ~ 3007 m > max_dropoff_m(2000)
--    => radial path fails. The candidate must ALSO clear match_candidates' own search-stage OR-path filter
--    (_car_rule_eval -> _car_detour_approx_m, the 0014 2x-perpendicular ADVISORY estimate) before request_match
--    ever reaches the new sound-floor check -- with driver.detour_tolerance_m=500 that means the perpendicular
--    offset must be small (<=250m, since approx = 2x perpendicular): 200m offset -> approx ~= 400 <= 500, so the
--    candidate is discoverable. Sound floor (triangle-inequality, this migration's real check) is then only
--    ~13.3 m for this small an offset -- much smaller than the advisory approx, which is expected: the OLD
--    2x-perpendicular estimate over-estimates the true detour for a near-route excursion far more than the
--    sound lower bound does. (NOTE on the original draft: it used a 1000m offset expecting floor~325 m, but at
--    that offset approx=2000m already exceeds detour_tolerance_m=500 at the search stage, so match_candidates
--    would never surface the candidate at all and request_match would fail with GWM_NOT_ELIGIBLE before ever
--    reaching the floor logic -- fixed here by shrinking the offset so search-stage candidacy actually passes.)
--    driver.detour_tolerance_m = 500 (ceiling default 2000, so limit = 500).
-- =====================================================================================================
-- B1: honest, plausible, within tolerance (400 m) -> passes, stored on the match row.
-- NOTE: rider origin/dest fixed to distinct points (BUG in original draft: identical origin=dest tripped
-- trips_guard's GWM_TRIP_TOO_SHORT; origin now on-route via a dogleg so match_candidates overlap/origin-radius
-- checks still pass).
select gwm_test.rtrip(2, 'rider', gwm_test.pt(16.60, 1000, 0), gwm_test.pt(16.60, 3000, 200), interval '31 minutes',
                       gwm_test.pt(16.60, 2900, 0));
select gwm_test.as_user(gwm_test.uid(2));
select gwm_test.expect_ok('B1 honest client detour (400 m, floor~13.3, tol=500) is accepted',
  format($q$select public.request_match(%L, %L, 400::double precision)$q$, gwm_test.tid(2), gwm_test.tid(1)));
select gwm_test.reset();
select gwm_test.chk('B1b stored detour_precise_m = 400 on the new match row',
  (select detour_precise_m from public.matches where id = gwm_test.mid(1,2)) = 400);

-- B2: implausibly low (5 m, below the ~13.3 m floor) -> GWM_DETOUR_IMPLAUSIBLE, on a FRESH pair (different rider).
select gwm_test.rtrip(3, 'rider', gwm_test.pt(16.60, 1000, 0), gwm_test.pt(16.60, 3000, 200), interval '31 minutes',
                       gwm_test.pt(16.60, 2900, 0));
select gwm_test.as_user(gwm_test.uid(3));
select gwm_test.expect_error('B2 implausibly low client detour (5 m < floor) is rejected',
  format($q$select public.request_match(%L, %L, 5::double precision)$q$, gwm_test.tid(3), gwm_test.tid(1)),
  'GWM_DETOUR_IMPLAUSIBLE');
select gwm_test.reset();
select gwm_test.chk('B2b no match row was created for the rejected request',
  not exists (select 1 from public.matches where least(requester_trip_id,target_trip_id) = least(gwm_test.tid(1),gwm_test.tid(3))
                and greatest(requester_trip_id,target_trip_id) = greatest(gwm_test.tid(1),gwm_test.tid(3))));

-- B3: honest and plausible (600 m, above floor) but exceeds the driver's 500 m tolerance -> GWM_NOT_ELIGIBLE.
select gwm_test.rtrip(4, 'rider', gwm_test.pt(16.60, 1000, 0), gwm_test.pt(16.60, 3000, 200), interval '31 minutes',
                       gwm_test.pt(16.60, 2900, 0));
select gwm_test.as_user(gwm_test.uid(4));
select gwm_test.expect_error('B3 honest but over the driver''s detour_tolerance_m is rejected',
  format($q$select public.request_match(%L, %L, 600::double precision)$q$, gwm_test.tid(4), gwm_test.tid(1)),
  'GWM_NOT_ELIGIBLE');
select gwm_test.reset();

-- B4: no value supplied at all when the detour path is the ONLY path -> GWM_NOT_ELIGIBLE (required, not optional here).
select gwm_test.rtrip(5, 'rider', gwm_test.pt(16.60, 1000, 0), gwm_test.pt(16.60, 3000, 200), interval '31 minutes',
                       gwm_test.pt(16.60, 2900, 0));
select gwm_test.as_user(gwm_test.uid(5));
select gwm_test.expect_error('B4 omitted p_client_detour_m on a detour-path-only candidate is rejected',
  format($q$select public.request_match(%L, %L)$q$, gwm_test.tid(5), gwm_test.tid(1)),
  'GWM_NOT_ELIGIBLE');
select gwm_test.reset();

-- B5: destination well within max_dropoff_m alone (radial path passes) -> p_client_detour_m irrelevant/not required,
--     detour_precise_m stays NULL even if the caller happens to pass a value (the radial path, not detour, justifies it).
select gwm_test.rtrip(6, 'rider', gwm_test.pt(16.60, 1000, 0), gwm_test.pt(16.60, 5000, 200), interval '31 minutes',
                       gwm_test.pt(16.60, 4900, 0));
select gwm_test.as_user(gwm_test.uid(6));
select gwm_test.expect_ok('B5 radial max_dropoff_m path alone is unaffected (no detour value needed)',
  format($q$select public.request_match(%L, %L)$q$, gwm_test.tid(6), gwm_test.tid(1)));
select gwm_test.reset();
select gwm_test.chk('B5b detour_precise_m is NULL when justified via the radial path',
  (select detour_precise_m from public.matches where id = gwm_test.mid(1,6)) is null);

-- =====================================================================================================
-- C. accept-time re-validation: driver's detour_tolerance_m lowered WHILE the request is pending (server-side
--    direct update, bypassing the client-facing lock trigger, to simulate "conditions changed" per the flow doc).
-- =====================================================================================================
select gwm_test.rtrip(7, 'driver', gwm_test.pt(16.61, 0), gwm_test.pt(16.61, 6000), interval '30 minutes', null, 2000, 500);
select gwm_test.rtrip(8, 'rider',  gwm_test.pt(16.61, 1000, 0), gwm_test.pt(16.61, 3000, 200), interval '31 minutes',
                       gwm_test.pt(16.61, 2900, 0));
select gwm_test.as_user(gwm_test.uid(8));
select public.request_match(gwm_test.tid(8), gwm_test.tid(7), 400::double precision);   -- honest, within tol=500 at request time
select gwm_test.reset();
select gwm_test.chk('C0 request accepted at request time (400 <= 500)', gwm_test.mid(7,8) is not null);
update public.trips set detour_tolerance_m = 300 where id = gwm_test.tid(7);   -- driver lowers tolerance below the stored 400
select gwm_test.as_user(gwm_test.uid(7));
select gwm_test.expect_error('C1 accept-time re-check catches the lowered tolerance (400 > new 300)',
  format($q$select public.respond_match(%L, true)$q$, gwm_test.mid(7,8)),
  'GWM_NOT_ELIGIBLE');
select gwm_test.reset();
select gwm_test.chk('C2 match stays pending (accept was rejected, not silently accepted)',
  (select status::text from public.matches where id = gwm_test.mid(7,8)) = 'pending');

-- C3: same setup but tolerance left alone (still 500) -> accept succeeds.
select gwm_test.rtrip(9,  'driver', gwm_test.pt(16.62, 0), gwm_test.pt(16.62, 6000), interval '30 minutes', null, 2000, 500);
select gwm_test.rtrip(10, 'rider',  gwm_test.pt(16.62, 1000, 0), gwm_test.pt(16.62, 3000, 200), interval '31 minutes',
                       gwm_test.pt(16.62, 2900, 0));
select gwm_test.as_user(gwm_test.uid(10));
select public.request_match(gwm_test.tid(10), gwm_test.tid(9), 400::double precision);
select gwm_test.reset();
select gwm_test.as_user(gwm_test.uid(9));
select gwm_test.expect_ok('C4 accept succeeds when the driver''s tolerance was not lowered',
  format($q$select public.respond_match(%L, true)$q$, gwm_test.mid(9,10)));
select gwm_test.reset();
select gwm_test.chk('C5 match is accepted', (select status::text from public.matches where id = gwm_test.mid(9,10)) = 'accepted');

-- =====================================================================================================
-- D. find_matches: fresh vibe_tags/mood_text surface, stale (>24h) mood_text is hidden, vibe_tags unaffected,
--    and the existing privacy rules (no user id column, car rider-destination blur) are unchanged.
-- =====================================================================================================
select gwm_test.rtrip(11, 'driver', gwm_test.pt(16.63, 0), gwm_test.pt(16.63, 5000), interval '40 minutes', null, 2000, 500);
select gwm_test.rtrip(12, 'rider',  gwm_test.pt(16.63, 200, 0), gwm_test.pt(16.63, 1900, 0), interval '41 minutes');
-- NOTE: vibe_tags must come from the live vibe.tags_rider allow-list (trips_vibe_mood_guard rejects anything else
-- with GWM_VIBE_TAG_INVALID) -- the original draft's placeholder tags ('quiet','music_ok') aren't in that list.
update public.trips set vibe_tags = array['#คุยเก่ง','#ฟังเพลงสากล'], mood_text = 'สบายๆ', mood_set_at = now()
 where id = gwm_test.tid(12);
select gwm_test.as_user(gwm_test.uid(11));
select gwm_test.chk('D1 find_matches surfaces fresh vibe_tags/mood_text for the candidate',
  (select vibe_tags = array['#คุยเก่ง','#ฟังเพลงสากล'] and mood_text = 'สบายๆ'
     from public.find_matches(gwm_test.tid(11)) where trip_id = gwm_test.tid(12)));
select gwm_test.reset();

-- D2: mood_set_at backdated past 24h (simulating the pre-purge window) -> mood_text hidden, same rule as get_trip_card.
update public.trips set mood_set_at = now() - interval '25 hours' where id = gwm_test.tid(12);
select gwm_test.as_user(gwm_test.uid(11));
select gwm_test.chk('D2 find_matches hides a stale (>24h) mood_text',
  (select mood_text is null from public.find_matches(gwm_test.tid(11)) where trip_id = gwm_test.tid(12)));
select gwm_test.chk('D3 find_matches still returns vibe_tags for the same stale-mood candidate (no independent expiry)',
  (select vibe_tags = array['#คุยเก่ง','#ฟังเพลงสากล'] from public.find_matches(gwm_test.tid(11)) where trip_id = gwm_test.tid(12)));
select gwm_test.reset();

-- D4: privacy regression - no user id column exists on find_matches' output, and the car Rider's destination stays
--     blurred to null for the OTHER party (the Driver here), unchanged by this migration.
select gwm_test.chk('D4 find_matches has no user-id-shaped column (privacy: candidate_user_id is match_candidates-only)',
  not exists (select 1 from information_schema.parameters
               where specific_schema = 'public' and specific_name in (
                 select specific_name from information_schema.routines
                  where routine_schema = 'public' and routine_name = 'find_matches')
                 and parameter_name = 'candidate_user_id'));
select gwm_test.as_user(gwm_test.uid(11));
select gwm_test.chk('D5 car rider destination stays blurred/null to the driver in find_matches',
  (select approx_dest_lat is null and approx_dest_lng is null
     from public.find_matches(gwm_test.tid(11)) where trip_id = gwm_test.tid(12)));
select gwm_test.reset();

-- =====================================================================================================
-- summary
-- =====================================================================================================
select format('%s/%s PASS', count(*) filter (where ok), count(*)) as summary from gwm_test.results;
select * from gwm_test.results where not ok order by n;
do $$
declare v_fail int;
begin
  select count(*) into v_fail from gwm_test.results where not ok;
  if v_fail > 0 then raise exception '% test(s) FAILED - see rows above', v_fail; end if;
end $$;

rollback;
