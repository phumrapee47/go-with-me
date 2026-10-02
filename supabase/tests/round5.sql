-- =============================================================================
-- GOWITHME automated SQL tests for migration 0009 (round 5: US-21 corridor matching + no-match hint, US-22 avatars,
-- US-26 reviews; docs/design-roles.md section 12).
-- Run after migrations 0001-0009 (as the postgres superuser role):
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f supabase/tests/round5.sql
-- One transaction, ROLLED BACK at the end. Same harness as roles.sql / dual_role.sql. Khon Kaen coordinates; car trips are placed
-- with ST_Project so that the distances named in the requirements (1 m, 2461 m, 900 m ...) are exact on the geography.
-- Storage-dependent checks run only when the `storage` schema exists (plain Postgres + PostGIS skips them, with a PASS row).
-- Prints PASS/FAIL rows and exits non-zero on any FAIL.  (Authored without a database at hand: run it before merging 0009.)
-- =============================================================================
\set ON_ERROR_STOP on
begin;
set search_path = public, extensions;

-- ---- harness (same as roles.sql / dual_role.sql) -------------------------------------------------
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

create function gwm_test.n(p_sql text) returns bigint language plpgsql as $$
declare v bigint; begin execute p_sql into v; return v; end $$;

create function gwm_test.as_user(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  execute 'set local role authenticated';
end $$;
-- moderator: is_admin() reads app_metadata.role from the JWT
create function gwm_test.as_admin(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated',
                     'app_metadata', json_build_object('role', 'admin'))::text, true);
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

create function gwm_test.signup(p_n int, p_email text default null, p_meta jsonb default '{}', p_confirmed boolean default true)
returns void language plpgsql as $$
begin
  insert into auth.users (instance_id, id, aud, role, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', gwm_test.uid(p_n), 'authenticated', 'authenticated',
          coalesce(p_email, 'u' || p_n || '@t.test'), case when p_confirmed then now() end, '{"provider":"email"}'::jsonb,
          jsonb_build_object('display_name', 'user' || p_n, 'adult_confirmed', true,
                             'policy_version', public.cfg('policy.current_version') #>> '{}') || p_meta,
          now(), now());
end $$;

-- ---- helpers specific to this file ----------------------------------------------------------------
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

-- generic trip fixture (superuser). p_via: optional middle vertex of the route (dogleg). tid defaults to the user number.
create function gwm_test.rtrip(p_n int, p_mode text, p_role text, p_o geography, p_d geography, p_dep interval,
                               p_via geography default null, p_tid int default null, p_max int default null) returns void language plpgsql as $$
declare v_line geography;
begin
  if p_role = 'driver' then perform gwm_test.veh(p_n); end if;
  v_line := case when p_via is null then ST_MakeLine(p_o::geometry, p_d::geometry)::geography
                 else ST_MakeLine(ARRAY[p_o::geometry, p_via::geometry, p_d::geometry])::geography end;
  insert into public.trips (id, user_id, mode, role, origin, dest, route, route_distance_m, route_duration_s, depart_at, max_dropoff_m)
  values (gwm_test.tid(coalesce(p_tid, p_n)), gwm_test.uid(p_n), p_mode::public.travel_mode, p_role::public.trip_role,
          p_o, p_d, v_line, greatest(1, round(ST_Length(v_line))::int), 600, now() + interval '1 hour', p_max);
  update public.trips set depart_at = now() + p_dep where id = gwm_test.tid(coalesce(p_tid, p_n));
end $$;

create function gwm_test.setcfg(p_key text, p_val text) returns void language sql as
$$ update public.app_config set value = p_val::jsonb where key = p_key $$;

create function gwm_test.cand_count(p_req int, p_cand int) returns bigint language sql as
$$ select count(*) from public.match_candidates(gwm_test.tid(p_req)) where candidate_trip_id = gwm_test.tid(p_cand) $$;
-- both directions must agree (symmetry) => returns 1 / 0, or -1 when the two sides disagree
create function gwm_test.sym(p_a int, p_b int) returns int language sql as $$
  select case when gwm_test.cand_count(p_a, p_b) = gwm_test.cand_count(p_b, p_a) then gwm_test.cand_count(p_a, p_b)::int else -1 end $$;
create function gwm_test.tstate(p_n int, p_status text) returns void language plpgsql as $$
begin update public.trips set status = p_status::public.trip_status where id = gwm_test.tid(p_n); end $$;
create function gwm_test.mid(a int, b int) returns uuid language sql as $$
  select id from public.matches
   where least(requester_trip_id, target_trip_id) = least(gwm_test.tid(a), gwm_test.tid(b))
     and greatest(requester_trip_id, target_trip_id) = greatest(gwm_test.tid(a), gwm_test.tid(b)) $$;
create function gwm_test.pair_accept(p_req int, p_tgt int) returns void language plpgsql as $$
begin
  perform gwm_test.as_user(gwm_test.uid(p_req));
  perform public.request_match(gwm_test.tid(p_req), gwm_test.tid(p_tgt));
  perform gwm_test.reset();
  perform gwm_test.as_user(gwm_test.uid(p_tgt));
  perform public.respond_match(gwm_test.mid(p_req, p_tgt), true);
  perform gwm_test.reset();
end $$;

-- a finished ride on its own line at p_lat (fixture, superuser): accepted match, boarded (optional), trips completed (optional)
create function gwm_test.done_pair(p_dn int, p_dtid int, p_rn int, p_rtid int, p_lat float8,
                                   p_boarded boolean default true, p_complete boolean default true) returns void language plpgsql as $$
begin
  perform gwm_test.rtrip(p_dn, 'car', 'driver', gwm_test.pt(p_lat, 0), gwm_test.pt(p_lat, 5000), interval '1 hour', null, p_dtid);
  perform gwm_test.rtrip(p_rn, 'car', 'rider',  gwm_test.pt(p_lat, 500), gwm_test.pt(p_lat, 4000), interval '1 hour', null, p_rtid);
  insert into public.matches (requester_trip_id, target_trip_id, requester_id, target_id, status, responded_at, boarded_at)
  values (gwm_test.tid(p_rtid), gwm_test.tid(p_dtid), gwm_test.uid(p_rn), gwm_test.uid(p_dn), 'accepted', now(),
          case when p_boarded then now() end);
  if p_boarded or p_complete then
    perform gwm_test.tstate(p_dtid, 'in_progress'); perform gwm_test.tstate(p_rtid, 'in_progress');
  end if;
  if p_complete then
    perform gwm_test.tstate(p_dtid, 'completed'); perform gwm_test.tstate(p_rtid, 'completed');
  end if;
end $$;

-- the test must not trip the per-user throttles (throttle behaviour has its own checks below)
update public.app_config set value = '1000'
 where key in ('throttle.find_matches_per_min', 'throttle.request_match_per_min', 'throttle.match_state_per_min',
               'throttle.match_hint_per_min', 'throttle.review_write_per_hour', 'throttle.avatar_write_per_hour', 'throttle.report_per_hour');
update public.app_config set value = '100' where key = 'match.max_pending_per_trip';

-- users: 1..23 main zone (drivers 1,12,14,15,16; riders the rest), 24/25 validation, 30..39 hint zones, 40..43 avatar, 50..52 walkers, 90..96 corridor zone,
--        60..72 review users, 80 admin
select gwm_test.signup(i) from generate_series(1, 23) i;
select gwm_test.signup(i) from generate_series(40, 43) i;
select gwm_test.signup(i) from generate_series(50, 52) i;
select gwm_test.signup(i) from generate_series(60, 72) i;
select gwm_test.signup(80);

-- =============================================================================
-- A. config + schema: the car rule keys, trips.max_dropoff_m, all thresholds from ONE place
-- =============================================================================
select gwm_test.chk('A1 match.car_rule = neighbourhood, car_origin_radius_m = 2000, car_dest_radius_max_m = 5000, time window 30, min overlap 40',
  (public.cfg('match.car_rule') #>> '{}') = 'neighbourhood' and public.cfg_num('match.car_origin_radius_m') = 2000
  and public.cfg_num('match.car_dest_radius_max_m') = 5000 and public.cfg_num('match.time_window_min') = 30
  and public.cfg_num('match.min_overlap_pct') = 40);
select gwm_test.chk('A1 corridor keys kept (OFF by default): 1000 / 3000 / 0.80',
  public.cfg_num('match.car_corridor_m') = 1000 and public.cfg_num('match.car_max_detour_m') = 3000 and public.cfg_num('match.car_min_rider_coverage') = 0.80);
select gwm_test.chk('A2 car_weights configured (corridor mode)', (select (public.cfg('match.car_weights') ->> 'detour')::float8 > 0));
select gwm_test.chk('A3 review.window_days = 7, min count 3, avatar.max_bytes = 524288, show_in_search default true (PM)',
  public.cfg_num('review.window_days') = 7 and public.cfg_num('review.min_count_for_aggregate') = 3 and public.cfg_num('avatar.max_bytes') = 524288
  and public.cfg_bool('review.show_in_search'));
select gwm_test.chk('A4 RLS enabled on every new table',
  (select bool_and(c.relrowsecurity) from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname in ('reviews', 'review_tags', 'review_selected_tags', 'content_reports', 'storage_purge_queue')));
select gwm_test.chk('A5 trips.max_dropoff_m is an integer column; matches.car_rule_checked exists; no approx_detour_m anywhere in find_matches',
  (select data_type = 'integer' from information_schema.columns where table_schema = 'public' and table_name = 'trips' and column_name = 'max_dropoff_m')
  and (select count(*) = 1 from information_schema.columns where table_schema = 'public' and table_name = 'matches' and column_name = 'car_rule_checked')
  and pg_get_function_result('public.find_matches(uuid,int)'::regprocedure) !~* 'detour');
select gwm_test.chk('A6 find_matches FINAL column list (Dart contract)',
  (select proargnames[3:18] = array['trip_id','display_name','badges','mode','depart_at','time_diff_min','overlap_pct',
     'approx_distance_m','score','approx_origin_lat','approx_origin_lng','approx_dest_lat','approx_dest_lng','request_status','role','max_dropoff_m']::text[]
     from pg_proc where oid = 'public.find_matches(uuid,int)'::regprocedure));

-- =============================================================================
-- B. car 'neighbourhood' rule (main zone lat 16.43). Drivers: 1 (default 2000), 12 (1000), 14 (legacy NULL), 15 (500), 16 (5000).
--    Driver route O -> E = 7.5 km straight east, depart +1 h. A "dest short by X" rider ends X m before E, on the same line.
-- =============================================================================
select gwm_test.rtrip(1,  'car', 'driver', gwm_test.pt(16.43, 0), gwm_test.pt(16.43, 7500), interval '1 hour');
select gwm_test.rtrip(12, 'car', 'driver', gwm_test.pt(16.43, 0), gwm_test.pt(16.43, 7500), interval '1 hour', null, null, 1000);
select gwm_test.rtrip(14, 'car', 'driver', gwm_test.pt(16.43, 0), gwm_test.pt(16.43, 7500), interval '1 hour');
update public.trips set max_dropoff_m = null where id = gwm_test.tid(14);                       -- legacy driver row (superuser)
select gwm_test.rtrip(15, 'car', 'driver', gwm_test.pt(16.43, 0), gwm_test.pt(16.43, 7500), interval '1 hour', null, null, 500);
select gwm_test.rtrip(16, 'car', 'driver', gwm_test.pt(16.43, 0), gwm_test.pt(16.43, 7500), interval '1 hour', null, null, 5000);
-- 2 = REGRESSION: origin 1 m from the driver's, +66 s (1.1 min), route fully on the driver's route, destination 2461 m short of the driver's
select gwm_test.rtrip(2, 'car', 'rider', gwm_test.pt(16.43, 1), ST_Project(gwm_test.pt(16.43, 7500), 2461, 3 * pi() / 2), interval '1 hour 66 seconds');
select gwm_test.rtrip(3, 'car', 'rider', gwm_test.pt(16.43, 1), ST_Project(gwm_test.pt(16.43, 7500), 2000, 3 * pi() / 2), interval '1 hour');     -- dest exactly 2000 m short
select gwm_test.rtrip(4, 'car', 'rider', gwm_test.pt(16.43, 1), ST_Project(gwm_test.pt(16.43, 7500), 2000.1, 3 * pi() / 2), interval '1 hour');   -- 2000.1 m short
select gwm_test.rtrip(5, 'car', 'rider', gwm_test.pt(16.43, 2000), gwm_test.pt(16.43, 7500), interval '1 hour');                                  -- origin exactly 2000 m from the driver's
select gwm_test.rtrip(6, 'car', 'rider', gwm_test.pt(16.43, 2000.1), gwm_test.pt(16.43, 7500), interval '1 hour');                                -- origin 2000.1 m
select gwm_test.rtrip(7, 'car', 'rider', gwm_test.pt(16.43, 0), gwm_test.pt(16.43, 7500), interval '1 hour 29 minutes');                          -- 29 min later
select gwm_test.rtrip(8, 'car', 'rider', gwm_test.pt(16.43, 0), gwm_test.pt(16.43, 7500), interval '1 hour 30 minutes');                          -- exactly 30 min
select gwm_test.rtrip(9, 'car', 'rider', gwm_test.pt(16.43, 0), gwm_test.pt(16.43, 7500), interval '1 hour 31 minutes');                          -- 31 min
select gwm_test.rtrip(10, 'car', 'rider', gwm_test.pt(16.43, 2500), gwm_test.pt(16.43, 7500), interval '1 hour');                                 -- origin 2500 m (far origin)
select gwm_test.rtrip(11, 'car', 'rider', gwm_test.pt(16.43, 0), gwm_test.pt(16.43, 7500), interval '1 hour');                                    -- same trip as the driver
select gwm_test.rtrip(13, 'car', 'rider', gwm_test.pt(16.43, 1), gwm_test.pt(16.43, 6000), interval '1 hour', gwm_test.pt(16.43, 3000, 4000));   -- 4 km dogleg: low overlap
select gwm_test.rtrip(17, 'car', 'rider', gwm_test.pt(16.43, 0), gwm_test.pt(16.43, 7500), interval '1 hour');                                    -- best score
select gwm_test.rtrip(18, 'car', 'rider', gwm_test.pt(16.43, 1500), gwm_test.pt(16.43, 6000), interval '1 hour');                                 -- 1.5 km / 1.5 km off
select gwm_test.rtrip(19, 'car', 'rider', gwm_test.pt(16.43, 0), gwm_test.pt(16.43, 7500), interval '1 hour');                                    -- exact twin of 17 (tie)
select gwm_test.rtrip(20, 'car', 'rider', gwm_test.pt(16.43, 0), gwm_test.pt(16.43, 7500), interval '1 hour 20 minutes');                         -- same, 20 min later
select gwm_test.rtrip(21, 'car', 'rider', gwm_test.pt(16.43, 1), ST_Project(gwm_test.pt(16.43, 7500), 480, 3 * pi() / 2), interval '1 hour');     -- dest 480 m short
select gwm_test.rtrip(22, 'car', 'rider', gwm_test.pt(16.43, 1), ST_Project(gwm_test.pt(16.43, 7500), 4900, 3 * pi() / 2), interval '1 hour');    -- dest 4900 m short

-- ---- B1 REGRESSION (the real bug) -----------------------------------------------------------------------------
select gwm_test.chk('B1 fixture: origins ~1 m apart, dests ~2461 m apart, 1.1 min, driver limit 2000',
  (select round(ST_Distance(a.origin, b.origin)) = 1 and round(ST_Distance(a.dest, b.dest)) = 2461 and a.max_dropoff_m = 2000
          and round((extract(epoch from (b.depart_at - a.depart_at)) / 60.0)::numeric, 1) = 1.1
     from public.trips a, public.trips b where a.id = gwm_test.tid(1) and b.id = gwm_test.tid(2)));
select gwm_test.chk('B1 REGRESSION: limit 2000 m -> NOT matched, on BOTH sides (match_candidates)', gwm_test.sym(1, 2) = 0);
select gwm_test.chk('B1 the same pair, both sides, via the rule function: stage 2 (far destination)',
  (select e.stage = 2 from public.trips d, public.trips r, lateral public._car_rule_eval(d.origin, d.dest, d.route, d.max_dropoff_m, d.detour_tolerance_m, r.origin, r.dest, r.route) e
    where d.id = gwm_test.tid(1) and r.id = gwm_test.tid(2)));
select gwm_test.as_user(gwm_test.uid(2));
select gwm_test.chk('B1 find_matches as Rider: Driver 1 not listed at limit 2000', (select count(*) = 0 from public.find_matches(gwm_test.tid(2), 50) where trip_id = gwm_test.tid(1)));
select gwm_test.expect_error('B1 request_match Rider -> Driver refused at limit 2000', $q$select public.request_match(gwm_test.tid(2), gwm_test.tid(1))$q$, 'GWM_NOT_ELIGIBLE');
select gwm_test.as_user(gwm_test.uid(1));
select gwm_test.chk('B1 find_matches as Driver: Rider 2 not listed', (select count(*) = 0 from public.find_matches(gwm_test.tid(1), 50) where trip_id = gwm_test.tid(2)));
select gwm_test.expect_error('B1 request_match Driver -> Rider refused at limit 2000', $q$select public.request_match(gwm_test.tid(1), gwm_test.tid(2))$q$, 'GWM_NOT_ELIGIBLE');
select gwm_test.reset();

-- ---- B2 boundaries (limit 2000, origin radius 2000, overlap 40, window 30), each from BOTH sides -----------------------------
select gwm_test.chk('B2 dest distance == limit (2000.0 m) passes, both sides', gwm_test.sym(1, 3) = 1);
select gwm_test.chk('B2 dest distance limit + 0.1 m fails, both sides', gwm_test.sym(1, 4) = 0);
select gwm_test.chk('B2 origin distance == radius (2000.0 m) passes, both sides', gwm_test.sym(1, 5) = 1);
select gwm_test.chk('B2 origin distance radius + 0.1 m fails, both sides', gwm_test.sym(1, 6) = 0);
select gwm_test.chk('B2 origin 2500 m fails (far origin), both sides', gwm_test.sym(1, 10) = 0);
select gwm_test.chk('B2 time: 29 min ok, exactly 30 min ok, 31 min fails (both sides)', gwm_test.sym(1, 7) = 1 and gwm_test.sym(1, 8) = 1 and gwm_test.sym(1, 9) = 0);
select gwm_test.chk('B2 identical trip matches (baseline), both sides', gwm_test.sym(1, 11) = 1);
select gwm_test.chk('B2 Driver<->Driver / Rider<->Rider still excluded', gwm_test.cand_count(1, 12) = 0 and gwm_test.cand_count(2, 3) = 0);
select gwm_test.chk('B2 stage report: rider 10 -> 1, rider 4 -> 2, rider 13 (dogleg) -> 3, rider 3 -> 0',
  (select array_agg(s order by k) = array[1, 2, 3, 0] from (
     select k, (select e.stage from public._car_rule_eval(d.origin, d.dest, d.route, d.max_dropoff_m, d.detour_tolerance_m, r.origin, r.dest, r.route) e) as s
       from unnest(array[10, 4, 13, 3]) with ordinality as u(t, k)
       join public.trips r on r.id = gwm_test.tid(u.t), public.trips d where d.id = gwm_test.tid(1)) q));
select gwm_test.chk('B2 overlap of rider 13 is below 40 (dogleg)', (select e.ov < 40 from public.trips d, public.trips r,
  lateral public._car_rule_eval(d.origin, d.dest, d.route, d.max_dropoff_m, d.detour_tolerance_m, r.origin, r.dest, r.route) e where d.id = gwm_test.tid(1) and r.id = gwm_test.tid(13)));
select gwm_test.chk('B2 symmetry over the whole population (driver 1 vs every rider)',
  (select count(*) = 0 from unnest(array[2,3,4,5,6,7,8,9,10,11,13,17,18,19,20,21,22]) r where gwm_test.sym(1, r) = -1));

-- ---- B3 config drives the outcome (== passes, a hair over fails) ---------------------------------------------------------------
select gwm_test.setcfg('match.car_origin_radius_m', '2500');
select gwm_test.chk('B3 origin radius 2500: rider 10 (2500.0 m) passes, both sides', gwm_test.sym(1, 10) = 1);
select gwm_test.setcfg('match.car_origin_radius_m', '2499.9');
select gwm_test.chk('B3 origin radius 2499.9: rider 10 fails', gwm_test.sym(1, 10) = 0);
select gwm_test.setcfg('match.car_origin_radius_m', '2000');
select gwm_test.setcfg('match.min_overlap_pct',
  (select round(e.ov::numeric, 1)::text from public.trips d, public.trips r, lateral public._car_rule_eval(d.origin, d.dest, d.route, d.max_dropoff_m, d.detour_tolerance_m, r.origin, r.dest, r.route) e
    where d.id = gwm_test.tid(1) and r.id = gwm_test.tid(13)));
select gwm_test.chk('B3 overlap == measured (rounded 0.1 %): rider 13 passes, both sides', gwm_test.sym(1, 13) = 1);
select gwm_test.setcfg('match.min_overlap_pct', ((public.cfg_num('match.min_overlap_pct') + 0.2)::numeric)::text);
select gwm_test.chk('B3 overlap threshold 0.2 % higher: fails', gwm_test.sym(1, 13) = 0);
select gwm_test.setcfg('match.min_overlap_pct', '40');
select gwm_test.setcfg('match.time_window_min', '25');
select gwm_test.chk('B3 time window 25: 29 min fails', gwm_test.sym(1, 7) = 0);
select gwm_test.setcfg('match.time_window_min', '30');
select gwm_test.setcfg('match.dest_radius_m', '100');
select gwm_test.chk('B3 match.dest_radius_m is NOT used for car (100 m): rider 3 still matches', gwm_test.sym(1, 3) = 1);
select gwm_test.setcfg('match.dest_radius_m', '2000');
select gwm_test.setcfg('match.car_rule', '"foo"');
select gwm_test.chk('B3 unknown match.car_rule behaves as neighbourhood', gwm_test.sym(1, 3) = 1 and gwm_test.sym(1, 4) = 0 and gwm_test.sym(1, 2) = 0);
select gwm_test.setcfg('match.car_rule', '"neighbourhood"');

-- ---- B4 per-Driver limit: 500 / 1000 / 3000 / 5000 / NULL -> 2000, ceiling from config ------------------------------------------
select gwm_test.chk('B4 legacy NULL limit behaves as 2000: rider 3 (2000.0) yes, rider 2 (2461) no', gwm_test.sym(14, 3) = 1 and gwm_test.sym(14, 2) = 0);
select gwm_test.chk('B4 limit 500: rider 21 (480) yes, rider 2 (2461) no', gwm_test.sym(15, 21) = 1 and gwm_test.sym(15, 2) = 0);
select gwm_test.chk('B4 limit 5000: rider 22 (4900) yes, rider 2 (2461) yes', gwm_test.sym(16, 22) = 1 and gwm_test.sym(16, 2) = 1);
select gwm_test.chk('B4 rider 2 (2461) passes driver 16 (5000) but not driver 12 (1000): the limit is PER Driver trip',
  gwm_test.sym(16, 2) = 1 and gwm_test.sym(12, 2) = 0);
select gwm_test.setcfg('match.car_dest_radius_max_m', '3000');
select gwm_test.chk('B4 ceiling 3000 caps driver 16 (5000): rider 22 (4900) no, rider 2 (2461) yes', gwm_test.sym(16, 22) = 0 and gwm_test.sym(16, 2) = 1);
select gwm_test.as_user(gwm_test.uid(2));
select gwm_test.chk('B4 find_matches shows the EFFECTIVE limit (driver 16: least(5000, 3000) = 3000; driver 15: 500)',
  (select max_dropoff_m from public.find_matches(gwm_test.tid(2), 50) where trip_id = gwm_test.tid(16)) = 3000);
select gwm_test.reset();
select gwm_test.setcfg('match.car_dest_radius_max_m', '5000');

-- ---- B5 trips.max_dropoff_m validation (insert path = client insert; server rejects, never rounds) -----------------------------
select gwm_test.signup(i) from generate_series(24, 25) i;
select gwm_test.expect_error('B5 400 rejected (below 500)', $q$select gwm_test.rtrip(24, 'car', 'driver', gwm_test.pt(16.43, 0), gwm_test.pt(16.43, 3000), interval '1 hour', null, 240, 400)$q$, 'GWM_DROPOFF_INVALID');
select gwm_test.expect_error('B5 5100 rejected (above the config ceiling)', $q$select gwm_test.rtrip(24, 'car', 'driver', gwm_test.pt(16.43, 0), gwm_test.pt(16.43, 3000), interval '1 hour', null, 240, 5100)$q$, 'GWM_DROPOFF_INVALID');
select gwm_test.expect_error('B5 1050 rejected (not a multiple of 100; not rounded)', $q$select gwm_test.rtrip(24, 'car', 'driver', gwm_test.pt(16.43, 0), gwm_test.pt(16.43, 3000), interval '1 hour', null, 240, 1050)$q$, 'GWM_DROPOFF_INVALID');
select gwm_test.expect_error('B5 negative rejected', $q$select gwm_test.rtrip(24, 'car', 'driver', gwm_test.pt(16.43, 0), gwm_test.pt(16.43, 3000), interval '1 hour', null, 240, -100)$q$, 'GWM_DROPOFF_INVALID');
select gwm_test.expect_error('B5 a Rider trip carries no limit', $q$select gwm_test.rtrip(25, 'car', 'rider', gwm_test.pt(16.43, 0), gwm_test.pt(16.43, 3000), interval '1 hour', null, 250, 1000)$q$, 'GWM_DROPOFF_NOT_ALLOWED');
select gwm_test.expect_error('B5 a walk trip carries no limit', $q$select gwm_test.rtrip(25, 'walk', null, gwm_test.pt(16.43, 0), gwm_test.pt(16.43, 3000), interval '1 hour', null, 251, 1000)$q$, 'GWM_DROPOFF_NOT_ALLOWED');
select gwm_test.setcfg('match.car_dest_radius_max_m', '3000');
select gwm_test.expect_error('B5 ceiling from config: 3100 rejected when the ceiling is 3000', $q$select gwm_test.rtrip(24, 'car', 'driver', gwm_test.pt(16.43, 0), gwm_test.pt(16.43, 3000), interval '1 hour', null, 240, 3100)$q$, 'GWM_DROPOFF_INVALID');
select gwm_test.setcfg('match.car_dest_radius_max_m', '5000');
select gwm_test.expect_ok('B5 500 and 5000 accepted (range ends)', $q$select gwm_test.rtrip(24, 'car', 'driver', gwm_test.pt(16.43, 0), gwm_test.pt(16.43, 3000), interval '1 hour', null, 240, 5000)$q$);
select gwm_test.chk('B5 driver trip without a value stores 2000 (default); Rider trip stores NULL',
  (select max_dropoff_m = 2000 from public.trips where id = gwm_test.tid(1)) and (select max_dropoff_m is null from public.trips where id = gwm_test.tid(2)));
select gwm_test.as_user(gwm_test.uid(1));
select gwm_test.expect_error('B5 update: 3050 rejected', $q$update public.trips set max_dropoff_m = 3050 where id = gwm_test.tid(1)$q$, 'GWM_DROPOFF_INVALID');
select gwm_test.expect_error('B5 update: 400 rejected', $q$update public.trips set max_dropoff_m = 400 where id = gwm_test.tid(1)$q$, 'GWM_DROPOFF_INVALID');
select gwm_test.expect_error('B5 update: NULL rejected', $q$update public.trips set max_dropoff_m = null where id = gwm_test.tid(1)$q$, 'GWM_DROPOFF_INVALID');
select gwm_test.as_user(gwm_test.uid(2));
select gwm_test.expect_error('B5 update on a Rider trip rejected', $q$update public.trips set max_dropoff_m = 1000 where id = gwm_test.tid(2)$q$, 'GWM_DROPOFF_NOT_ALLOWED');
select gwm_test.as_user(gwm_test.uid(1));
select gwm_test.expect_ok('B5 Driver 1 raises the limit to 3000 (no pending request, editable)', $q$update public.trips set max_dropoff_m = 3000 where id = gwm_test.tid(1)$q$);
select gwm_test.reset();
select gwm_test.chk('B5 value stored', (select max_dropoff_m = 3000 from public.trips where id = gwm_test.tid(1)));

-- ---- B6 REGRESSION at limit 3000: MATCHED on both sides (search, find_matches, request_match, respond_match) -----------------
select gwm_test.chk('B6 REGRESSION: limit 3000 -> matched, both sides (match_candidates)', gwm_test.sym(1, 2) = 1);
select gwm_test.chk('B6 reported metrics: 1.1 min, overlap ~100 %, origin ~1 m',
  (select round(c.time_diff_min::numeric, 1) = 1.1 and c.overlap_pct > 99 and c.origin_distance_m < 5
     from public.match_candidates(gwm_test.tid(1), 50) c where c.candidate_trip_id = gwm_test.tid(2)));
select gwm_test.chk('B6 rider 22 (4900) still fails driver 1 at 3000, rider 2 passes driver 12? (1000) no', gwm_test.sym(1, 22) = 0 and gwm_test.sym(12, 2) = 0);
select gwm_test.as_user(gwm_test.uid(2));
select gwm_test.chk('B6 find_matches as Rider lists Driver 1 with role driver, max_dropoff_m = 3000 (effective), overlap multiple of 5, dest blurred but present',
  (select count(*) = 1 and bool_and(role = 'driver') and bool_and(max_dropoff_m = 3000) and bool_and(overlap_pct % 5 = 0) and bool_and(approx_dest_lat is not null)
     from public.find_matches(gwm_test.tid(2), 50) where trip_id = gwm_test.tid(1)));
select gwm_test.as_user(gwm_test.uid(1));
select gwm_test.chk('B6 find_matches as Driver lists Rider 2; PRIVACY: no destination coordinates, no max_dropoff_m',
  (select count(*) = 1 and bool_and(role = 'rider') and bool_and(approx_dest_lat is null and approx_dest_lng is null) and bool_and(max_dropoff_m is null)
     from public.find_matches(gwm_test.tid(1), 50) where trip_id = gwm_test.tid(2)));
select gwm_test.chk('B6 the Driver still gets the Rider''s blurred ORIGIN (as before)',
  (select bool_and(approx_origin_lat is not null) from public.find_matches(gwm_test.tid(1), 50) where trip_id = gwm_test.tid(2)));
select gwm_test.chk('B6 no vehicle / detour / exact-distance columns in find_matches',
  pg_get_function_result('public.find_matches(uuid,int)'::regprocedure) !~* '(plate|model|color|vehicle|detour|dest_distance)');
select gwm_test.reset();

-- ---- B7 score ordering + determinism ---------------------------------------------------------------------------------------
select gwm_test.chk('B7 closer origin/destination scores higher: rider 17 (0/0 m) > rider 18 (1500/1500 m)',
  (select (select score from public.match_candidates(gwm_test.tid(1), 50) where candidate_trip_id = gwm_test.tid(17))
        > (select score from public.match_candidates(gwm_test.tid(1), 50) where candidate_trip_id = gwm_test.tid(18))));
select gwm_test.chk('B7 closer departure scores higher: 17 (+0) > 20 (+20 min)',
  (select (select score from public.match_candidates(gwm_test.tid(1), 50) where candidate_trip_id = gwm_test.tid(17))
        > (select score from public.match_candidates(gwm_test.tid(1), 50) where candidate_trip_id = gwm_test.tid(20))));
select gwm_test.chk('B7 twins 17 and 19 tie on score; repeated calls give the identical order; tie -> 17 before 19',
  (select (select score from public.match_candidates(gwm_test.tid(1), 50) where candidate_trip_id = gwm_test.tid(17))
        = (select score from public.match_candidates(gwm_test.tid(1), 50) where candidate_trip_id = gwm_test.tid(19)))
  and array(select candidate_trip_id from public.match_candidates(gwm_test.tid(1), 50)) = array(select candidate_trip_id from public.match_candidates(gwm_test.tid(1), 50))
  and (select array_position(a, gwm_test.tid(17)) < array_position(a, gwm_test.tid(19))
         from (select array(select candidate_trip_id from public.match_candidates(gwm_test.tid(1), 50)) as a) q));
select gwm_test.as_user(gwm_test.uid(17));
select gwm_test.chk('B7 hint says has_results while candidates exist', public.get_match_hint(gwm_test.tid(17)) = 'has_results');
select gwm_test.reset();

-- ---- B8 Peer modes unchanged: dest radius still applies to walkers ---------------------------------------------------------
select gwm_test.rtrip(50, 'walk', null, gwm_test.pt(16.50, 0), gwm_test.pt(16.50, 3000), interval '1 hour');
select gwm_test.rtrip(51, 'walk', null, gwm_test.pt(16.50, 0), gwm_test.pt(16.50, 5461), interval '1 hour');
select gwm_test.rtrip(52, 'walk', null, gwm_test.pt(16.50, 0), gwm_test.pt(16.50, 4500), interval '1 hour');
select gwm_test.chk('B8 PEER: destinations 2461 m apart still rejected (dest radius 2000 m applies to walk)', gwm_test.sym(50, 51) = 0);
select gwm_test.chk('B8 PEER: destinations ~1.5 km apart still matched', gwm_test.sym(50, 52) = 1);
select gwm_test.as_user(gwm_test.uid(50));
select gwm_test.chk('B8 peer output: max_dropoff_m NULL, destination coordinates still returned',
  (select count(*) >= 1 and bool_and(max_dropoff_m is null) and bool_and(approx_dest_lat is not null) from public.find_matches(gwm_test.tid(50))));
select gwm_test.reset();

-- ---- B9 backend enforcement: request_match + respond_match use the same predicate; edit lock ---------------------------------
select gwm_test.as_user(gwm_test.uid(22));
select gwm_test.expect_error('B9 Rider 22 (4900 m) cannot request Driver 1 (limit 3000), direct RPC', $q$select public.request_match(gwm_test.tid(22), gwm_test.tid(1))$q$, 'GWM_NOT_ELIGIBLE');
select gwm_test.as_user(gwm_test.uid(10));
select gwm_test.expect_error('B9 Rider 10 (origin 2500 m) cannot request', $q$select public.request_match(gwm_test.tid(10), gwm_test.tid(1))$q$, 'GWM_NOT_ELIGIBLE');
select gwm_test.as_user(gwm_test.uid(9));
select gwm_test.expect_error('B9 Rider 9 (31 min) cannot request', $q$select public.request_match(gwm_test.tid(9), gwm_test.tid(1))$q$, 'GWM_NOT_ELIGIBLE');
select gwm_test.as_user(gwm_test.uid(1));
select gwm_test.expect_error('B9 Driver 1 cannot request Rider 22 either', $q$select public.request_match(gwm_test.tid(1), gwm_test.tid(22))$q$, 'GWM_NOT_ELIGIBLE');
select gwm_test.expect_ok('B9 Driver 1 -> Rider 11 request', $q$select public.request_match(gwm_test.tid(1), gwm_test.tid(11))$q$);
select gwm_test.as_user(gwm_test.uid(2));
select gwm_test.expect_ok('B9 REGRESSION (limit 3000): Rider 2 -> Driver 1 request_match succeeds', $q$select public.request_match(gwm_test.tid(2), gwm_test.tid(1))$q$);
select gwm_test.as_user(gwm_test.uid(3));
select gwm_test.expect_ok('B9 Rider 3 -> Driver 1 request', $q$select public.request_match(gwm_test.tid(3), gwm_test.tid(1))$q$);
select gwm_test.reset();
select gwm_test.chk('B9 requests remember the rule check; matches.dest_distance_m is NOT stored for car',
  (select count(*) = 3 and bool_and(car_rule_checked) and bool_and(dest_distance_m is null) from public.matches where driver_trip_id = gwm_test.tid(1)));
select gwm_test.as_user(gwm_test.uid(1));
select gwm_test.chk('B9 get_trip_card as Driver: the Rider''s destination is never returned',
  (select approx_dest_lat is null and approx_dest_lng is null and approx_origin_lat is not null from public.get_trip_card(gwm_test.tid(2))));
select gwm_test.expect_error('B9 EDIT LOCK: max_dropoff_m cannot change while a request is pending', $q$update public.trips set max_dropoff_m = 4000 where id = gwm_test.tid(1)$q$, 'GWM_TRIP_HAS_MATCHES');
select gwm_test.as_user(gwm_test.uid(2));
select gwm_test.chk('B9 get_trip_card as Rider: the Driver card still has its (blurred) destination', (select approx_dest_lat is not null from public.get_trip_card(gwm_test.tid(1))));
select gwm_test.reset();
select gwm_test.chk('B9 the locked value did not change', (select max_dropoff_m = 3000 from public.trips where id = gwm_test.tid(1)));
-- lock released after the request is cancelled
select gwm_test.as_user(gwm_test.uid(22));
select gwm_test.expect_ok('B9 Rider 22 -> Driver 16 (limit 5000) request', $q$select public.request_match(gwm_test.tid(22), gwm_test.tid(16))$q$);
select gwm_test.as_user(gwm_test.uid(16));
select gwm_test.expect_error('B9 driver 16 locked while pending', $q$update public.trips set max_dropoff_m = 4000 where id = gwm_test.tid(16)$q$, 'GWM_TRIP_HAS_MATCHES');
select gwm_test.as_user(gwm_test.uid(22));
select gwm_test.expect_ok('B9 Rider 22 cancels the request', format($q$select public.cancel_match(%L)$q$, gwm_test.mid(22, 16)));
select gwm_test.as_user(gwm_test.uid(16));
select gwm_test.expect_ok('B9 driver 16 can edit again after the request ended', $q$update public.trips set max_dropoff_m = 4000 where id = gwm_test.tid(16)$q$);
select gwm_test.reset();

-- respond_match re-checks with the SAME predicate (current config / values) for rows created by 0009 ------------------------
select gwm_test.setcfg('match.min_overlap_pct', '101');                                   -- nobody qualifies any more
select gwm_test.as_user(gwm_test.uid(1));
select gwm_test.expect_error('B9 accept of a car_rule_checked request that no longer satisfies the predicate is refused',
  format($q$select public.respond_match(%L, true)$q$, gwm_test.mid(3, 1)), 'GWM_NOT_ELIGIBLE');
select gwm_test.expect_ok('B9 decline needs no predicate', format($q$select public.respond_match(%L, false)$q$, gwm_test.mid(3, 1)));
select gwm_test.reset();
select gwm_test.setcfg('match.min_overlap_pct', '40');
select gwm_test.as_user(gwm_test.uid(21));
select gwm_test.expect_ok('B9 legacy setup: Rider 21 -> Driver 12 pending', $q$select public.request_match(gwm_test.tid(21), gwm_test.tid(12))$q$);
select gwm_test.reset();
update public.matches set car_rule_checked = false where id = gwm_test.mid(21, 12);
select gwm_test.setcfg('match.min_overlap_pct', '101');
select gwm_test.as_user(gwm_test.uid(12));
select gwm_test.expect_ok('B9 pre-0009 pending row (car_rule_checked = false) is honoured as it was', format($q$select public.respond_match(%L, true)$q$, gwm_test.mid(21, 12)));
select gwm_test.reset();
select gwm_test.setcfg('match.min_overlap_pct', '40');
select gwm_test.as_user(gwm_test.uid(1));
select gwm_test.expect_ok('B9 REGRESSION: Driver 1 accepts Rider 2 (respond_match, limit 3000)', format($q$select public.respond_match(%L, true)$q$, gwm_test.mid(2, 1)));
select gwm_test.reset();
select gwm_test.chk('B9 accepted; other pending requests of the trip were auto-closed (US-16 kept)',
  (select status = 'accepted' from public.matches where id = gwm_test.mid(2, 1))
  and (select status = 'cancelled' and auto_closed from public.matches where id = gwm_test.mid(1, 11)));

-- ---- B10 the OPTIONAL corridor rule still works when switched on (zone lat 16.60; nobody here touches max_dropoff_m) ---------------------
select gwm_test.signup(i) from generate_series(90, 96) i;
select gwm_test.rtrip(90, 'car', 'driver', gwm_test.pt(16.60, 0), gwm_test.pt(16.60, 7500), interval '1 hour');
select gwm_test.rtrip(91, 'car', 'rider', gwm_test.pt(16.60, 1), ST_Project(gwm_test.pt(16.60, 7500), 2461, 3 * pi() / 2), interval '1 hour 66 seconds');   -- the regression rider
select gwm_test.rtrip(92, 'car', 'rider', gwm_test.pt(16.60, 5000), gwm_test.pt(16.60, 1000), interval '1 hour');                                          -- opposite direction
select gwm_test.rtrip(93, 'car', 'rider', gwm_test.pt(16.60, 1000, 1500), gwm_test.pt(16.60, 4000), interval '1 hour');                                    -- pickup 1.5 km off
select gwm_test.rtrip(94, 'car', 'rider', gwm_test.pt(16.60, 1000, 900), gwm_test.pt(16.60, 4000, 900), interval '1 hour');                                -- detour ~3.6 km
select gwm_test.rtrip(95, 'car', 'rider', gwm_test.pt(16.60, 1000), gwm_test.pt(16.60, 9000), interval '1 hour');                                          -- drop 1.5 km beyond
select gwm_test.rtrip(96, 'car', 'rider', gwm_test.pt(16.60, 1000), gwm_test.pt(16.60, 6000), interval '1 hour', gwm_test.pt(16.60, 3500, 6000));         -- dogleg
select gwm_test.chk('B10 (rule neighbourhood) the regression rider 91 is NOT matched at limit 2000', gwm_test.sym(90, 91) = 0);
select gwm_test.setcfg('match.car_rule', '"corridor"');
select gwm_test.chk('B10 corridor rule ON: regression rider 91 (2461 m) IS matched, both sides (max_dropoff_m ignored)', gwm_test.sym(90, 91) = 1);
select gwm_test.chk('B10 corridor: opposite direction rejected, both sides', gwm_test.sym(90, 92) = 0);
select gwm_test.chk('B10 corridor: pickup 1.5 km off rejected', gwm_test.sym(90, 93) = 0);
select gwm_test.chk('B10 corridor: excessive detour rejected', gwm_test.sym(90, 94) = 0);
select gwm_test.chk('B10 corridor: drop-off beyond the destination rejected', gwm_test.sym(90, 95) = 0);
select gwm_test.chk('B10 corridor: low coverage (dogleg) rejected', gwm_test.sym(90, 96) = 0);
select gwm_test.setcfg('match.car_max_detour_m',
  (select round(e.detour_m::numeric, 1)::text from public.trips d, public.trips r,
          lateral public._car_corridor_eval(d.route, r.route, r.origin, r.dest) e where d.id = gwm_test.tid(90) and r.id = gwm_test.tid(94)));
select gwm_test.chk('B10 corridor: detour == estimate passes; 0.1 m smaller fails (config driven)', gwm_test.sym(90, 94) = 1);
select gwm_test.setcfg('match.car_max_detour_m', ((public.cfg_num('match.car_max_detour_m') - 0.1)::numeric)::text);
select gwm_test.chk('B10 corridor: detour threshold - 0.1 m fails', gwm_test.sym(90, 94) = 0);
select gwm_test.setcfg('match.car_max_detour_m', '3000');
select gwm_test.as_user(gwm_test.uid(91));
select gwm_test.expect_ok('B10 corridor: request_match uses the same predicate (regression rider requests)', $q$select public.request_match(gwm_test.tid(91), gwm_test.tid(90))$q$);
select gwm_test.as_user(gwm_test.uid(92));
select gwm_test.expect_error('B10 corridor: opposite-direction rider refused at request_match', $q$select public.request_match(gwm_test.tid(92), gwm_test.tid(90))$q$, 'GWM_NOT_ELIGIBLE');
select gwm_test.reset();
select gwm_test.setcfg('match.car_rule', '"neighbourhood"');
select gwm_test.chk('B10 switched back: regression rider 91 not matched again', gwm_test.sym(90, 91) = 0);

-- =============================================================================
-- C. no-match hint (P1): category only (has_results / none_found / far_destination / far_origin), read-only, rate limited
-- =============================================================================
select gwm_test.signup(i) from generate_series(30, 39) i;
select gwm_test.rtrip(30, 'car', 'driver', gwm_test.pt(16.80, 0), gwm_test.pt(16.80, 6000), interval '1 hour');
select gwm_test.chk('C1 return type is plain text (no counts / ids / numbers)', pg_get_function_result('public.get_match_hint(uuid)'::regprocedure) = 'text');
select gwm_test.as_user(gwm_test.uid(30));
select gwm_test.chk('C1 nobody around -> none_found', public.get_match_hint(gwm_test.tid(30)) = 'none_found');
select gwm_test.reset();
select gwm_test.rtrip(31, 'car', 'rider', gwm_test.pt(16.80, 1), ST_Project(gwm_test.pt(16.80, 6000), 2461, 3 * pi() / 2), interval '1 hour');   -- REGRESSION shape
select gwm_test.rtrip(32, 'car', 'rider', gwm_test.pt(16.80, 3000), gwm_test.pt(16.80, 6000), interval '1 hour');                                 -- origin 3 km away
select gwm_test.as_user(gwm_test.uid(30));
select gwm_test.chk('C2 in-window Rider whose destination exceeds the Driver limit (2000) -> far_destination (priority over far_origin)',
  public.get_match_hint(gwm_test.tid(30)) = 'far_destination');
select gwm_test.expect_error('C3 hint only for the caller''s own trip', $q$select public.get_match_hint(gwm_test.tid(31))$q$, 'GWM_TRIP_NOT_FOUND');
select gwm_test.reset();
select gwm_test.rtrip(35, 'car', 'driver', gwm_test.pt(16.85, 0), gwm_test.pt(16.85, 6000), interval '1 hour');
select gwm_test.rtrip(36, 'car', 'rider', gwm_test.pt(16.85, 3000), gwm_test.pt(16.85, 6000), interval '1 hour');
select gwm_test.as_user(gwm_test.uid(35));
select gwm_test.chk('C4 only the origin is too far -> far_origin', public.get_match_hint(gwm_test.tid(35)) = 'far_origin');
select gwm_test.reset();
select gwm_test.rtrip(38, 'car', 'driver', gwm_test.pt(18.00, 0), gwm_test.pt(18.00, 6000), interval '1 hour');
select gwm_test.rtrip(39, 'car', 'rider', gwm_test.pt(18.00, 500), gwm_test.pt(18.00, 5500), interval '5 hours');                                 -- perfect fit but outside the window
select gwm_test.as_user(gwm_test.uid(38));
select gwm_test.chk('C5 a trip only OUTSIDE the time window leaks nothing -> none_found', public.get_match_hint(gwm_test.tid(38)) = 'none_found');
select gwm_test.reset();
select gwm_test.rtrip(33, 'car', 'driver', gwm_test.pt(16.75, 0), gwm_test.pt(16.75, 6000), interval '1 hour', null, null, 1000);
select gwm_test.rtrip(34, 'car', 'rider', gwm_test.pt(16.75, 1), ST_Project(gwm_test.pt(16.75, 6000), 1500, 3 * pi() / 2), interval '1 hour');
select gwm_test.as_user(gwm_test.uid(34));
select gwm_test.chk('C6 Rider searching: destination beyond the DRIVER''s own limit (1000) -> far_destination', public.get_match_hint(gwm_test.tid(34)) = 'far_destination');
select gwm_test.reset();
select gwm_test.setcfg('throttle.match_hint_per_min', '2');
select gwm_test.as_user(gwm_test.uid(36));
select gwm_test.expect_ok('C7 hint call 1', $q$select public.get_match_hint(gwm_test.tid(36))$q$);
select gwm_test.expect_ok('C7 hint call 2', $q$select public.get_match_hint(gwm_test.tid(36))$q$);
select gwm_test.expect_error('C7 hint call 3 in the same minute is rate limited', $q$select public.get_match_hint(gwm_test.tid(36))$q$, 'GWM_RATE_LIMITED');
select gwm_test.reset();
select gwm_test.setcfg('throttle.match_hint_per_min', '1000');
select gwm_test.chk('C8 hint has no side effects (no matches rows created by it)', (select count(*) from public.matches where requester_trip_id in (gwm_test.tid(30), gwm_test.tid(34), gwm_test.tid(35))) = 0);

-- =============================================================================
-- D. US-22 avatars
-- =============================================================================
select gwm_test.rtrip(41, 'car', 'driver', gwm_test.pt(16.90, 0), gwm_test.pt(16.90, 5000), interval '1 hour');
select gwm_test.rtrip(40, 'car', 'rider',  gwm_test.pt(16.90, 500), gwm_test.pt(16.90, 4000), interval '1 hour');
select gwm_test.rtrip(43, 'car', 'rider',  gwm_test.pt(16.90, 600), gwm_test.pt(16.90, 3900), interval '1 hour');       -- pending only
select gwm_test.rtrip(42, 'walk', null, gwm_test.pt(17.10, 0), gwm_test.pt(17.10, 3000), interval '1 hour');            -- stranger

-- storage fixture (only when the storage schema exists): the object the client would have uploaded
do $$ begin
  if to_regclass('storage.objects') is not null then
    insert into storage.objects (bucket_id, name, owner, metadata)
    values ('avatars', gwm_test.uid(40)::text || '/avatar.jpg', gwm_test.uid(40), '{"mimetype":"image/jpeg","size":1000}'::jsonb);
  end if;
end $$;

select gwm_test.as_user(gwm_test.uid(40));
select gwm_test.expect_error('D1 avatar path in another user''s folder rejected', format($q$select public.set_my_avatar(%L)$q$, gwm_test.uid(41)::text || '/avatar.jpg'), 'GWM_AVATAR_INVALID');
select gwm_test.expect_error('D1 avatar path with another file name / extension rejected (one fixed jpeg object per user)',
  format($q$select public.set_my_avatar(%L)$q$, gwm_test.uid(40)::text || '/me.png'), 'GWM_AVATAR_INVALID');
select gwm_test.expect_error('D1 direct column update with a bad path rejected by the trigger too',
  format($q$update public.profiles set avatar_path = %L where id = %L$q$, gwm_test.uid(40)::text || '/x.jpg', gwm_test.uid(40)), 'GWM_AVATAR_INVALID');
select gwm_test.expect_ok('D2 set own avatar path', format($q$select public.set_my_avatar(%L)$q$, gwm_test.uid(40)::text || '/avatar.jpg'));
select gwm_test.reset();
select gwm_test.chk('D2 avatar_path stored', (select avatar_path = gwm_test.uid(40)::text || '/avatar.jpg' from public.profiles where id = gwm_test.uid(40)));

-- visibility: nobody but a currently matched partner
select gwm_test.as_user(gwm_test.uid(42));
select gwm_test.chk('D3 stranger cannot view', not public.can_view_avatar(gwm_test.uid(40)));
select gwm_test.as_user(gwm_test.uid(41));
select gwm_test.chk('D3 driver with NO match yet cannot view', not public.can_view_avatar(gwm_test.uid(40)));
select gwm_test.as_user(gwm_test.uid(43));
select gwm_test.expect_ok('D3 Rider 43 requests Driver 41', $q$select public.request_match(gwm_test.tid(43), gwm_test.tid(41))$q$);
select gwm_test.as_user(gwm_test.uid(40));
select gwm_test.expect_ok('D3 Rider 40 requests Driver 41', $q$select public.request_match(gwm_test.tid(40), gwm_test.tid(41))$q$);
select gwm_test.as_user(gwm_test.uid(41));
select gwm_test.chk('D3 PENDING request does not reveal the photo (search / pending / declined never do)', not public.can_view_avatar(gwm_test.uid(40)));
select gwm_test.expect_ok('D3 Driver 41 accepts Rider 40', format($q$select public.respond_match(%L, true)$q$, gwm_test.mid(40, 41)));
select gwm_test.reset();
select gwm_test.as_user(gwm_test.uid(41));
select gwm_test.chk('D4 accepted pair: Driver can view Rider photo', public.can_view_avatar(gwm_test.uid(40)));
select gwm_test.chk('D4 get_partner_avatar_path returns the path', public.get_partner_avatar_path(gwm_test.mid(40, 41)) = gwm_test.uid(40)::text || '/avatar.jpg');
select gwm_test.as_user(gwm_test.uid(42));
select gwm_test.chk('D4 stranger still cannot view / gets NULL for that match', not public.can_view_avatar(gwm_test.uid(40)) and public.get_partner_avatar_path(gwm_test.mid(40, 41)) is null);
select gwm_test.as_user(gwm_test.uid(43));
select gwm_test.chk('D4 the auto-closed pending Rider 43 cannot view', not public.can_view_avatar(gwm_test.uid(40)));
select gwm_test.reset();

-- storage policies (when the storage schema exists)
do $$
begin
  if to_regclass('storage.buckets') is null then
    perform gwm_test.chk('D5 storage policies (skipped: no storage schema)', true, 'skipped');
    return;
  end if;
  perform gwm_test.chk('D5 bucket avatars: private, 512 KB, image/jpeg only',
    (select not public and file_size_limit = 524288 and allowed_mime_types = array['image/jpeg'] from storage.buckets where id = 'avatars'));
  perform gwm_test.chk('D5 four avatar policies present',
    (select count(*) = 4 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname like 'avatars\_%'));
  -- reads (as the partner / a stranger)
  perform gwm_test.as_user(gwm_test.uid(41));
  perform gwm_test.chk('D5 partner can read the object row', (select count(*) = 1 from storage.objects where bucket_id = 'avatars' and name = gwm_test.uid(40)::text || '/avatar.jpg'));
  perform gwm_test.as_user(gwm_test.uid(42));
  perform gwm_test.chk('D5 stranger cannot read it', (select count(*) = 0 from storage.objects where bucket_id = 'avatars' and name = gwm_test.uid(40)::text || '/avatar.jpg'));
  -- writes
  perform gwm_test.as_user(gwm_test.uid(42));
  perform gwm_test.expect_error('D5 cannot write into another user''s folder',
    format($q$insert into storage.objects (bucket_id, name, owner) values ('avatars', %L, %L)$q$, gwm_test.uid(40)::text || '/avatar.jpg', gwm_test.uid(42)), 'row-level security');
  perform gwm_test.expect_error('D5 cannot write a differently named object even in the own folder',
    format($q$insert into storage.objects (bucket_id, name, owner) values ('avatars', %L, %L)$q$, gwm_test.uid(42)::text || '/other.png', gwm_test.uid(42)), 'row-level security');
  perform gwm_test.expect_ok('D5 can write the fixed own object',
    format($q$insert into storage.objects (bucket_id, name, owner, metadata) values ('avatars', %L, %L, '{"size":1000}'::jsonb)$q$, gwm_test.uid(42)::text || '/avatar.jpg', gwm_test.uid(42)));
  perform gwm_test.expect_error('D5 size term of the write policy: > 512 KB refused when metadata carries the size',
    format($q$update storage.objects set metadata = '{"size":600000}'::jsonb where bucket_id = 'avatars' and name = %L$q$, gwm_test.uid(42)::text || '/avatar.jpg'), 'row-level security');
  perform gwm_test.reset();
end $$;

-- report: hides the photo from the reporter immediately, keeps it for others; stranger cannot report
select gwm_test.as_user(gwm_test.uid(42));
select gwm_test.expect_error('D6 stranger cannot report a photo it cannot see', format($q$select public.report_avatar(%L, 'harassment')$q$, gwm_test.mid(40, 41)), 'GWM_REPORT_INVALID');
select gwm_test.as_user(gwm_test.uid(41));
select gwm_test.expect_ok('D6 partner reports the photo', format($q$select public.report_avatar(%L, 'fake_profile')$q$, gwm_test.mid(40, 41)));
select gwm_test.expect_ok('D6 reporting twice is idempotent', format($q$select public.report_avatar(%L, 'fake_profile')$q$, gwm_test.mid(40, 41)));
select gwm_test.chk('D6 photo hidden from the reporter at once (initials fallback)',
  not public.can_view_avatar(gwm_test.uid(40)) and public.get_partner_avatar_path(gwm_test.mid(40, 41)) is null);
select gwm_test.chk('D6 reporter can read own report, exactly one row', gwm_test.n($q$select count(*) from public.content_reports$q$) = 1);
select gwm_test.as_user(gwm_test.uid(40));
select gwm_test.chk('D6 the reported user sees NO report row (reporter stays anonymous)', gwm_test.n($q$select count(*) from public.content_reports$q$) = 0);
select gwm_test.reset();

-- moderator removal / purge queue
select gwm_test.as_user(gwm_test.uid(41));
select gwm_test.expect_error('D7 non-admin cannot remove photos', format($q$select public.admin_remove_avatar(%L)$q$, gwm_test.uid(40)), 'GWM_FORBIDDEN');
select gwm_test.as_admin(gwm_test.uid(80));
select gwm_test.expect_ok('D7 admin removes the photo', format($q$select public.admin_remove_avatar(%L)$q$, gwm_test.uid(40)));
select gwm_test.reset();
select gwm_test.chk('D7 profile cleared, purge queue row created, report closed as upheld',
  (select avatar_path is null from public.profiles where id = gwm_test.uid(40))
  and (select count(*) = 1 from public.storage_purge_queue where bucket = 'avatars' and path = gwm_test.uid(40)::text || '/avatar.jpg')
  and (select status = 'upheld' from public.content_reports where kind = 'avatar' and reported_user_id = gwm_test.uid(40)));
select gwm_test.chk('D7 claim_storage_purge hands the row to the (service) job', (select count(*) = 1 from public.claim_storage_purge(10)));
select gwm_test.chk('D7 a claimed row is not handed out again', (select count(*) = 0 from public.claim_storage_purge(10)));
select gwm_test.chk('D7 complete_storage_purge removes it', public.complete_storage_purge((select array_agg(id) from public.storage_purge_queue)) = 1);
select gwm_test.chk('D7 queue empty', (select count(*) = 0 from public.storage_purge_queue));
-- re-upload after removal must not be purged later: a queue row whose path is referenced again is dropped, never claimed
insert into public.storage_purge_queue (bucket, path, reason) values ('avatars', gwm_test.uid(40)::text || '/avatar.jpg', 'moderation');
select gwm_test.as_user(gwm_test.uid(40));
select gwm_test.expect_ok('D8 owner sets the avatar again', format($q$select public.set_my_avatar(%L)$q$, gwm_test.uid(40)::text || '/avatar.jpg'));
select gwm_test.reset();
select gwm_test.chk('D8 stale purge row for a path that is referenced again is not claimed', (select count(*) = 0 from public.claim_storage_purge(10)));
-- owner removes the photo: queue row; account deletion: same
select gwm_test.as_user(gwm_test.uid(40));
select gwm_test.expect_ok('D9 owner clears the avatar', $q$select public.set_my_avatar(null)$q$);
select gwm_test.expect_ok('D9 owner sets it a third time', format($q$select public.set_my_avatar(%L)$q$, gwm_test.uid(40)::text || '/avatar.jpg'));
select gwm_test.expect_ok('D9 account deletion by the owner', $q$select public.request_account_deletion()$q$);
select gwm_test.reset();
select gwm_test.chk('D9 deletion: avatar_path cleared and the file is queued for deletion',
  (select avatar_path is null from public.profiles where id = gwm_test.uid(40))
  and (select count(*) >= 1 from public.storage_purge_queue where path = gwm_test.uid(40)::text || '/avatar.jpg'));
select gwm_test.chk('D9 deletion: avatar reports about the user are deleted', (select count(*) = 0 from public.content_reports where kind = 'avatar' and reported_user_id = gwm_test.uid(40)));

-- =============================================================================
-- E. US-26 reviews (fixtures: finished rides on separate lines, matches accepted + boarded)
-- =============================================================================
select gwm_test.chk('E0 tag allow-list per reviewee role (driver has vehicle_matches, rider has not)',
  (select count(*) = 1 from public.review_tags where reviewee_role = 'driver' and tag = 'vehicle_matches')
  and (select count(*) = 0 from public.review_tags where reviewee_role = 'rider' and tag = 'vehicle_matches'));
select gwm_test.chk('E0 clients cannot read/write the tables directly (RPC only)',
  not has_table_privilege('authenticated', 'public.reviews', 'select') and not has_table_privilege('authenticated', 'public.reviews', 'insert')
  and not has_table_privilege('authenticated', 'public.review_aggregates', 'select') and not has_table_privilege('anon', 'public.reviews', 'select'));

-- P1..P3: driver 60 with three finished rides (riders 61, 62, 63) at lat 17.20 / 17.21 / 17.22
select gwm_test.done_pair(60, 601, 61, 61, 17.20);
select gwm_test.done_pair(60, 602, 62, 62, 17.21);
select gwm_test.done_pair(60, 603, 63, 63, 17.22);
-- P4: blind pair; P5: timeout pair; P6 (68/69): not boarded; P7 (71/72): boarded but trips still in progress
select gwm_test.done_pair(64, 64, 65, 65, 17.30);
select gwm_test.done_pair(66, 66, 67, 67, 17.31);
select gwm_test.done_pair(68, 68, 69, 69, 17.32, false, false);
select gwm_test.done_pair(71, 71, 72, 72, 17.33, true, false);

select gwm_test.as_user(gwm_test.uid(69));
select gwm_test.expect_error('E1 not boarded / trip not completed -> not eligible (backend, direct RPC)', format($q$select public.submit_review(%L, 5)$q$, gwm_test.mid(68, 69)), 'GWM_REVIEW_NOT_ELIGIBLE');
select gwm_test.chk('E1 state says not_boarded', (select reason = 'not_boarded' and not can_review from public.get_my_review_state(gwm_test.mid(68, 69))));
select gwm_test.as_user(gwm_test.uid(72));
select gwm_test.expect_error('E1 boarded but own trip not completed -> not eligible', format($q$select public.submit_review(%L, 5)$q$, gwm_test.mid(71, 72)), 'GWM_REVIEW_NOT_ELIGIBLE');
select gwm_test.as_user(gwm_test.uid(62));
select gwm_test.expect_error('E1 a non-party cannot review someone else''s ride', format($q$select public.submit_review(%L, 5)$q$, gwm_test.mid(64, 65)), 'GWM_REVIEW_NOT_ELIGIBLE');

-- input validation (as rider 61 on P1)
select gwm_test.as_user(gwm_test.uid(61));
select gwm_test.expect_error('E2 stars 0 rejected', format($q$select public.submit_review(%L, 0)$q$, gwm_test.mid(601, 61)), 'GWM_REVIEW_INVALID');
select gwm_test.expect_error('E2 stars 6 rejected', format($q$select public.submit_review(%L, 6)$q$, gwm_test.mid(601, 61)), 'GWM_REVIEW_INVALID');
select gwm_test.expect_error('E2 tag outside the allow-list rejected', format($q$select public.submit_review(%L, 5, array['nice_hat'])$q$, gwm_test.mid(601, 61)), 'GWM_REVIEW_INVALID');
select gwm_test.expect_error('E2 duplicate tag rejected', format($q$select public.submit_review(%L, 5, array['on_time','on_time'])$q$, gwm_test.mid(601, 61)), 'GWM_REVIEW_INVALID');
select gwm_test.expect_error('E2 comment > 200 chars rejected', format($q$select public.submit_review(%L, 5, '{}', %L)$q$, gwm_test.mid(601, 61), repeat('ก', 201)), 'GWM_REVIEW_INVALID');
select gwm_test.chk('E2 nothing was stored by the failed calls', gwm_test.n($q$select count(*) from public.get_my_review_state(gwm_test.mid(601, 61)) where my_stars is not null$q$) = 0);

-- P1 both directions => reveal
select gwm_test.expect_ok('E3 Rider 61 reviews Driver 60 (5 stars, tags, comment)',
  format($q$select public.submit_review(%L, 5, array['on_time','safe_driving'], 'ขับดีมาก')$q$, gwm_test.mid(601, 61)));
select gwm_test.expect_error('E3 second review in the same direction rejected (one per match per direction)', format($q$select public.submit_review(%L, 4)$q$, gwm_test.mid(601, 61)), 'GWM_REVIEW_DUPLICATE');
select gwm_test.chk('E3 own review readable by its author only via state; other side unknown (blind)',
  (select my_stars = 5 and my_comment = 'ขับดีมาก' and not can_review and reason = 'already_submitted' from public.get_my_review_state(gwm_test.mid(601, 61))));
select gwm_test.chk('E3 BLIND: the reviewer sees nothing received yet', (select count(*) = 0 from public.get_reviews_received()));
select gwm_test.as_user(gwm_test.uid(60));
select gwm_test.chk('E3 BLIND: driver 60 cannot see the Rider''s review before submitting his own', (select count(*) = 0 from public.get_reviews_received()));
select gwm_test.chk('E3 BLIND: driver state does not disclose that the Rider already submitted',
  (select can_review and my_stars is null and reason is null from public.get_my_review_state(gwm_test.mid(601, 61))));
select gwm_test.expect_error('E3 tag safe_driving is not valid for the REVIEWEE role rider', format($q$select public.submit_review(%L, 4, array['safe_driving'])$q$, gwm_test.mid(601, 61)), 'GWM_REVIEW_INVALID');
select gwm_test.expect_ok('E3 Driver 60 reviews Rider 61 (4 stars)', format($q$select public.submit_review(%L, 4, array['polite'])$q$, gwm_test.mid(601, 61)));
select gwm_test.chk('E3 reveal: both directions in => each side now sees the review about itself, comment included, no reviewer id',
  (select count(*) = 1 and bool_and(stars = 5) and bool_and(comment = 'ขับดีมาก') from public.get_reviews_received())
  and pg_get_function_result('public.get_reviews_received(int)'::regprocedure) !~* 'reviewer');
select gwm_test.as_user(gwm_test.uid(61));
select gwm_test.chk('E3 reveal: the rider now sees the driver''s review of him', (select count(*) = 1 and bool_and(stars = 4) from public.get_reviews_received()));
select gwm_test.as_user(gwm_test.uid(63));
select gwm_test.chk('E3 a third person sees nothing', (select count(*) = 0 from public.get_reviews_received()));
select gwm_test.expect_error('E3 direct table read denied', $q$select count(*) from public.reviews$q$, 'permission denied');
select gwm_test.reset();
select gwm_test.chk('E3 revealed_at stamped on both rows', (select count(*) = 2 and bool_and(revealed_at is not null) from public.reviews where match_id = gwm_test.mid(601, 61)));

-- P2, P3 (both directions each)
select gwm_test.as_user(gwm_test.uid(62)); select gwm_test.expect_ok('E4 P2 rider->driver 4', format($q$select public.submit_review(%L, 4)$q$, gwm_test.mid(602, 62)));
select gwm_test.as_user(gwm_test.uid(60)); select gwm_test.expect_ok('E4 P2 driver->rider 3', format($q$select public.submit_review(%L, 3)$q$, gwm_test.mid(602, 62)));
select gwm_test.as_user(gwm_test.uid(60));
select gwm_test.chk('E4 aggregate: only 2 revealed reviews -> "not enough", no average, no count',
  (select bool_and(not enough) and bool_and(avg_stars is null) and bool_and(review_count is null) and count(*) = 2 from public.get_user_rating(gwm_test.uid(60))));
select gwm_test.as_user(gwm_test.uid(63)); select gwm_test.expect_ok('E4 P3 rider->driver 3', format($q$select public.submit_review(%L, 3)$q$, gwm_test.mid(603, 63)));
select gwm_test.as_user(gwm_test.uid(60));
select gwm_test.chk('E4 aggregate still "not enough": the 3rd review is blind (driver has not reviewed yet)',
  (select not enough from public.get_user_rating(gwm_test.uid(60)) where role = 'driver'));
select gwm_test.expect_ok('E4 P3 driver->rider 5', format($q$select public.submit_review(%L, 5)$q$, gwm_test.mid(603, 63)));
select gwm_test.chk('E4 aggregate with 3 revealed reviews: enough, avg 4.0 (5,4,3), count 3, per role',
  (select enough and avg_stars = 4.0 and review_count = 3 from public.get_user_rating(gwm_test.uid(60)) where role = 'driver')
  and (select not enough from public.get_user_rating(gwm_test.uid(60)) where role = 'rider'));
select gwm_test.as_user(gwm_test.uid(42));
select gwm_test.reset();
select gwm_test.setcfg('review.show_in_search', 'false');
select gwm_test.as_user(gwm_test.uid(42));
select gwm_test.expect_error('E4 unrelated user cannot read the rating (review.show_in_search = false)', format($q$select * from public.get_user_rating(%L)$q$, gwm_test.uid(60)), 'GWM_FORBIDDEN');
select gwm_test.reset();
select gwm_test.setcfg('review.show_in_search', 'true');
select gwm_test.as_user(gwm_test.uid(42));
select gwm_test.chk('E4 with review.show_in_search = true a user with a scheduled trip (30) is readable: 2 rows, not enough',
  (select count(*) = 2 and bool_and(not enough) from public.get_user_rating(gwm_test.uid(30))));
select gwm_test.reset();
select gwm_test.setcfg('review.show_in_search', 'false');

-- P4 blind pair: one side only
select gwm_test.as_user(gwm_test.uid(65)); select gwm_test.expect_ok('E5 P4 rider->driver 2 with comment', format($q$select public.submit_review(%L, 2, array['late'], 'มาช้า')$q$, gwm_test.mid(64, 65)));
select gwm_test.as_user(gwm_test.uid(64));
select gwm_test.chk('E5 driver 64 sees nothing (blind, other side not in, < 7 days)', (select count(*) = 0 from public.get_reviews_received()));
select gwm_test.reset();

-- P5 timeout: 7 days after the first completed trip the review is revealed without the other side, and the window closes
select gwm_test.as_user(gwm_test.uid(67)); select gwm_test.expect_ok('E6 P5 rider->driver 1 star', format($q$select public.submit_review(%L, 1)$q$, gwm_test.mid(66, 67)));
select gwm_test.reset();
update public.trips set ended_at = now() - interval '8 days' where id in (gwm_test.tid(66), gwm_test.tid(67));
update public.reviews set reveal_at = now() - interval '1 day' where match_id = gwm_test.mid(66, 67);
select gwm_test.as_user(gwm_test.uid(66));
select gwm_test.chk('E6 after 7 days the review is revealed although the driver never reviewed', (select count(*) = 1 and bool_and(stars = 1) from public.get_reviews_received()));
select gwm_test.expect_error('E6 window closed: driver 66 can no longer review', format($q$select public.submit_review(%L, 3)$q$, gwm_test.mid(66, 67)), 'GWM_REVIEW_WINDOW_CLOSED');
select gwm_test.reset();
select gwm_test.chk('E6 _reveal_due_reviews (cron via purge_expired_data) returns the number stamped', public._reveal_due_reviews() >= 1);
select gwm_test.chk('E6 ... and revealed_at is stamped', (select revealed_at is not null from public.reviews where match_id = gwm_test.mid(66, 67)));

-- report / hold / moderator
select gwm_test.as_user(gwm_test.uid(60));
select gwm_test.chk('E7 driver 60 has 3 received reviews', (select count(*) = 3 from public.get_reviews_received()));
select gwm_test.expect_error('E7 only the reviewee can report (unknown/other review id)', format($q$select public.report_review(%L, 'harassment')$q$, gen_random_uuid()), 'GWM_REPORT_INVALID');
select gwm_test.expect_ok('E7 driver 60 reports the 5-star comment review',
  format($q$select public.report_review(%L, 'harassment')$q$, (select review_id from public.get_reviews_received() where stars = 5)));
select gwm_test.chk('E7 reported review hidden from the reviewee and not counted (2 left => "not enough")',
  (select count(*) = 2 from public.get_reviews_received())
  and (select not enough from public.get_user_rating(gwm_test.uid(60)) where role = 'driver'));
select gwm_test.reset();
create table if not exists gwm_test.kv (k text primary key, v text);
grant all on gwm_test.kv to public;
insert into gwm_test.kv select 'rev61', id::text from public.reviews where match_id = gwm_test.mid(601, 61) and role = 'driver';
select gwm_test.as_user(gwm_test.uid(61));
select gwm_test.expect_error('E7 the reviewer (not the reviewee) cannot report it', format($q$select public.report_review(%L, 'spam')$q$, (select v::uuid from gwm_test.kv where k = 'rev61')), 'GWM_REPORT_INVALID');
select gwm_test.as_admin(gwm_test.uid(80));
select gwm_test.expect_ok('E7 moderator dismisses the report -> review counted again',
  format($q$select public.admin_resolve_review_report(%L, false)$q$, (select id from public.content_reports where kind = 'review' and status = 'open')));
select gwm_test.as_user(gwm_test.uid(60));
select gwm_test.chk('E7 back to 3 received / enough again', (select count(*) = 3 from public.get_reviews_received())
  and (select enough and review_count = 3 from public.get_user_rating(gwm_test.uid(60)) where role = 'driver'));
select gwm_test.expect_ok('E7 report again', format($q$select public.report_review(%L, 'harassment')$q$, (select review_id from public.get_reviews_received() where stars = 5)));
select gwm_test.as_admin(gwm_test.uid(80));
select gwm_test.expect_ok('E7 moderator upholds -> removed', format($q$select public.admin_resolve_review_report(%L, true)$q$, (select id from public.content_reports where kind = 'review' and status = 'open')));
select gwm_test.reset();
select gwm_test.chk('E7 removed review stays out of the aggregate', (select removed_at is not null from public.reviews where match_id = gwm_test.mid(601, 61) and role = 'driver'));

-- account deletion of a reviewer / reviewee
select gwm_test.as_user(gwm_test.uid(61));
select gwm_test.expect_ok('E8 rider 61 deletes the account', $q$select public.request_account_deletion()$q$);
select gwm_test.reset();
select gwm_test.chk('E8 reviews ABOUT 61 deleted; reviews BY 61 lost comment and author link (stars/tags stay anonymous)',
  (select count(*) = 0 from public.reviews where reviewee_id = gwm_test.uid(61))
  and (select count(*) = 1 and bool_and(comment is null) and bool_and(reviewer_id is null) from public.reviews where match_id = gwm_test.mid(601, 61) and role = 'driver'));
select gwm_test.chk('E8 export_my_data carries the review sections', (select public.export_my_data() is not null));
select gwm_test.as_user(gwm_test.uid(65));
select gwm_test.chk('E8 export_my_data (user 65) lists the review written', (select jsonb_array_length(public.export_my_data() -> 'reviews_written') = 1));
select gwm_test.reset();

-- =============================================================================
-- F. grants
-- =============================================================================
select gwm_test.chk('F1 authenticated may call the new RPCs; anon may not',
  has_function_privilege('authenticated', 'public.submit_review(uuid,integer,text[],text)', 'execute')
  and has_function_privilege('authenticated', 'public.get_match_hint(uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.set_my_avatar(text)', 'execute')
  and has_function_privilege('authenticated', 'public.get_partner_avatar_path(uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.get_user_rating(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.submit_review(uuid,integer,text[],text)', 'execute')
  and not has_function_privilege('anon', 'public.get_match_hint(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.get_partner_avatar_path(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.find_matches(uuid,integer)', 'execute'));
select gwm_test.chk('F2 internals are not callable by clients',
  not has_function_privilege('authenticated', 'public._car_corridor_eval(geography,geography,geography,geography)', 'execute')
  and not has_function_privilege('authenticated', 'public._car_rule_eval(geography,geography,geography,integer,integer,geography,geography,geography)', 'execute')
  and not has_function_privilege('authenticated', 'public._car_dropoff_limit(integer)', 'execute')
  and not has_function_privilege('authenticated', 'public.trips_max_dropoff_guard()', 'execute')
  and not has_function_privilege('authenticated', 'public.match_candidates(uuid,integer,uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public._accept_match(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public._review_check(uuid,uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public._reveal_due_reviews()', 'execute')
  and not has_function_privilege('authenticated', 'public.claim_storage_purge(integer)', 'execute')
  and not has_function_privilege('authenticated', 'public.complete_storage_purge(uuid[])', 'execute')
  and not has_function_privilege('authenticated', 'public.purge_expired_data()', 'execute')
  and not has_function_privilege('authenticated', 'public.profiles_avatar_guard()', 'execute')
  and not has_table_privilege('authenticated', 'public.storage_purge_queue', 'select'));
select gwm_test.chk('F3 review_tags readable by authenticated (client renders the chips)', has_table_privilege('authenticated', 'public.review_tags', 'select'));

-- ---- report ---------------------------------------------------------------------------------------
select gwm_test.reset();
select n, case when ok then 'PASS' else 'FAIL' end as result, label, detail from gwm_test.results order by n;
select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed from gwm_test.results;
do $$
begin
  if exists (select 1 from gwm_test.results where not ok) then
    raise exception 'Round 5 (0009) SQL tests FAILED: % check(s)', (select count(*) from gwm_test.results where not ok);
  end if;
end $$;
rollback;
