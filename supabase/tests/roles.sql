-- =============================================================================
-- GOWITHME automated SQL tests for migration 0006 (Driver/Rider roles, US-16..18, R3-1..R3-4; docs/design-roles.md).
-- Run after migrations 0001-0006 (as the postgres superuser role):
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f supabase/tests/roles.sql
-- One transaction, ROLLED BACK at the end. Same harness as qa_round1.sql. Khon Kaen coordinates on one west->east line.
-- Includes PM decisions Q-1 (driver cannot cancel after boarded), Q-2 (boarded rider keeps vehicle view), Q-8 (expiry), 12-month match_outcomes purge.
-- Prints PASS/FAIL rows and exits non-zero on any FAIL. A concurrent race cannot be reproduced inside one transaction:
-- it is covered by (a) the simulated race loser (C6) and (b) the partial unique indexes (C5).
-- =============================================================================
\set ON_ERROR_STOP on
begin;
set search_path = public, extensions;

-- ---- harness ------------------------------------------------------------------------------------
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

-- valid signup (what the Flutter client sends); p_meta is merged over the defaults
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

-- scheduled trip for user p_n; depart_at = now() + p_dep (inserted valid, then moved as system so the past can be tested)
create function gwm_test.trip(p_n int, olng float8, olat float8, dlng float8, dlat float8, p_dep interval default interval '1 hour')
returns void language plpgsql as $$
begin
  insert into public.trips (id, user_id, mode, origin, dest, route, route_distance_m, route_duration_s, depart_at)
  values (gwm_test.tid(p_n), gwm_test.uid(p_n), 'walk',
          ST_SetSRID(ST_MakePoint(olng, olat), 4326)::geography, ST_SetSRID(ST_MakePoint(dlng, dlat), 4326)::geography,
          ST_MakeLine(ST_SetSRID(ST_MakePoint(olng, olat), 4326), ST_SetSRID(ST_MakePoint(dlng, dlat), 4326))::geography,
          3000, 1800, now() + interval '1 hour');
  update public.trips set depart_at = now() + p_dep where id = gwm_test.tid(p_n);
end $$;

create function gwm_test.cand_count(p_req int, p_cand int) returns bigint language sql as
$$ select count(*) from public.match_candidates(gwm_test.tid(p_req)) where candidate_trip_id = gwm_test.tid(p_cand) $$;


-- ---- role-specific helpers ---------------------------------------------------------------------
create table gwm_test.tokens (n int primary key, tok text);
grant all on gwm_test.tokens to public;

-- vehicle inserted directly (superuser); share switch stays OFF (NULL) like a fresh Driver
-- (0008: a driver is a REGISTERED driver; the fixture also sets the 3 server-owned registration columns when 0008 is present)
create function gwm_test.veh(p_n int) returns void language plpgsql as $$
begin
  insert into public.vehicles (user_id, plate, model, color) values (gwm_test.uid(p_n), 'กข 1234', 'Toyota Vios', 'ขาว')
  on conflict do nothing;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'profiles' and column_name = 'driver_registered_at') then
    execute format('update public.profiles set driver_registered_at = now(), licence_declared_at = now(), licence_declaration_version = %L where id = %L',
                   'd1-draft', gwm_test.uid(p_n));
  end if;
end $$;

-- car trip on the straight west->east line at lat 16.43 (origin 102.8300). Driver gets a vehicle first (trip guard requires it).
create function gwm_test.ctrip(p_n int, p_role public.trip_role, p_dlng float8 default 102.8534, p_dep interval default interval '1 hour')
returns void language plpgsql as $$
begin
  if p_role = 'driver' then perform gwm_test.veh(p_n); end if;
  insert into public.trips (id, user_id, mode, role, origin, dest, route, route_distance_m, route_duration_s, depart_at)
  values (gwm_test.tid(p_n), gwm_test.uid(p_n), 'car', p_role,
          ST_SetSRID(ST_MakePoint(102.8300, 16.4300), 4326)::geography, ST_SetSRID(ST_MakePoint(p_dlng, 16.4300), 4326)::geography,
          ST_MakeLine(ST_SetSRID(ST_MakePoint(102.8300, 16.4300), 4326), ST_SetSRID(ST_MakePoint(p_dlng, 16.4300), 4326))::geography,
          2500, 600, now() + interval '1 hour');
  update public.trips set depart_at = now() + p_dep where id = gwm_test.tid(p_n);
end $$;

create function gwm_test.raw_trip(p_n int, p_mode text, p_role text) returns void language plpgsql as $$
begin
  insert into public.trips (id, user_id, mode, role, origin, dest, route, route_distance_m, route_duration_s, depart_at)
  values (gwm_test.tid(p_n), gwm_test.uid(p_n), p_mode::public.travel_mode, p_role::public.trip_role,
          ST_SetSRID(ST_MakePoint(102.8300, 16.4300), 4326)::geography, ST_SetSRID(ST_MakePoint(102.8534, 16.4300), 4326)::geography,
          ST_MakeLine(ST_SetSRID(ST_MakePoint(102.8300, 16.4300), 4326), ST_SetSRID(ST_MakePoint(102.8534, 16.4300), 4326))::geography,
          2500, 600, now() + interval '1 hour');
end $$;

create function gwm_test.mid(a int, b int) returns uuid language sql as $$
  select id from public.matches
   where least(requester_trip_id, target_trip_id) = least(gwm_test.tid(a), gwm_test.tid(b))
     and greatest(requester_trip_id, target_trip_id) = greatest(gwm_test.tid(a), gwm_test.tid(b)) $$;
create function gwm_test.mstat(a int, b int) returns text language sql as $$
  select status::text from public.matches where id = gwm_test.mid(a, b) $$;
create function gwm_test.propose_n(p_m uuid, p_n int) returns void language plpgsql as $$
begin
  for i in 1 .. p_n loop
    perform public.propose_meeting_point(p_m, 102.8350 + i * 0.0001, 16.4300, 'p' || i);
  end loop;
end $$;
create function gwm_test.msgs(p_m uuid, p_body text) returns bigint language sql as $$
  select count(*) from public.chat_messages where match_id = p_m and body = p_body $$;
create function gwm_test.trip_state(p_n int, p_status text) returns void language plpgsql as $$
begin
  update public.trips set status = p_status::public.trip_status where id = gwm_test.tid(p_n);
end $$;
-- both trips of a pair: request (rider or driver side) + accept by the other side
create function gwm_test.pair_accept(p_req int, p_tgt int) returns void language plpgsql as $$
begin
  perform gwm_test.as_user(gwm_test.uid(p_req));
  perform public.request_match(gwm_test.tid(p_req), gwm_test.tid(p_tgt));
  perform gwm_test.reset();
  perform gwm_test.as_user(gwm_test.uid(p_tgt));
  perform public.respond_match(gwm_test.mid(p_req, p_tgt), true);
  perform gwm_test.reset();
end $$;

-- ---- users ------------------------------------------------------------------------------------
select gwm_test.signup(n) from generate_series(1, 13) n;
select gwm_test.signup(n) from generate_series(20, 33) n;
select gwm_test.signup(40); select gwm_test.signup(41);

-- =============================================================================
-- A. trips.role rules, vehicle table/RPC, consent switch, constants
-- =============================================================================
select gwm_test.chk('A0 enum trip_role = driver|rider', (select array_agg(e.enumlabel::text order by e.enumsortorder) = array['driver','rider']
  from pg_enum e join pg_type t on t.oid = e.enumtypid where t.typname = 'trip_role'));
select gwm_test.chk('A0 no seat column anywhere (seats fixed = 1)',
  gwm_test.n($q$select count(*) from information_schema.columns where table_schema = 'public' and column_name ilike '%seat%'$q$) = 0);
select gwm_test.chk('A0 car_seats() = 1', public.car_seats() = 1);
select gwm_test.chk('A0 config match.pickup_max_deviation_m = 500 and public', public.cfg_num('match.pickup_max_deviation_m') = 500
  and (select is_public from public.app_config where key = 'match.pickup_max_deviation_m'));

select gwm_test.expect_error('A1 car trip without role rejected', $q$select gwm_test.raw_trip(40, 'car', null)$q$, 'GWM_ROLE_REQUIRED');
select gwm_test.expect_error('A1 walk trip with role rejected', $q$select gwm_test.raw_trip(40, 'walk', 'driver')$q$, 'GWM_ROLE_NOT_ALLOWED');
select gwm_test.expect_error('A1 driver trip without registration rejected (0008: registration is checked before the vehicle)', $q$select gwm_test.raw_trip(40, 'car', 'driver')$q$, 'GWM_NOT_A_DRIVER');

select gwm_test.as_user(gwm_test.uid(40));
select gwm_test.expect_error('A2 empty plate invalid', $q$select public.upsert_my_vehicle('', 'Toyota', 'ขาว')$q$, 'GWM_VEHICLE_INVALID');
select gwm_test.expect_error('A2 control char in plate invalid', $q$select public.upsert_my_vehicle('AB' || chr(7), 'Toyota', 'ขาว')$q$, 'GWM_VEHICLE_INVALID');
select gwm_test.expect_error('A2 model > 60 chars invalid', $q$select public.upsert_my_vehicle('กข 1234', repeat('a', 61), 'ขาว')$q$, 'GWM_VEHICLE_INVALID');
select gwm_test.expect_error('A2 no direct INSERT on vehicles', $q$insert into public.vehicles (user_id, plate, model, color) values (gwm_test.uid(40), 'x', 'y', 'z')$q$, 'permission denied');
select gwm_test.expect_error('A2 consent switch needs a registered driver (0008)', $q$select public.set_vehicle_share_consent(true)$q$, 'GWM_NOT_A_DRIVER');
select gwm_test.expect_ok('A2 upsert vehicle (whitespace normalised)', $q$select public.upsert_my_vehicle('  กข   1234 ', 'Toyota Vios', 'ขาว')$q$);
select gwm_test.reset();
select gwm_test.chk('A2 plate normalised, share switch defaults OFF',
  (select plate = 'กข 1234' and share_consent_at is null from public.vehicles where user_id = gwm_test.uid(40)));

select gwm_test.veh(40);   -- 0008: register the driver (vehicle exists from A2)
select gwm_test.raw_trip(40, 'car', 'driver');
select gwm_test.raw_trip(41, 'car', 'rider');
select gwm_test.chk('A3 driver trip (with vehicle) and rider trip (no vehicle) accepted',
  gwm_test.n($q$select count(*) from public.trips where id in (gwm_test.tid(40), gwm_test.tid(41)) and mode = 'car' and role is not null$q$) = 2);

select gwm_test.as_user(gwm_test.uid(40));
select gwm_test.expect_error('A4 role column not updatable by client', $q$update public.trips set role = 'rider' where id = gwm_test.tid(40)$q$, 'permission denied');
select gwm_test.expect_error('A4 mode cannot leave car', $q$update public.trips set mode = 'walk' where id = gwm_test.tid(40)$q$, 'GWM_ROLE_IMMUTABLE');
select gwm_test.expect_error('A4 vehicle cannot be deleted while a driver trip is active', $q$select public.delete_my_vehicle()$q$, 'GWM_VEHICLE_IN_USE');
select gwm_test.chk('A5 set consent ON returns server time', (select public.set_vehicle_share_consent(true)) is not null);
select gwm_test.chk('A5 set consent OFF returns NULL', (select public.set_vehicle_share_consent(false)) is null);
select gwm_test.chk('A5 export_my_data carries the vehicle', jsonb_typeof(public.export_my_data() -> 'vehicle') = 'object');
select gwm_test.expect_ok('A4 cancel own trip', $q$update public.trips set status = 'cancelled' where id = gwm_test.tid(40)$q$);
select gwm_test.expect_ok('A4 unregister first (0008: a registered driver cannot delete the vehicle)', $q$select public.unregister_driver()$q$);
select gwm_test.expect_ok('A4 vehicle deletable once trip is over', $q$select public.delete_my_vehicle()$q$);
select gwm_test.expect_ok('A4 delete is idempotent', $q$select public.delete_my_vehicle()$q$);
select gwm_test.reset();

-- =============================================================================
-- B. match_candidates: Driver<->Rider only, rider-route overlap, legacy, non-car unchanged
-- =============================================================================
select gwm_test.ctrip(1, 'driver');  select gwm_test.ctrip(2, 'driver');
select gwm_test.ctrip(3, 'rider');   select gwm_test.ctrip(4, 'rider');
select gwm_test.ctrip(5, 'rider');   select gwm_test.ctrip(13, 'rider');
select gwm_test.ctrip(10, 'driver', 102.8340);                 -- short driver route: 0.43 km; rider destination 2.07 km beyond the driver's (0009: driver limit 2000 m default => excluded; 0006 excluded it by overlap 40)
select gwm_test.trip(6, 102.8300, 16.4300, 102.8534, 16.4300); select gwm_test.trip(7, 102.8300, 16.4300, 102.8534, 16.4300);
select gwm_test.trip(8, 102.8300, 16.4300, 102.8534, 16.4300);
alter table public.trips disable trigger trg_trips_role_guard;             -- legacy dev row: car without role
select gwm_test.raw_trip(11, 'car', null);
alter table public.trips enable trigger trg_trips_role_guard;

select gwm_test.chk('B1 Driver->Rider candidate', gwm_test.cand_count(1, 3) = 1);
select gwm_test.chk('B1 Rider->Driver candidate', gwm_test.cand_count(3, 1) = 1);
select gwm_test.chk('B1 Driver<->Driver excluded', gwm_test.cand_count(1, 2) = 0 and gwm_test.cand_count(2, 1) = 0);
select gwm_test.chk('B1 Rider<->Rider excluded', gwm_test.cand_count(3, 4) = 0 and gwm_test.cand_count(4, 3) = 0);
select gwm_test.chk('B1 car<->walk excluded both ways', gwm_test.cand_count(1, 6) = 0 and gwm_test.cand_count(6, 1) = 0
  and gwm_test.cand_count(3, 6) = 0 and gwm_test.cand_count(6, 3) = 0);
select gwm_test.chk('B1 walk<->walk unchanged (peer)', gwm_test.cand_count(6, 7) = 1 and gwm_test.cand_count(7, 6) = 1);
select gwm_test.chk('B2 legacy car trip without role never matched', gwm_test.cand_count(11, 1) = 0 and gwm_test.cand_count(1, 11) = 0
  and gwm_test.cand_count(3, 11) = 0 and gwm_test.cand_count(11, 3) = 0);
select gwm_test.chk('B3 (0009 neighbourhood rule) rider destination 2.07 km beyond the short driver route > default limit 2000 m -> excluded (both sides)',
  gwm_test.cand_count(3, 10) = 0 and gwm_test.cand_count(10, 3) = 0);
select gwm_test.chk('B3 full-route driver covers rider -> candidate', gwm_test.cand_count(4, 1) = 1);

select gwm_test.as_user(gwm_test.uid(3));
select gwm_test.chk('B4 find_matches returns role (2 drivers, 0 riders)',
  gwm_test.n($q$select count(*) from public.find_matches(gwm_test.tid(3)) where role = 'driver'$q$) = 2
  and gwm_test.n($q$select count(*) from public.find_matches(gwm_test.tid(3)) where role = 'rider'$q$) = 0);
select gwm_test.reset();
select gwm_test.chk('B4 find_matches / get_trip_card expose no vehicle fields',
  pg_get_function_result('public.find_matches(uuid,int)'::regprocedure) !~* '(plate|model|color|vehicle)'
  and pg_get_function_result('public.get_trip_card(uuid)'::regprocedure) !~* '(plate|model|color|vehicle)'
  and pg_get_function_result('public.get_trip_card(uuid)'::regprocedure) ~* 'role');

select gwm_test.as_user(gwm_test.uid(11));
select gwm_test.expect_ok('B2 legacy role-less car trip can still be cancelled', $q$update public.trips set status = 'cancelled' where id = gwm_test.tid(11)$q$);
select gwm_test.reset();

-- =============================================================================
-- C. request / accept / auto-close / limits / cancel / re-request / vehicle RLS
-- =============================================================================
select gwm_test.as_user(gwm_test.uid(1));
select gwm_test.expect_error('C1 Driver->Driver request rejected at backend', $q$select public.request_match(gwm_test.tid(1), gwm_test.tid(2))$q$, 'GWM_NOT_ELIGIBLE');
select gwm_test.expect_error('C1 Driver->walker request rejected', $q$select public.request_match(gwm_test.tid(1), gwm_test.tid(6))$q$, 'GWM_NOT_ELIGIBLE');
select gwm_test.as_user(gwm_test.uid(3));
select gwm_test.expect_error('C1 Rider->Rider request rejected at backend', $q$select public.request_match(gwm_test.tid(3), gwm_test.tid(4))$q$, 'GWM_NOT_ELIGIBLE');
select gwm_test.expect_ok('C2 Rider->Driver request (R1->D1)', $q$select public.request_match(gwm_test.tid(3), gwm_test.tid(1))$q$);
select gwm_test.expect_ok('C2 Rider->Driver request (R1->D2)', $q$select public.request_match(gwm_test.tid(3), gwm_test.tid(2))$q$);
select gwm_test.as_user(gwm_test.uid(1));
select gwm_test.expect_ok('C2 Driver->Rider request (D1->R2)', $q$select public.request_match(gwm_test.tid(1), gwm_test.tid(4))$q$);
select gwm_test.as_user(gwm_test.uid(5));
select gwm_test.expect_ok('C2 Rider->Driver request (R3->D1)', $q$select public.request_match(gwm_test.tid(5), gwm_test.tid(1))$q$);

-- vehicle is invisible while pending
select gwm_test.as_user(gwm_test.uid(3));
select gwm_test.chk('C3 pending partner cannot see the vehicle (RLS + RPC)',
  gwm_test.n($q$select count(*) from public.vehicles where user_id = gwm_test.uid(1)$q$) = 0
  and gwm_test.n($q$select count(*) from public.get_match_vehicle(gwm_test.mid(1, 3))$q$) = 0);
select gwm_test.expect_error('R3-4 only the request TARGET may respond (requester cannot accept)',
  $q$select public.respond_match(gwm_test.mid(1, 3), true)$q$, 'GWM_MATCH_NOT_FOUND');
select gwm_test.as_user(gwm_test.uid(1));
select gwm_test.chk('C3 owner sees own vehicle', gwm_test.n($q$select count(*) from public.vehicles where user_id = gwm_test.uid(1)$q$) = 1);
select gwm_test.expect_ok('C4 Driver accepts R1', $q$select public.respond_match(gwm_test.mid(1, 3), true)$q$);
select gwm_test.reset();

select gwm_test.chk('C4 accepted', gwm_test.mstat(1, 3) = 'accepted');
select gwm_test.chk('C4 other pending of BOTH trips auto-closed (D1->R2, R1->D2, R3->D1)',
  gwm_test.mstat(1, 4) = 'cancelled' and gwm_test.mstat(3, 2) = 'cancelled' and gwm_test.mstat(5, 1) = 'cancelled'
  and gwm_test.n($q$select count(*) from public.matches where auto_closed$q$) = 3
  and gwm_test.n($q$select count(*) from public.matches where status = 'pending' and (requester_trip_id in (gwm_test.tid(1), gwm_test.tid(3)) or target_trip_id in (gwm_test.tid(1), gwm_test.tid(3)))$q$) = 0);
select gwm_test.chk('C4 driver_trip_id / rider_trip_id resolved by trigger',
  (select driver_trip_id = gwm_test.tid(1) and rider_trip_id = gwm_test.tid(3) from public.matches where id = gwm_test.mid(1, 3)));
select gwm_test.chk('C5 accepted Driver hidden from other Riders; accepted Rider hidden from other Drivers',
  gwm_test.cand_count(5, 1) = 0 and gwm_test.cand_count(4, 1) = 0 and gwm_test.cand_count(2, 3) = 0 and gwm_test.cand_count(3, 2) = 0
  and gwm_test.cand_count(4, 2) = 1);
select gwm_test.expect_error('C5 hard guard: 2nd accepted per DRIVER trip violates unique index',
  $q$insert into public.matches (requester_trip_id, target_trip_id, requester_id, target_id, status)
     values (gwm_test.tid(13), gwm_test.tid(1), gwm_test.uid(13), gwm_test.uid(1), 'accepted')$q$, 'matches_one_accepted_per_driver_trip');
select gwm_test.expect_error('C5 hard guard: 2nd accepted per RIDER trip violates unique index',
  $q$insert into public.matches (requester_trip_id, target_trip_id, requester_id, target_id, status)
     values (gwm_test.tid(3), gwm_test.tid(10), gwm_test.uid(3), gwm_test.uid(10), 'accepted')$q$, 'matches_one_accepted_per_rider_trip');

-- race loser: a pending row that slipped in (simulated) cannot be accepted
insert into public.matches (requester_trip_id, target_trip_id, requester_id, target_id)
values (gwm_test.tid(13), gwm_test.tid(1), gwm_test.uid(13), gwm_test.uid(1));
select gwm_test.as_user(gwm_test.uid(1));
select gwm_test.expect_error('C6 accepting a 2nd rider while the driver already has one -> GWM_MATCH_LIMIT',
  $q$select public.respond_match(gwm_test.mid(1, 13), true)$q$, 'GWM_MATCH_LIMIT');
select gwm_test.reset();

-- vehicle RLS + RPC after accept
select gwm_test.as_user(gwm_test.uid(3));
select gwm_test.chk('C7 accepted Rider sees the vehicle (RLS) and the RPC agrees, share switch OFF',
  gwm_test.n($q$select count(*) from public.vehicles where user_id = gwm_test.uid(1)$q$) = 1
  and (select share_allowed = false and plate = 'กข 1234' and model = 'Toyota Vios' from public.get_match_vehicle(gwm_test.mid(1, 3))));
select gwm_test.as_user(gwm_test.uid(4));
select gwm_test.chk('C7 auto-closed rider cannot see it', gwm_test.n($q$select count(*) from public.vehicles where user_id = gwm_test.uid(1)$q$) = 0);
select gwm_test.as_user(gwm_test.uid(5));
select gwm_test.chk('C7 another rider cannot see it', gwm_test.n($q$select count(*) from public.vehicles where user_id = gwm_test.uid(1)$q$) = 0);
select gwm_test.as_user(gwm_test.uid(9));
select gwm_test.chk('C7 stranger cannot see it', gwm_test.n($q$select count(*) from public.vehicles where user_id = gwm_test.uid(1)$q$) = 0);
select gwm_test.as_user(gwm_test.uid(2));
select gwm_test.chk('C7 other driver cannot see it', gwm_test.n($q$select count(*) from public.vehicles where user_id = gwm_test.uid(1)$q$) = 0);
select gwm_test.as_user(gwm_test.uid(1));
select gwm_test.expect_ok('C7 Driver turns share switch ON', $q$select public.set_vehicle_share_consent(true)$q$);
select gwm_test.as_user(gwm_test.uid(3));
select gwm_test.chk('C7 Rider sees share_allowed = true', (select share_allowed from public.get_match_vehicle(gwm_test.mid(1, 3))));
select gwm_test.as_user(gwm_test.uid(1));
select gwm_test.expect_ok('C7 Driver edits the car -> neutral system message', $q$select public.upsert_my_vehicle('กข 1234', 'Honda City', 'ดำ')$q$);
select gwm_test.reset();
select gwm_test.chk('C7 edit keeps the switch and posts system.vehicle_updated',
  (select share_consent_at is not null and model = 'Honda City' from public.vehicles where user_id = gwm_test.uid(1))
  and gwm_test.msgs(gwm_test.mid(1, 3), 'system.vehicle_updated') = 1);

-- pickup point: Driver opens; soft warning only (boolean, never rejected)
select gwm_test.as_user(gwm_test.uid(3));
select gwm_test.expect_error('C8 Rider cannot open the pickup proposal', $q$select public.propose_meeting_point(gwm_test.mid(1, 3), 102.8350, 16.4300, 'x')$q$, 'GWM_PICKUP_DRIVER_FIRST');
select gwm_test.as_user(gwm_test.uid(1));
select gwm_test.chk('C8 Driver point 333 m from route: no warning', (select public.propose_meeting_point(gwm_test.mid(1, 3), 102.8350, 16.4330, 'near')) = false);
select gwm_test.chk('C8 Driver point 1.1 km off route: warning=true (soft)', (select public.propose_meeting_point(gwm_test.mid(1, 3), 102.8350, 16.4400, 'far')) = true);
select gwm_test.reset();
select gwm_test.chk('C8 the far point is STILL stored (never rejected)',
  (select meeting_proposed_label = 'far' from public.matches where id = gwm_test.mid(1, 3)));
select gwm_test.as_user(gwm_test.uid(3));
select gwm_test.chk('C8 Rider may counter-propose after the Driver', (select public.propose_meeting_point(gwm_test.mid(1, 3), 102.8400, 16.4300, 'rider')) = false);
select gwm_test.as_user(gwm_test.uid(1));
select gwm_test.expect_ok('C8 Driver confirms the Rider counter-offer', $q$select public.confirm_meeting_point(gwm_test.mid(1, 3))$q$);
select gwm_test.expect_ok('C8 up to 10 proposals per match/hour (8 more)', $q$select gwm_test.propose_n(gwm_test.mid(1, 3), 8)$q$);
select gwm_test.expect_error('C8 11th proposal -> GWM_RATE_LIMITED (route oracle cap)', $q$select public.propose_meeting_point(gwm_test.mid(1, 3), 102.8350, 16.4300, 'z')$q$, 'GWM_RATE_LIMITED');
select gwm_test.reset();
select gwm_test.chk('C8 agreed pickup point stored', (select meeting_point is not null from public.matches where id = gwm_test.mid(1, 3)));

-- cancel after accept (before boarding) -> internal reason, neutral message, vehicle hidden, no re-request
select gwm_test.as_user(gwm_test.uid(3));
select gwm_test.expect_ok('C9 Rider cancels the accepted match', $q$select public.cancel_match(gwm_test.mid(1, 3))$q$);
select gwm_test.chk('C9 vehicle hidden immediately', gwm_test.n($q$select count(*) from public.vehicles where user_id = gwm_test.uid(1)$q$) = 0
  and gwm_test.n($q$select count(*) from public.get_match_vehicle(gwm_test.mid(1, 3))$q$) = 0);
select gwm_test.expect_error('C9 internal outcome is not readable by clients', $q$select count(*) from public.match_outcomes$q$, 'permission denied');
select gwm_test.expect_error('C9 cancelling pair: Rider cannot re-request', $q$select public.request_match(gwm_test.tid(3), gwm_test.tid(1))$q$, 'GWM_');
select gwm_test.as_user(gwm_test.uid(1));
select gwm_test.expect_error('C9 cancelling pair: Driver cannot request back', $q$select public.request_match(gwm_test.tid(1), gwm_test.tid(3))$q$, 'GWM_');
select gwm_test.reset();
select gwm_test.chk('C9 status cancelled + outcome cancelled_by_rider + one neutral system message',
  gwm_test.mstat(1, 3) = 'cancelled'
  and (select reason = 'cancelled_by_rider' from public.match_outcomes where match_id = gwm_test.mid(1, 3))
  and gwm_test.msgs(gwm_test.mid(1, 3), 'system.match_cancelled') = 1);
select gwm_test.chk('C9 cancelled pair never candidates again', gwm_test.cand_count(1, 3) = 0 and gwm_test.cand_count(3, 1) = 0);
select gwm_test.chk('C9 both trips back in search for others (auto-closed pairs may re-request)',
  gwm_test.cand_count(4, 1) = 1 and gwm_test.cand_count(5, 1) = 1 and gwm_test.cand_count(3, 2) = 1
  and (select scheduled_ok from (select bool_and(status = 'scheduled') as scheduled_ok from public.trips where id in (gwm_test.tid(1), gwm_test.tid(3))) x));

-- re-request of an AUTO-CLOSED pair works (stale row removed); mutual request accepts
select gwm_test.as_user(gwm_test.uid(4));
select gwm_test.expect_ok('C10 auto-closed pair may send a fresh request', $q$select public.request_match(gwm_test.tid(4), gwm_test.tid(1))$q$);
select gwm_test.as_user(gwm_test.uid(5));
select gwm_test.expect_ok('C10 R3->D1 request', $q$select public.request_match(gwm_test.tid(5), gwm_test.tid(1))$q$);
select gwm_test.as_user(gwm_test.uid(1));
select gwm_test.expect_ok('C10 D1->R3 mutual request accepts the existing one', $q$select public.request_match(gwm_test.tid(1), gwm_test.tid(5))$q$);
select gwm_test.reset();
select gwm_test.chk('C10 exactly one row per pair, D1-R3 accepted, R2->D1 and R4->D1 auto-closed',
  gwm_test.n($q$select count(*) from public.matches where gwm_test.tid(1) in (requester_trip_id, target_trip_id) and gwm_test.tid(5) in (requester_trip_id, target_trip_id)$q$) = 1
  and gwm_test.mstat(1, 5) = 'accepted' and gwm_test.mstat(4, 1) = 'cancelled' and gwm_test.mstat(13, 1) = 'cancelled'
  and (select bool_and(auto_closed) from public.matches where id in (gwm_test.mid(4, 1), gwm_test.mid(13, 1))));
select gwm_test.as_user(gwm_test.uid(1));
select gwm_test.expect_ok('C11 Driver cancels the accepted match (before start)', $q$select public.cancel_match(gwm_test.mid(1, 5))$q$);
select gwm_test.reset();
select gwm_test.chk('C11 outcome cancelled_by_driver; rider back in search',
  (select reason = 'cancelled_by_driver' from public.match_outcomes where match_id = gwm_test.mid(1, 5)) and gwm_test.cand_count(5, 2) = 1);

-- non-car peers: NO auto-close, unchanged
select gwm_test.as_user(gwm_test.uid(7));
select gwm_test.expect_ok('C12 walker 7 requests 6', $q$select public.request_match(gwm_test.tid(7), gwm_test.tid(6))$q$);
select gwm_test.as_user(gwm_test.uid(8));
select gwm_test.expect_ok('C12 walker 8 requests 6', $q$select public.request_match(gwm_test.tid(8), gwm_test.tid(6))$q$);
select gwm_test.as_user(gwm_test.uid(6));
select gwm_test.expect_ok('C12 walker 6 accepts 7', $q$select public.respond_match(gwm_test.mid(6, 7), true)$q$);
select gwm_test.reset();
select gwm_test.chk('C12 non-car: other pending request is NOT auto-closed, no car ids', gwm_test.mstat(6, 8) = 'pending'
  and not (select auto_closed from public.matches where id = gwm_test.mid(6, 8))
  and (select driver_trip_id is null and rider_trip_id is null from public.matches where id = gwm_test.mid(6, 7)));

-- =============================================================================
-- D. boarding, live location, no-show, trip cancel, share/SOS plate-only, 24 h window, block, deletion
-- =============================================================================
select gwm_test.ctrip(20, 'driver'); select gwm_test.ctrip(21, 'rider');
select gwm_test.ctrip(22, 'driver'); select gwm_test.ctrip(23, 'rider');
select gwm_test.ctrip(26, 'driver'); select gwm_test.ctrip(27, 'rider');
select gwm_test.ctrip(28, 'driver'); select gwm_test.ctrip(29, 'rider');
select gwm_test.ctrip(30, 'driver'); select gwm_test.ctrip(31, 'rider');
update public.vehicles set share_consent_at = now() where user_id = gwm_test.uid(20);       -- driver 20: switch ON
select gwm_test.pair_accept(21, 20);

select gwm_test.as_user(gwm_test.uid(9));
select gwm_test.expect_error('D1 stranger cannot mark boarded', $q$select public.mark_boarded(gwm_test.mid(20, 21))$q$, 'GWM_MATCH_NOT_FOUND');
select gwm_test.as_user(gwm_test.uid(21));
select gwm_test.expect_error('D1 boarding needs both trips in_progress', $q$select public.mark_boarded(gwm_test.mid(20, 21))$q$, 'GWM_TRIP_NOT_STARTED');
select gwm_test.expect_error('D1 rider cannot report a no-show', $q$select public.report_rider_no_show(gwm_test.mid(20, 21))$q$, 'GWM_NO_SHOW_NOT_ALLOWED');
select gwm_test.as_user(gwm_test.uid(20));
select gwm_test.expect_error('D1 Driver cannot mark boarded', $q$select public.mark_boarded(gwm_test.mid(20, 21))$q$, 'GWM_NOT_RIDER');
select gwm_test.expect_error('D1 no-show only after the Driver trip started', $q$select public.report_rider_no_show(gwm_test.mid(20, 21))$q$, 'GWM_NO_SHOW_NOT_ALLOWED');
select gwm_test.reset();

select gwm_test.trip_state(20, 'in_progress'); select gwm_test.trip_state(21, 'in_progress');
update public.trips set last_location = ST_SetSRID(ST_MakePoint(102.8350, 16.4300), 4326)::geography, last_location_at = now()
 where id in (gwm_test.tid(20), gwm_test.tid(21));
select gwm_test.as_user(gwm_test.uid(20));
select gwm_test.chk('D2 before boarding: Driver sees Rider live location',
  gwm_test.n($q$select count(*) from public.get_partner_live_location(gwm_test.mid(20, 21))$q$) = 1);
select gwm_test.as_user(gwm_test.uid(21));
select gwm_test.chk('D2 Rider sees Driver live location', gwm_test.n($q$select count(*) from public.get_partner_live_location(gwm_test.mid(20, 21))$q$) = 1);
select gwm_test.expect_ok('D3 Rider marks boarded', $q$select public.mark_boarded(gwm_test.mid(20, 21))$q$);
select gwm_test.reset();
select gwm_test.chk('D3 boarded_at set', (select boarded_at is not null from public.matches where id = gwm_test.mid(20, 21)));
select gwm_test.as_user(gwm_test.uid(21));
select gwm_test.chk('D3 mark_boarded is idempotent (same timestamp)',
  (select public.mark_boarded(gwm_test.mid(20, 21))) = (select boarded_at from public.matches where id = gwm_test.mid(20, 21)));
select gwm_test.chk('D4 after boarding: Rider still sees Driver', gwm_test.n($q$select count(*) from public.get_partner_live_location(gwm_test.mid(20, 21))$q$) = 1);
select gwm_test.expect_error('D4 no cancel after boarding', $q$select public.cancel_match(gwm_test.mid(20, 21))$q$, 'GWM_ALREADY_BOARDED');
select gwm_test.as_user(gwm_test.uid(20));
select gwm_test.chk('D4 after boarding: Rider live location no longer shared with Driver',
  gwm_test.n($q$select count(*) from public.get_partner_live_location(gwm_test.mid(20, 21))$q$) = 0);
select gwm_test.expect_error('D4 no no-show after boarding', $q$select public.report_rider_no_show(gwm_test.mid(20, 21))$q$, 'GWM_ALREADY_BOARDED');
select gwm_test.expect_error('D4 no pickup edits after boarding', $q$select public.propose_meeting_point(gwm_test.mid(20, 21), 102.8350, 16.4300, 'x')$q$, 'GWM_ALREADY_BOARDED');
select gwm_test.reset();

-- SOS snapshot + share payload (plate only, gated by the switch)
select gwm_test.as_user(gwm_test.uid(21));
select gwm_test.expect_error('D5 client cannot write the SOS vehicle snapshot',
  $q$insert into public.sos_events (user_id, trip_id, vehicle_snapshot) values (gwm_test.uid(21), gwm_test.tid(21), 'FAKE')$q$, 'permission denied');
select gwm_test.expect_ok('D5 Rider SOS', $q$insert into public.sos_events (user_id, trip_id, source) values (gwm_test.uid(21), gwm_test.tid(21), 'trip')$q$);
insert into gwm_test.tokens select 21, token from public.create_trip_share(gwm_test.tid(21));
select gwm_test.as_user(gwm_test.uid(20));
insert into gwm_test.tokens select 20, token from public.create_trip_share(gwm_test.tid(20));
select gwm_test.reset();
select gwm_test.chk('D5 SOS keeps the PLATE only, server-side, only with consent',
  (select vehicle_snapshot = 'กข 1234' from public.sos_events where user_id = gwm_test.uid(21)));
select gwm_test.chk('D5 Rider link: driver name + plate (consent ON), nothing else about the car',
  (select driver_name = 'user20' and vehicle_plate = 'กข 1234' from public.get_shared_trip((select tok from gwm_test.tokens where n = 21)))
  and pg_get_function_result('public.get_shared_trip(text)'::regprocedure) !~* '(model|color|colour)');
select gwm_test.chk('D5 Driver own link: own plate, no driver_name',
  (select driver_name is null and vehicle_plate = 'กข 1234' from public.get_shared_trip((select tok from gwm_test.tokens where n = 20))));
select gwm_test.as_user(gwm_test.uid(20));
select gwm_test.expect_ok('D5 Driver withdraws consent', $q$select public.set_vehicle_share_consent(false)$q$);
select gwm_test.reset();
select gwm_test.chk('D5 withdrawal strips the plate from the still-active backend link at once (name stays)',
  (select driver_name = 'user20' and vehicle_plate is null from public.get_shared_trip((select tok from gwm_test.tokens where n = 21))));

-- Driver trip cancelled AFTER start + boarding (system path): match ends, rider trip NOT cancelled, alert message, plate gone from links, in-app vehicle stays (Q-2)
select gwm_test.trip_state(20, 'cancelled');
select gwm_test.chk('D6 driver trip cancel after start: match cancelled, rider trip still in_progress',
  gwm_test.mstat(20, 21) = 'cancelled' and (select status = 'in_progress' from public.trips where id = gwm_test.tid(21))
  and (select reason = 'cancelled_by_driver' from public.match_outcomes where match_id = gwm_test.mid(20, 21))
  and gwm_test.msgs(gwm_test.mid(20, 21), 'system.trip_cancelled') >= 1);
select gwm_test.as_user(gwm_test.uid(21));
-- Q-2 (PM): the Rider had boarded, so the vehicle stays visible in the app until the Rider's own trip ends (+24 h). Old expectation: hidden.
-- (A client can no longer reach this state: Q-1 makes the Driver's cancel after boarding fail with GWM_ALREADY_BOARDED; here it is a system/superuser cancel.)
select gwm_test.chk('D6 Q-2: boarded Rider keeps the in-app vehicle view after the match ended',
  gwm_test.n($q$select count(*) from public.vehicles where user_id = gwm_test.uid(20)$q$) = 1);
select gwm_test.reset();
select gwm_test.chk('D6 shared link has no driver info any more',
  (select driver_name is null and vehicle_plate is null from public.get_shared_trip((select tok from gwm_test.tokens where n = 21))));

-- No-show by Driver (Rider not boarded); consent OFF => plate absent from SOS/share
select gwm_test.pair_accept(23, 22);
select gwm_test.as_user(gwm_test.uid(23));
insert into gwm_test.tokens select 23, token from public.create_trip_share(gwm_test.tid(23));
select gwm_test.expect_ok('D7 Rider SOS (driver consent OFF)', $q$insert into public.sos_events (user_id, trip_id, source) values (gwm_test.uid(23), gwm_test.tid(23), 'trip')$q$);
select gwm_test.reset();
select gwm_test.chk('D7 consent OFF: SOS snapshot NULL and link has driver name but no plate',
  (select vehicle_snapshot is null from public.sos_events where user_id = gwm_test.uid(23))
  and (select driver_name = 'user22' and vehicle_plate is null from public.get_shared_trip((select tok from gwm_test.tokens where n = 23))));
select gwm_test.trip_state(22, 'in_progress');
select gwm_test.as_user(gwm_test.uid(23));
select gwm_test.expect_error('D7 Rider cannot report a Driver no-show (Rider cancels instead)', $q$select public.report_rider_no_show(gwm_test.mid(22, 23))$q$, 'GWM_NO_SHOW_NOT_ALLOWED');
select gwm_test.as_user(gwm_test.uid(22));
select gwm_test.expect_ok('D7 Driver reports Rider no-show', $q$select public.report_rider_no_show(gwm_test.mid(22, 23))$q$);
select gwm_test.reset();
select gwm_test.chk('D7 match ended, internal reason recorded, neutral message only, rider trip back in search',
  gwm_test.mstat(22, 23) = 'cancelled'
  and (select reason = 'rider_no_show' from public.match_outcomes where match_id = gwm_test.mid(22, 23))
  and gwm_test.msgs(gwm_test.mid(22, 23), 'system.match_cancelled_in_trip') = 1
  and (select status = 'scheduled' from public.trips where id = gwm_test.tid(23))
  and gwm_test.cand_count(23, 2) = 1);
select gwm_test.as_user(gwm_test.uid(23));
select gwm_test.chk('D7 Rider lost vehicle access', gwm_test.n($q$select count(*) from public.vehicles where user_id = gwm_test.uid(22)$q$) = 0);
select gwm_test.expect_error('D7 Rider cannot read why (match_outcomes)', $q$select reason from public.match_outcomes$q$, 'permission denied');
select gwm_test.reset();

-- Driver cancels trip BEFORE start: rider trip stays scheduled and returns to search
select gwm_test.pair_accept(27, 26);
select gwm_test.trip_state(26, 'cancelled');
select gwm_test.chk('D8 driver trip cancelled before start: match ended, rider trip scheduled and searchable',
  gwm_test.mstat(26, 27) = 'cancelled' and (select status = 'scheduled' from public.trips where id = gwm_test.tid(27))
  and gwm_test.cand_count(27, 2) = 1);

-- 24 h window after a completed trip, and block
select gwm_test.pair_accept(29, 28);
select gwm_test.trip_state(28, 'in_progress'); select gwm_test.trip_state(29, 'in_progress');
select gwm_test.trip_state(28, 'completed');   select gwm_test.trip_state(29, 'completed');
select gwm_test.as_user(gwm_test.uid(29));
select gwm_test.chk('D9 completed < 24 h: Rider still sees the vehicle', gwm_test.n($q$select count(*) from public.vehicles where user_id = gwm_test.uid(28)$q$) = 1);
select gwm_test.reset();
update public.trips set ended_at = now() - interval '48 hours' where id in (gwm_test.tid(28), gwm_test.tid(29));
select gwm_test.as_user(gwm_test.uid(29));
select gwm_test.chk('D9 completed > 24 h: access gone', gwm_test.n($q$select count(*) from public.vehicles where user_id = gwm_test.uid(28)$q$) = 0);
select gwm_test.reset();

select gwm_test.pair_accept(31, 30);
select gwm_test.as_user(gwm_test.uid(31));
select gwm_test.chk('D10 before block: Rider sees the vehicle', gwm_test.n($q$select count(*) from public.vehicles where user_id = gwm_test.uid(30)$q$) = 1);
select gwm_test.as_user(gwm_test.uid(30));
select gwm_test.expect_ok('D10 Driver blocks the Rider', $q$insert into public.blocks (blocker_id, blocked_id) values (gwm_test.uid(30), gwm_test.uid(31))$q$);
select gwm_test.as_user(gwm_test.uid(31));
select gwm_test.chk('D10 block hides the vehicle even though the match row stays accepted',
  gwm_test.n($q$select count(*) from public.vehicles where user_id = gwm_test.uid(30)$q$) = 0);
select gwm_test.reset();

-- account deletion erases the vehicle
select gwm_test.veh(32);
select gwm_test.as_user(gwm_test.uid(32));
select gwm_test.expect_ok('D11 account deletion', $q$select public.request_account_deletion()$q$);
select gwm_test.reset();
select gwm_test.chk('D11 vehicle erased with the account', gwm_test.n($q$select count(*) from public.vehicles where user_id = gwm_test.uid(32)$q$) = 0);

-- PM decisions Q-1 / Q-2 / Q-8 / match_outcomes retention -----------------------------------------------------
select gwm_test.ctrip(24, 'driver'); select gwm_test.ctrip(25, 'rider');
select gwm_test.pair_accept(25, 24);
select gwm_test.trip_state(24, 'in_progress'); select gwm_test.trip_state(25, 'in_progress');
select gwm_test.as_user(gwm_test.uid(25));
select gwm_test.expect_ok('D12 Rider boards', $q$select public.mark_boarded(gwm_test.mid(24, 25))$q$);
select gwm_test.as_user(gwm_test.uid(24));
select gwm_test.chk('D12 SOS/Driver context: matched Driver can read the Rider display name (client composes the SOS text)',
  gwm_test.n($q$select count(*) from public.profiles where id = gwm_test.uid(25) and display_name = 'user25'$q$) = 1);
select gwm_test.expect_error('D12 Q-1: Driver cannot cancel the trip after the Rider boarded',
  $q$update public.trips set status = 'cancelled' where id = gwm_test.tid(24)$q$, 'GWM_ALREADY_BOARDED');
select gwm_test.reset();
select gwm_test.chk('D12 Q-1: the rejected cancel left match accepted and the driver trip in_progress',
  gwm_test.mstat(24, 25) = 'accepted' and (select status = 'in_progress' from public.trips where id = gwm_test.tid(24)));
update public.trips set depart_at = now() - interval '10 hours' where id = gwm_test.tid(24);
update public.match_outcomes set created_at = now() - interval '13 months' where match_id = gwm_test.mid(22, 23);
select public.purge_expired_data();
select gwm_test.chk('D12 Q-8: purge/expiry never closes a boarded match or an in_progress driver trip',
  gwm_test.mstat(24, 25) = 'accepted' and (select status = 'in_progress' from public.trips where id = gwm_test.tid(24)));
select gwm_test.chk('D12 match_outcomes older than 12 months purged, recent ones kept',
  gwm_test.n($q$select count(*) from public.match_outcomes where match_id = gwm_test.mid(22, 23)$q$) = 0
  and gwm_test.n($q$select count(*) from public.match_outcomes where match_id = gwm_test.mid(1, 5)$q$) = 1);
select gwm_test.trip_state(24, 'completed');
update public.trips set ended_at = now() - interval '48 hours' where id = gwm_test.tid(24);
select gwm_test.chk('D13 Q-2: Driver finished, match stays accepted', gwm_test.mstat(24, 25) = 'accepted');
select gwm_test.as_user(gwm_test.uid(25));
select gwm_test.chk('D13 Q-2: boarded Rider still sees the vehicle (RLS + RPC) after the Driver trip ended > 24 h ago, while own trip runs',
  gwm_test.n($q$select count(*) from public.vehicles where user_id = gwm_test.uid(24)$q$) = 1
  and gwm_test.n($q$select count(*) from public.get_match_vehicle(gwm_test.mid(24, 25))$q$) = 1);
select gwm_test.reset();
select gwm_test.trip_state(25, 'completed');
select gwm_test.as_user(gwm_test.uid(25));
select gwm_test.chk('D13 Q-2: still visible < 24 h after the Rider trip ended', gwm_test.n($q$select count(*) from public.vehicles where user_id = gwm_test.uid(24)$q$) = 1);
select gwm_test.reset();
update public.trips set ended_at = now() - interval '48 hours' where id = gwm_test.tid(25);
select gwm_test.as_user(gwm_test.uid(25));
select gwm_test.chk('D13 Q-2: gone > 24 h after the Rider trip ended', gwm_test.n($q$select count(*) from public.vehicles where user_id = gwm_test.uid(24)$q$) = 0
  and gwm_test.n($q$select count(*) from public.get_match_vehicle(gwm_test.mid(24, 25))$q$) = 0);
select gwm_test.reset();
select gwm_test.chk('D13 Q-2 contrast: share link plate still consent-gated (driver 24 switch OFF)',
  (select share_consent_at is null from public.vehicles where user_id = gwm_test.uid(24)));

-- US-18 P0: rider never taps "ขึ้นรถแล้ว" (boarded_at stays null); missing boarding must not block start/complete ---------
select gwm_test.signup(n) from generate_series(42, 47) n;
-- F1: 46 = Driver, 47 = Rider; never boarded
select gwm_test.ctrip(46, 'driver'); select gwm_test.ctrip(47, 'rider');
select gwm_test.pair_accept(47, 46);
select gwm_test.as_user(gwm_test.uid(46));
select gwm_test.expect_ok('F1 US-18: Driver starts the trip while the Rider has not boarded', $q$update public.trips set status = 'in_progress' where id = gwm_test.tid(46)$q$);
select gwm_test.as_user(gwm_test.uid(47));
select gwm_test.expect_ok('F1 US-18: Rider starts the trip without ever tapping boarded', $q$update public.trips set status = 'in_progress' where id = gwm_test.tid(47)$q$);
select gwm_test.reset();
select gwm_test.chk('F1 US-18: boarded_at stays null and match stays accepted after both trips started',
  (select boarded_at is null from public.matches where id = gwm_test.mid(46, 47)) and gwm_test.mstat(46, 47) = 'accepted');
select gwm_test.as_user(gwm_test.uid(46));
select gwm_test.expect_ok('F1 US-18: Driver marks arrival / completes with boarded_at null', $q$update public.trips set status = 'completed' where id = gwm_test.tid(46)$q$);
select gwm_test.as_user(gwm_test.uid(47));
select gwm_test.expect_ok('F1 US-18: Rider marks arrival / completes with boarded_at null', $q$update public.trips set status = 'completed' where id = gwm_test.tid(47)$q$);
select gwm_test.reset();
select gwm_test.chk('F1 US-18: both trips completed, boarded_at still null, match not cancelled, no outcome row',
  (select count(*) = 2 from public.trips where id in (gwm_test.tid(46), gwm_test.tid(47)) and status = 'completed')
  and (select boarded_at is null from public.matches where id = gwm_test.mid(46, 47)) and gwm_test.mstat(46, 47) = 'accepted'
  and gwm_test.n($q$select count(*) from public.match_outcomes where match_id = gwm_test.mid(46, 47)$q$) = 0);
-- F2: Q-1 driver cancel allowed while boarded_at is null (in_progress), then rejected once boarded
select gwm_test.ctrip(42, 'driver'); select gwm_test.ctrip(43, 'rider'); select gwm_test.ctrip(44, 'driver'); select gwm_test.ctrip(45, 'rider');
select gwm_test.pair_accept(43, 42); select gwm_test.pair_accept(45, 44);
select gwm_test.trip_state(42, 'in_progress'); select gwm_test.trip_state(43, 'in_progress');
select gwm_test.trip_state(44, 'in_progress'); select gwm_test.trip_state(45, 'in_progress');
select gwm_test.as_user(gwm_test.uid(42));
select gwm_test.expect_ok('F2 Q-1: Driver cancel_match allowed while boarded_at is null', $q$select public.cancel_match(gwm_test.mid(42, 43))$q$);
select gwm_test.reset();
select gwm_test.chk('F2 Q-1: match cancelled with outcome cancelled_by_driver',
  gwm_test.mstat(42, 43) = 'cancelled' and (select reason from public.match_outcomes where match_id = gwm_test.mid(42, 43)) = 'cancelled_by_driver');
select gwm_test.as_user(gwm_test.uid(45));
select gwm_test.expect_ok('F2 Rider boards (second pair)', $q$select public.mark_boarded(gwm_test.mid(44, 45))$q$);
select gwm_test.as_user(gwm_test.uid(44));
select gwm_test.expect_error('F2 Q-1: Driver cancel_match rejected once boarded', $q$select public.cancel_match(gwm_test.mid(44, 45))$q$, 'GWM_ALREADY_BOARDED');
select gwm_test.reset();
select gwm_test.chk('F2 Q-1: rejected driver cancel left match accepted', gwm_test.mstat(44, 45) = 'accepted');

-- grants: clients cannot reach internals
select gwm_test.chk('E1 internal functions are not executable by clients',
  not has_function_privilege('authenticated', 'public._accept_match(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public._pickup_beyond_limit(uuid,double precision,double precision)', 'execute')
  and not has_function_privilege('anon', 'public.get_match_vehicle(uuid)', 'execute')
  and has_function_privilege('anon', 'public.get_shared_trip(text)', 'execute'));
select gwm_test.chk('E1 match_outcomes has no client privileges',
  not has_table_privilege('authenticated', 'public.match_outcomes', 'select') and not has_table_privilege('anon', 'public.vehicles', 'select'));


-- ---- report ---------------------------------------------------------------------------------------
select gwm_test.reset();
select n, case when ok then 'PASS' else 'FAIL' end as result, label, detail from gwm_test.results order by n;
select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed from gwm_test.results;
do $$
begin
  if exists (select 1 from gwm_test.results where not ok) then
    raise exception 'Driver/Rider roles SQL tests FAILED: % check(s)', (select count(*) from gwm_test.results where not ok);
  end if;
end $$;
rollback;
