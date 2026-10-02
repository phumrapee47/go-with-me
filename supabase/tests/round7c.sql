-- =============================================================================
-- GOWITHME automated SQL tests for round 7 Stage C migration 0014 (US-49 lateness/no-fault-cancel,
-- US-50 detour tolerance). docs/design-roles.md section 15. Same harness as round5.sql/round6.sql/round7.sql.
-- Run after migrations 0001-0014 (as the postgres superuser role):
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f supabase/tests/round7c.sql
-- One transaction, ROLLED BACK at the end. Prints PASS/FAIL rows, exits non-zero on any FAIL.
-- KNOWN GAP (documented, not a bug): OSRM itself is never called from this file (SQL has no live OSRM access - see
-- docs/design-roles.md #15.5); the detour-tolerance tests exercise the PostGIS approximation only.
-- (Authored without a database at hand: run before applying 0014.)
-- =============================================================================
\set ON_ERROR_STOP on
begin;
set search_path = public, extensions;

-- ---- harness (same as round7.sql) -------------------------------------------------------------------
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

create function gwm_test.tstate(p_n int, p_status text) returns void language plpgsql as $$
begin update public.trips set status = p_status::public.trip_status where id = gwm_test.tid(p_n); end $$;
create function gwm_test.mid(a int, b int) returns uuid language sql as $$
  select id from public.matches
   where least(requester_trip_id, target_trip_id) = least(gwm_test.tid(a), gwm_test.tid(b))
     and greatest(requester_trip_id, target_trip_id) = greatest(gwm_test.tid(a), gwm_test.tid(b)) $$;

-- symmetric match_candidates membership check (both directions must agree, like round5.sql's sym())
create function gwm_test.sym_ok(p_d int, p_r int) returns boolean language sql as $$
  select exists (select 1 from public.match_candidates(gwm_test.tid(p_d)) where candidate_trip_id = gwm_test.tid(p_r))
     and exists (select 1 from public.match_candidates(gwm_test.tid(p_r)) where candidate_trip_id = gwm_test.tid(p_d))
$$;

-- an ACCEPTED, NOT boarded, in_progress car pair (superuser fixture) - the state lateness detection applies to.
create function gwm_test.waiting_pair(p_dn int, p_rn int, p_meet geography default null) returns void language plpgsql as $$
begin
  insert into public.matches (requester_trip_id, target_trip_id, requester_id, target_id, status, responded_at, meeting_point)
  values (gwm_test.tid(p_rn), gwm_test.tid(p_dn), gwm_test.uid(p_rn), gwm_test.uid(p_dn), 'accepted', now(), p_meet);
  perform gwm_test.tstate(p_dn, 'in_progress');
  perform gwm_test.tstate(p_rn, 'in_progress');
end $$;

-- backdated trip_locations breadcrumb (superuser)
create function gwm_test.loc(p_n int, p_pt geography, p_ago interval) returns void language plpgsql as $$
begin
  insert into public.trip_locations (trip_id, user_id, location, recorded_at)
  values (gwm_test.tid(p_n), gwm_test.uid(p_n), p_pt, now() - p_ago);
end $$;

update public.app_config set value = '1000'
 where key in ('throttle.find_matches_per_min', 'throttle.request_match_per_min', 'throttle.match_state_per_min');
update public.app_config set value = '100' where key = 'match.max_pending_per_trip';

-- users: 1..99 various car driver/rider fixtures below
select gwm_test.signup(i) from generate_series(1, 60) i;

-- =====================================================================================================
-- A. Q13 (closed): _review_check already gates on boarded_at - a no-fault cancel (never boarded) cannot
--    become reviewable, independent of the match_outcomes.reason value.
-- =====================================================================================================
select gwm_test.chk('A0 match_outcomes.reason CHECK now includes no_fault_lateness',
  (select pg_get_constraintdef(oid) from pg_constraint
    where conrelid = 'public.match_outcomes'::regclass and conname = 'match_outcomes_reason_check') ilike '%no_fault_lateness%');

select gwm_test.rtrip(1, 'driver', gwm_test.pt(13.70, 0), gwm_test.pt(13.70, 5000), interval '-20 minutes');
select gwm_test.rtrip(2, 'rider',  gwm_test.pt(13.70, 500), gwm_test.pt(13.70, 4000), interval '-19 minutes');
select gwm_test.waiting_pair(1, 2, gwm_test.pt(13.70, 500));
select gwm_test.as_user(gwm_test.uid(1));
select public.cancel_match_no_fault(gwm_test.mid(1,2));   -- overdue via Q11(a): 20 min > 10 min threshold
select gwm_test.reset();
select gwm_test.chk('A1 no-fault cancel recorded with the distinct reason',
  (select reason from public.match_outcomes where match_id = gwm_test.mid(1,2)) = 'no_fault_lateness');
select gwm_test.chk('A2 boarded_at stayed NULL (never met) so _review_check is not_boarded regardless of reason',
  (select reason from public._review_check(gwm_test.mid(1,2), gwm_test.uid(1))) = 'not_boarded'
  and (select reason from public._review_check(gwm_test.mid(1,2), gwm_test.uid(2))) = 'not_boarded');
select gwm_test.as_user(gwm_test.uid(1));
select gwm_test.expect_error('A3 submit_review is rejected for a no-fault-cancelled (never-boarded) match',
  format($q$select public.submit_review(%L, 5)$q$, gwm_test.mid(1,2)),
  'GWM_REVIEW_NOT_ELIGIBLE');
select gwm_test.reset();

-- =====================================================================================================
-- B. lateness no-fault cancel: overdue re-verification, idempotency, first-write-wins, either side, polite push
-- =====================================================================================================
-- B1: NOT overdue yet (just accepted, on time) - server must refuse even though the RPC is called.
select gwm_test.rtrip(3, 'driver', gwm_test.pt(13.71, 0), gwm_test.pt(13.71, 5000), interval '2 minutes');
select gwm_test.rtrip(4, 'rider',  gwm_test.pt(13.71, 500), gwm_test.pt(13.71, 4000), interval '3 minutes');
select gwm_test.waiting_pair(3, 4, gwm_test.pt(13.71, 500));
select gwm_test.as_user(gwm_test.uid(3));
select gwm_test.expect_error('B1 server refuses a premature no-fault cancel (not overdue)',
  format($q$select public.cancel_match_no_fault(%L)$q$, gwm_test.mid(3,4)),
  'GWM_NOT_OVERDUE');
select gwm_test.reset();
select gwm_test.chk('B1b match stays accepted (client assertion alone changes nothing)',
  (select status::text from public.matches where id = gwm_test.mid(3,4)) = 'accepted');

-- B2: overdue via Q11(b) - 3 samples over the stall window whose distance to the meeting point barely moves (<100 m).
select gwm_test.rtrip(5, 'driver', gwm_test.pt(13.72, 0), gwm_test.pt(13.72, 5000), interval '-6 minutes');
select gwm_test.rtrip(6, 'rider',  gwm_test.pt(13.72, 500), gwm_test.pt(13.72, 4000), interval '-5 minutes');
select gwm_test.waiting_pair(5, 6, gwm_test.pt(13.72, 500));      -- meeting point = rider pickup
-- driver stuck ~2000 m short of the meeting point across the whole 5-minute window (net improvement 40 m < 100 m)
select gwm_test.loc(5, gwm_test.pt(13.72, -1500), interval '4 minutes');
select gwm_test.loc(5, gwm_test.pt(13.72, -1520), interval '2 minutes');
select gwm_test.loc(5, gwm_test.pt(13.72, -1540), interval '30 seconds');
select gwm_test.as_user(gwm_test.uid(6));
select public.cancel_match_no_fault(gwm_test.mid(5,6));           -- the RIDER (not the stuck driver) cancels
select gwm_test.reset();
select gwm_test.chk('B2 overdue via ETA-not-improving (Q11b) - either side may trigger it',
  (select status::text from public.matches where id = gwm_test.mid(5,6)) = 'cancelled'
  and (select reason from public.match_outcomes where match_id = gwm_test.mid(5,6)) = 'no_fault_lateness');

-- B2b: same shape but the driver clearly closes in (>=100 m improvement) - must NOT be overdue via (b), and not yet
-- overdue via (a) either (still within the 10-minute grace), so the call is refused.
select gwm_test.rtrip(7, 'driver', gwm_test.pt(13.73, 0), gwm_test.pt(13.73, 5000), interval '-6 minutes');
select gwm_test.rtrip(8, 'rider',  gwm_test.pt(13.73, 500), gwm_test.pt(13.73, 4000), interval '-5 minutes');
select gwm_test.waiting_pair(7, 8, gwm_test.pt(13.73, 500));
select gwm_test.loc(7, gwm_test.pt(13.73, -1500), interval '4 minutes');
select gwm_test.loc(7, gwm_test.pt(13.73, -1000), interval '2 minutes');
select gwm_test.loc(7, gwm_test.pt(13.73, -300),  interval '30 seconds');
select gwm_test.as_user(gwm_test.uid(8));
select gwm_test.expect_error('B2b closing in fast enough (>=100 m) is NOT overdue - refused',
  format($q$select public.cancel_match_no_fault(%L)$q$, gwm_test.mid(7,8)),
  'GWM_NOT_OVERDUE');
select gwm_test.reset();

-- B3: idempotent repeat / first-write-wins race (Q12) - the second call, from either side, gets a calm 'already_cancelled'
select gwm_test.rtrip(9,  'driver', gwm_test.pt(13.74, 0), gwm_test.pt(13.74, 5000), interval '-20 minutes');
select gwm_test.rtrip(10, 'rider',  gwm_test.pt(13.74, 500), gwm_test.pt(13.74, 4000), interval '-19 minutes');
select gwm_test.waiting_pair(9, 10, gwm_test.pt(13.74, 500));
select gwm_test.as_user(gwm_test.uid(9));
select gwm_test.chk('B3a first call returns cancelled', public.cancel_match_no_fault(gwm_test.mid(9,10)) = 'cancelled');
select gwm_test.reset();
select gwm_test.as_user(gwm_test.uid(10));
select gwm_test.chk('B3b second call (other side) is idempotent, no error', public.cancel_match_no_fault(gwm_test.mid(9,10)) = 'already_cancelled');
select gwm_test.reset();
select gwm_test.as_user(gwm_test.uid(9));
select gwm_test.chk('B3c a THIRD call (same side, repeat) is still idempotent', public.cancel_match_no_fault(gwm_test.mid(9,10)) = 'already_cancelled');
select gwm_test.reset();
select gwm_test.chk('B3d exactly one match_outcomes row (on conflict do nothing held)',
  (select count(*) from public.match_outcomes where match_id = gwm_test.mid(9,10)) = 1);

-- B4: the OTHER side (who did not click cancel) gets a polite push via the EXISTING match_cancelled push_outbox kind
select gwm_test.chk('B4 push_outbox match_cancelled queued for the non-cancelling side too (existing kind, no new kind)',
  (select count(*) from public.push_outbox where match_id = gwm_test.mid(9,10) and kind = 'match_cancelled' and user_id = gwm_test.uid(10)) = 1);
select gwm_test.chk('B4b neutral system chat message, no blame wording (reuses system.match_cancelled)',
  (select count(*) from public.chat_messages where match_id = gwm_test.mid(9,10) and kind = 'system' and body = 'system.match_cancelled') = 1);

-- B5: already boarded => GWM_MATCH_NOT_FOUND (never a no-fault path once the two have actually met)
select gwm_test.rtrip(11, 'driver', gwm_test.pt(13.75, 0), gwm_test.pt(13.75, 5000), interval '-20 minutes');
select gwm_test.rtrip(12, 'rider',  gwm_test.pt(13.75, 500), gwm_test.pt(13.75, 4000), interval '-19 minutes');
select gwm_test.waiting_pair(11, 12, gwm_test.pt(13.75, 500));
update public.matches set boarded_at = now() where id = gwm_test.mid(11,12);
select gwm_test.as_user(gwm_test.uid(11));
select gwm_test.expect_error('B5 already-boarded match cannot be no-fault-cancelled',
  format($q$select public.cancel_match_no_fault(%L)$q$, gwm_test.mid(11,12)),
  'GWM_MATCH_NOT_FOUND');
select gwm_test.reset();

-- B6: a stranger cannot no-fault-cancel someone else's match (existence not leaked)
select gwm_test.as_user(gwm_test.uid(20));
select gwm_test.expect_error('B6 non-participant gets GWM_MATCH_NOT_FOUND (existence not leaked)',
  format($q$select public.cancel_match_no_fault(%L)$q$, gwm_test.mid(3,4)),
  'GWM_MATCH_NOT_FOUND');
select gwm_test.reset();

-- =====================================================================================================
-- C. US-50 detour tolerance: OR-alternative to max_dropoff_m, boundary, fail-closed
-- =====================================================================================================
-- Driver 30: origin->dest straight line 6000 m east at lat 16.50, max_dropoff_m default(2000), detour_tolerance_m = 500.
select gwm_test.rtrip(30, 'driver', gwm_test.pt(16.50, 0), gwm_test.pt(16.50, 6000), interval '1 hour', null, null, 500);
select gwm_test.chk('C0 trips.detour_tolerance_m defaulted to 500', (select detour_tolerance_m from public.trips where id = gwm_test.tid(30)) = 500);

-- C1: rider destination fails max_dropoff_m (short by 2500 m, > 2000 default limit) but the perpendicular approximation
-- (2 * distance-to-route) is only ~2*200=400 m <= 500 m detour_tolerance_m => matches via the NEW path.
select gwm_test.rtrip(31, 'rider', gwm_test.pt(16.50, 1), gwm_test.pt(16.50, 3500, 200), interval '1 hour');  -- 200 m PERPENDICULAR off the driver's straight route
select gwm_test.chk('C1 fails max_dropoff_m alone but passes via detour tolerance (OR)',
  gwm_test.sym_ok(30, 31));

-- C2: same lateral offset (200 m => ~400 m approx) but detour_tolerance_m too small (200) to admit it => fails both.
select gwm_test.rtrip(32, 'driver', gwm_test.pt(16.51, 0), gwm_test.pt(16.51, 6000), interval '1 hour', null, null, 200);
select gwm_test.rtrip(33, 'rider', gwm_test.pt(16.51, 1), gwm_test.pt(16.51, 3500, 200), interval '1 hour');
select gwm_test.chk('C2 fails max_dropoff_m AND fails detour tolerance (driver only accepts 200 m)', not gwm_test.sym_ok(32, 33));

-- C3: destination well within max_dropoff_m (short by only 500 m) - matches via the ORIGINAL path regardless of detour.
select gwm_test.rtrip(34, 'driver', gwm_test.pt(16.52, 0), gwm_test.pt(16.52, 6000), interval '1 hour', null, null, 200);
select gwm_test.rtrip(35, 'rider', gwm_test.pt(16.52, 1), gwm_test.pt(16.52, 5500), interval '1 hour');
select gwm_test.chk('C3 passes via max_dropoff_m alone (detour tolerance irrelevant here)', gwm_test.sym_ok(34, 35));

-- C4: boundary - lateral offset exactly at the driver's detour_tolerance_m/2 (so approx == limit, inclusive <=).
select gwm_test.rtrip(36, 'driver', gwm_test.pt(16.53, 0), gwm_test.pt(16.53, 6000), interval '1 hour', null, null, 400);
select gwm_test.rtrip(37, 'rider', gwm_test.pt(16.53, 1), gwm_test.pt(16.53, 3500, 200), interval '1 hour');  -- approx = 400 m exactly
select gwm_test.chk('C4 boundary: approx == detour_tolerance_m is INCLUSIVE (matches)', gwm_test.sym_ok(36, 37));

-- C5: config ceiling enforced regardless of what the client sends (mirrors max_dropoff_m's ceiling behaviour)
update public.app_config set value = '300' where key = 'match.detour_tolerance_max_m';
select gwm_test.chk('C5 effective limit is capped by the config ceiling',
  public._car_detour_tolerance_limit(500) = 300);
update public.app_config set value = '2000' where key = 'match.detour_tolerance_max_m';   -- restore

-- C6: fail-closed when the approximation cannot be computed (null route input) - does not block max_dropoff_m though.
select gwm_test.chk('C6a _car_detour_approx_m is NULL (fail-closed) when a route is missing',
  public._car_detour_approx_m(null, gwm_test.pt(16.54, 100)) is null);
select gwm_test.rtrip(39, 'driver', gwm_test.pt(16.54, 0), gwm_test.pt(16.54, 6000), interval '1 hour', null, null, 2000);
select gwm_test.rtrip(40, 'rider', gwm_test.pt(16.54, 1), gwm_test.pt(16.54, 5900), interval '1 hour');   -- short by 100 m: passes via max_dropoff_m regardless
select gwm_test.chk('C6b max_dropoff_m path is unaffected by the detour-tolerance predicate existing at all',
  gwm_test.sym_ok(39, 40));

-- C7: insert-time validation / lock (byte-for-byte like max_dropoff_m's guard)
select gwm_test.expect_error('C7 400 rejected (below 200)',
  $q$select gwm_test.rtrip(41, 'driver', gwm_test.pt(16.55, 0), gwm_test.pt(16.55, 3000), interval '1 hour', null, null, 100)$q$, 'GWM_DETOUR_INVALID');
select gwm_test.expect_error('C7 2100 rejected (above config ceiling 2000)',
  $q$select gwm_test.rtrip(42, 'driver', gwm_test.pt(16.55, 0), gwm_test.pt(16.55, 3000), interval '1 hour', null, null, 2100)$q$, 'GWM_DETOUR_INVALID');
select gwm_test.expect_error('C7 350 rejected (not a multiple of 100)',
  $q$select gwm_test.rtrip(43, 'driver', gwm_test.pt(16.55, 0), gwm_test.pt(16.55, 3000), interval '1 hour', null, null, 350)$q$, 'GWM_DETOUR_INVALID');
select gwm_test.expect_error('C7 a Rider trip carries no detour tolerance',
  $q$select gwm_test.rtrip(44, 'rider', gwm_test.pt(16.55, 0), gwm_test.pt(16.55, 3000), interval '1 hour', null, null, 500)$q$, 'GWM_DETOUR_NOT_ALLOWED');
select gwm_test.expect_ok('C7 200 and 2000 accepted (range ends)',
  $q$select gwm_test.rtrip(45, 'driver', gwm_test.pt(16.55, 0), gwm_test.pt(16.55, 3000), interval '1 hour', null, null, 200)$q$);
select gwm_test.rtrip(46, 'driver', gwm_test.pt(16.56, 0), gwm_test.pt(16.56, 3000), interval '1 hour', null, null, 600);
select gwm_test.rtrip(47, 'rider', gwm_test.pt(16.56, 1), gwm_test.pt(16.56, 2900), interval '1 hour');
select gwm_test.as_user(gwm_test.uid(46));
select public.request_match(gwm_test.tid(46), gwm_test.tid(47));
select gwm_test.expect_error('C7 editing detour_tolerance_m is locked once a match exists',
  format($q$update public.trips set detour_tolerance_m = 700 where id = %L$q$, gwm_test.tid(46)),
  'GWM_TRIP_HAS_MATCHES');
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
