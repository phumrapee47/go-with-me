-- =============================================================================
-- GOWITHME automated SQL tests for migration 0008 (Dual role, round 4: US-19 register/unregister driver,
-- US-20 active role, changed ACs of US-5/16/17; docs/design-roles.md section 11).
-- Run after migrations 0001-0008 (as the postgres superuser role):
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f supabase/tests/dual_role.sql
-- One transaction, ROLLED BACK at the end. Same harness as roles.sql / qa_round1.sql. Khon Kaen coordinates on one west->east line.
-- A true concurrent race cannot be reproduced in one transaction: it is covered by (a) both orderings tested sequentially,
-- (b) a static check that trips_role_guard takes FOR SHARE on the profile row, (c) unregister locking the row first.
-- Prints PASS/FAIL rows and exits non-zero on any FAIL.
-- =============================================================================
\set ON_ERROR_STOP on
begin;
set search_path = public, extensions;

-- ---- harness (same as roles.sql) ---------------------------------------------------------------
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

-- ---- helpers specific to this file --------------------------------------------------------------
-- Registered driver WITHOUT the RPC (fixture, superuser): vehicle + the three server-owned columns
create function gwm_test.force_reg(p_n int) returns void language plpgsql as $$
begin
  insert into public.vehicles (user_id, plate, model, color) values (gwm_test.uid(p_n), 'กข 1234', 'Toyota Vios', 'ขาว')
  on conflict do nothing;
  update public.profiles set driver_registered_at = now(), licence_declared_at = now(), licence_declaration_version = 'd1-draft'
   where id = gwm_test.uid(p_n);
end $$;

-- car trip on the straight west->east line at lat 16.43 (origin 102.8300). p_tid = trip id number (default = user number)
create function gwm_test.raw_trip(p_n int, p_mode text, p_role text, p_tid int default null) returns void language plpgsql as $$
begin
  insert into public.trips (id, user_id, mode, role, origin, dest, route, route_distance_m, route_duration_s, depart_at)
  values (gwm_test.tid(coalesce(p_tid, p_n)), gwm_test.uid(p_n), p_mode::public.travel_mode, p_role::public.trip_role,
          ST_SetSRID(ST_MakePoint(102.8300, 16.4300), 4326)::geography, ST_SetSRID(ST_MakePoint(102.8534, 16.4300), 4326)::geography,
          ST_MakeLine(ST_SetSRID(ST_MakePoint(102.8300, 16.4300), 4326), ST_SetSRID(ST_MakePoint(102.8534, 16.4300), 4326))::geography,
          2500, 600, now() + interval '1 hour');
end $$;

create function gwm_test.mid(a int, b int) returns uuid language sql as $$
  select id from public.matches
   where least(requester_trip_id, target_trip_id) = least(gwm_test.tid(a), gwm_test.tid(b))
     and greatest(requester_trip_id, target_trip_id) = greatest(gwm_test.tid(a), gwm_test.tid(b)) $$;
create function gwm_test.cand_count(p_req int, p_cand int) returns bigint language sql as
$$ select count(*) from public.match_candidates(gwm_test.tid(p_req)) where candidate_trip_id = gwm_test.tid(p_cand) $$;
create function gwm_test.pair_accept(p_req int, p_tgt int) returns void language plpgsql as $$
begin
  perform gwm_test.as_user(gwm_test.uid(p_req));
  perform public.request_match(gwm_test.tid(p_req), gwm_test.tid(p_tgt));
  perform gwm_test.reset();
  perform gwm_test.as_user(gwm_test.uid(p_tgt));
  perform public.respond_match(gwm_test.mid(p_req, p_tgt), true);
  perform gwm_test.reset();
end $$;

-- the test must not trip the per-user throttles (throttle behaviour has its own check in section G)
update public.app_config set value = '1000' where key in ('throttle.driver_registration_per_hour', 'throttle.role_switch_per_min');

-- ---- users: 1 main flow, 2 invalid registration, 3 never registers, 4/5 driver+rider match, 6 rider trip only,
--      7 legacy driver, 8 account deletion, 9 throttle, 10 legacy rider -------------------------------------------
select gwm_test.signup(i) from generate_series(1, 10) i;

-- ================= A. defaults: every new account is a Rider only (US-19 AC1) ================================
select gwm_test.chk('A1 new profile: active_role rider, not registered, no declaration',
  (select active_role = 'rider' and not driver_registered and driver_registered_at is null
          and licence_declared_at is null and licence_declaration_version is null
     from public.profiles where id = gwm_test.uid(3)));
select gwm_test.as_user(gwm_test.uid(3));
select gwm_test.chk('A2 get_my_role_state for a fresh account',
  (public.get_my_role_state() ->> 'active_role') = 'rider' and (public.get_my_role_state() ->> 'driver_registered') = 'false'
  and public.get_my_role_state() -> 'roles' = '["rider"]'::jsonb and (public.get_my_role_state() ->> 'has_vehicle') = 'false');
select gwm_test.reset();
select gwm_test.chk('A3 no licence number / photo column exists on profiles',
  not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'profiles'
               and (column_name ilike '%licen%number%' or column_name ilike '%licence_no%' or column_name ilike '%licence_photo%'
                    or column_name ilike '%license%')));

-- ================= B. privileges: clients cannot write or read the new columns directly ====================
select gwm_test.as_user(gwm_test.uid(3));
select gwm_test.expect_error('B1 client cannot UPDATE active_role', $q$update public.profiles set active_role = 'driver' where id = gwm_test.uid(3)$q$, 'permission denied');
select gwm_test.expect_error('B2 client cannot UPDATE driver_registered_at', $q$update public.profiles set driver_registered_at = now() where id = gwm_test.uid(3)$q$, 'permission denied');
select gwm_test.expect_error('B3 client cannot UPDATE licence_declared_at', $q$update public.profiles set licence_declared_at = now() where id = gwm_test.uid(3)$q$, 'permission denied');
select gwm_test.expect_error('B4 client cannot UPDATE licence_declaration_version', $q$update public.profiles set licence_declaration_version = 'x' where id = gwm_test.uid(3)$q$, 'permission denied');
select gwm_test.expect_error('B5 client cannot UPDATE the derived flag', $q$update public.profiles set driver_registered = true where id = gwm_test.uid(3)$q$, '428C9');   -- generated-column check fires before the privilege check
select gwm_test.expect_error('B6 client cannot INSERT a profile row', $q$insert into public.profiles (id, display_name) values (gen_random_uuid(), 'x')$q$, 'permission denied');
select gwm_test.expect_error('B7 client cannot SELECT the licence declaration column (even own row)', $q$select licence_declared_at from public.profiles where id = gwm_test.uid(3)$q$, 'permission denied');
select gwm_test.expect_error('B8 select * on profiles is denied (column list only)', $q$select * from public.profiles where id = gwm_test.uid(3)$q$, 'permission denied');
select gwm_test.expect_ok('B9 explicit existing columns still readable', $q$select id, display_name, avatar_path, deleted_at from public.profiles where id = gwm_test.uid(3)$q$);
select gwm_test.expect_ok('B10 display_name update still allowed', $q$update public.profiles set display_name = 'renamed 3' where id = gwm_test.uid(3)$q$);
select gwm_test.reset();
select gwm_test.chk('B11 column privileges (authenticated): new columns not readable/writable; display_name writable',
  not has_column_privilege('authenticated', 'public.profiles', 'licence_declared_at', 'select')
  and not has_column_privilege('authenticated', 'public.profiles', 'active_role', 'select')
  and not has_column_privilege('authenticated', 'public.profiles', 'active_role', 'update')
  and not has_column_privilege('authenticated', 'public.profiles', 'driver_registered_at', 'update')
  and not has_column_privilege('authenticated', 'public.profiles', 'adult_confirmed_at', 'update')
  and has_column_privilege('authenticated', 'public.profiles', 'display_name', 'update')
  and not has_table_privilege('anon', 'public.profiles', 'select'));
select gwm_test.chk('B12 RPC grants: authenticated only; internal _role_state closed',
  has_function_privilege('authenticated', 'public.register_driver(text,text,text,text)', 'execute')
  and has_function_privilege('authenticated', 'public.unregister_driver()', 'execute')
  and has_function_privilege('authenticated', 'public.set_active_role(public.trip_role)', 'execute')
  and has_function_privilege('authenticated', 'public.get_my_role_state()', 'execute')
  and not has_function_privilege('anon', 'public.register_driver(text,text,text,text)', 'execute')
  and not has_function_privilege('anon', 'public.unregister_driver()', 'execute')
  and not has_function_privilege('anon', 'public.set_active_role(public.trip_role)', 'execute')
  and not has_function_privilege('anon', 'public.get_my_role_state()', 'execute')
  and not has_function_privilege('authenticated', 'public._role_state(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.trips_role_guard()', 'execute')
  and not has_function_privilege('authenticated', 'public.vehicles_delete_guard()', 'execute'));
select gwm_test.chk('B13 register_driver takes no timestamp argument (declaration time is server time)',
  (select pronargs from pg_proc where oid = 'public.register_driver(text,text,text,text)'::regprocedure) = 4);
-- table CHECK invariants (superuser bypasses grants, not constraints)
select gwm_test.expect_error('B14 CHECK: active_role driver requires registration', $q$update public.profiles set active_role = 'driver' where id = gwm_test.uid(3)$q$, '23514');
select gwm_test.expect_error('B15 CHECK: registered_at without declaration', $q$update public.profiles set driver_registered_at = now() where id = gwm_test.uid(3)$q$, '23514');
select gwm_test.expect_error('B16 CHECK: declaration time without version', $q$update public.profiles set driver_registered_at = now(), licence_declared_at = now() where id = gwm_test.uid(3)$q$, '23514');
select gwm_test.expect_error('B17 derived flag cannot be written even by superuser', $q$update public.profiles set driver_registered = true where id = gwm_test.uid(3)$q$, '428C9');

-- ================= C. register_driver (US-19) ==========================================================
select gwm_test.expect_error('C1 unauthenticated call rejected', $q$select public.register_driver('กข 1', 'Vios', 'ขาว', 'd1-draft')$q$, 'GWM_UNAUTHENTICATED');
select gwm_test.as_user(gwm_test.uid(2));
select gwm_test.expect_error('C2 blank plate', $q$select public.register_driver('   ', 'Vios', 'ขาว', 'd1-draft')$q$, 'GWM_VEHICLE_INVALID');
select gwm_test.expect_error('C3 blank model', $q$select public.register_driver('กข 1', '', 'ขาว', 'd1-draft')$q$, 'GWM_VEHICLE_INVALID');
select gwm_test.expect_error('C4 null colour', $q$select public.register_driver('กข 1', 'Vios', null, 'd1-draft')$q$, 'GWM_VEHICLE_INVALID');
select gwm_test.expect_error('C5 plate too long (26)', $q$select public.register_driver(repeat('A', 26), 'Vios', 'ขาว', 'd1-draft')$q$, 'GWM_VEHICLE_INVALID');
select gwm_test.expect_error('C6 control character in model', $q$select public.register_driver('กข 1', E'Vi\x01os', 'ขาว', 'd1-draft')$q$, 'GWM_VEHICLE_INVALID');
select gwm_test.expect_error('C7 declaration missing (not ticked) = null', $q$select public.register_driver('กข 1', 'Vios', 'ขาว', null)$q$, 'GWM_DECLARATION_REQUIRED');
select gwm_test.expect_error('C8 declaration blank', $q$select public.register_driver('กข 1', 'Vios', 'ขาว', '  ')$q$, 'GWM_DECLARATION_REQUIRED');
select gwm_test.expect_error('C9 declaration version stale/unknown', $q$select public.register_driver('กข 1', 'Vios', 'ขาว', 'd0-old')$q$, 'GWM_DECLARATION_VERSION_STALE');
select gwm_test.reset();
select gwm_test.chk('C10 atomic: every failed attempt left no vehicle and no registration',
  (select count(*) from public.vehicles where user_id = gwm_test.uid(2)) = 0
  and (select driver_registered_at is null and licence_declared_at is null and licence_declaration_version is null and active_role = 'rider'
         from public.profiles where id = gwm_test.uid(2)));

select gwm_test.as_user(gwm_test.uid(10));
select gwm_test.expect_ok('C5b plate of exactly 25 chars is valid (upsert_my_vehicle + CHECK)', $q$select public.upsert_my_vehicle(repeat('A', 25), 'Vios', 'ขาว')$q$);
select gwm_test.expect_error('C5c plate of 26 chars rejected by upsert_my_vehicle', $q$select public.upsert_my_vehicle(repeat('A', 26), 'Vios', 'ขาว')$q$, 'GWM_VEHICLE_INVALID');
select gwm_test.reset();
select gwm_test.chk('C5d server CHECK on vehicles.plate is 25', (select pg_get_constraintdef(oid) like '%<= 25%' from pg_constraint where conname = 'vehicles_plate_check'));

select gwm_test.as_user(gwm_test.uid(1));
select gwm_test.expect_ok('C11 register with valid data + current declaration version',
  $q$select public.register_driver('  กข   1234 ', 'Toyota Vios', 'ขาว', 'd1-draft')$q$);
select gwm_test.chk('C12 state returned: registered, both roles, active_role still rider (no auto switch), has_vehicle',
  (public.get_my_role_state() ->> 'driver_registered') = 'true' and (public.get_my_role_state() ->> 'active_role') = 'rider'
  and public.get_my_role_state() -> 'roles' = '["rider","driver"]'::jsonb and (public.get_my_role_state() ->> 'has_vehicle') = 'true'
  and (public.get_my_role_state() ->> 'licence_declaration_version') = 'd1-draft');
select gwm_test.reset();
select gwm_test.chk('C13 declaration time = server time; registered_at set; plate normalised; share switch OFF; not verified',
  (select p.licence_declared_at = now() and p.driver_registered_at = now() and p.licence_declaration_version = 'd1-draft'
     from public.profiles p where p.id = gwm_test.uid(1))
  and (select v.plate = 'กข 1234' and v.share_consent_at is null and v.verified_at is null
         from public.vehicles v where v.user_id = gwm_test.uid(1)));

-- idempotency: age the declaration, register again with an edited colour
update public.profiles set driver_registered_at = now() - interval '1 day', licence_declared_at = now() - interval '1 day'
 where id = gwm_test.uid(1);
select gwm_test.as_user(gwm_test.uid(1));
select gwm_test.expect_ok('C14 register again while registered (double tap / second device)',
  $q$select public.register_driver('กข 1234', 'Toyota Vios', 'ดำ', 'd1-draft')$q$);
select gwm_test.expect_ok('C15 register again with identical data',
  $q$select public.register_driver('กข 1234', 'Toyota Vios', 'ดำ', 'd1-draft')$q$);
select gwm_test.reset();
select gwm_test.chk('C16 idempotent: still 1 vehicle (updated), original declaration/registered times untouched',
  (select count(*) from public.vehicles where user_id = gwm_test.uid(1)) = 1
  and (select color = 'ดำ' from public.vehicles where user_id = gwm_test.uid(1))
  and (select licence_declared_at < now() - interval '23 hours' and driver_registered_at < now() - interval '23 hours'
         from public.profiles where id = gwm_test.uid(1)));

-- ================= D. set_active_role (US-20) ==========================================================
select gwm_test.as_user(gwm_test.uid(3));
select gwm_test.expect_error('D1 unregistered cannot set active_role driver', $q$select public.set_active_role('driver')$q$, 'GWM_NOT_A_DRIVER');
select gwm_test.expect_ok('D2 unregistered can set rider (idempotent no-op)', $q$select public.set_active_role('rider')$q$);
select gwm_test.expect_error('D3 null role rejected', $q$select public.set_active_role(null)$q$, 'GWM_INVALID_ROLE');
select gwm_test.reset();
select gwm_test.chk('D4 rejected switch left active_role rider', (select active_role = 'rider' from public.profiles where id = gwm_test.uid(3)));
select gwm_test.as_user(gwm_test.uid(1));
select gwm_test.expect_ok('D5 registered user switches to driver', $q$select public.set_active_role('driver')$q$);
select gwm_test.expect_ok('D6 repeat switch is idempotent', $q$select public.set_active_role('driver')$q$);
select gwm_test.chk('D7 state shows driver', (public.get_my_role_state() ->> 'active_role') = 'driver');
select gwm_test.reset();

-- ================= E. trips guard: role=driver needs registration; max 1 active trip; role stays with the trip ======
select gwm_test.as_user(gwm_test.uid(3));
select gwm_test.expect_error('E1 unregistered: client INSERT of a driver trip (direct API) rejected', $q$select gwm_test.raw_trip(3, 'car', 'driver')$q$, 'GWM_NOT_A_DRIVER');
select gwm_test.expect_ok('E2 unregistered: rider trip is fine', $q$select gwm_test.raw_trip(3, 'car', 'rider')$q$);
select gwm_test.reset();
select gwm_test.chk('E3 no driver trip row was created for the unregistered account',
  (select count(*) from public.trips where user_id = gwm_test.uid(3) and role = 'driver') = 0);
select gwm_test.expect_error('E4 superuser/service insert of a driver trip for an unregistered account also rejected', $q$select gwm_test.raw_trip(2, 'car', 'driver')$q$, 'GWM_NOT_A_DRIVER');

select gwm_test.as_user(gwm_test.uid(1));
select gwm_test.expect_ok('E5 registered: driver trip created (client path)', $q$select gwm_test.raw_trip(1, 'car', 'driver', 1)$q$);
select gwm_test.expect_ok('E6 switching active role rider while the driver trip is scheduled', $q$select public.set_active_role('rider')$q$);
select gwm_test.expect_error('E7 still max 1 active trip (second trip, rider) rejected', $q$select gwm_test.raw_trip(1, 'car', 'rider', 101)$q$, 'GWM_ACTIVE_TRIP_LIMIT');
select gwm_test.reset();
select gwm_test.chk('E8 role switch did not change the existing trip role', (select role = 'driver' from public.trips where id = gwm_test.tid(1)));
select gwm_test.chk('E9 trips_role_guard locks the profile row FOR SHARE (race-safe vs unregister_driver)',
  pg_get_functiondef('public.trips_role_guard()'::regprocedure) ilike '%for share%'
  and pg_get_functiondef('public.unregister_driver()'::regprocedure) ilike '%for update%');
-- registered driver whose vehicle row vanished (defensive): vehicle still required
select gwm_test.force_reg(2);
delete from public.vehicles where user_id = gwm_test.uid(2);           -- superuser: auth.uid() null => guard skipped
select gwm_test.expect_error('E10 registered but vehicle missing => GWM_VEHICLE_REQUIRED', $q$select gwm_test.raw_trip(2, 'car', 'driver')$q$, 'GWM_VEHICLE_REQUIRED');

-- ================= F. unregister_driver + vehicle rules (user 1 continues) ==================================
select gwm_test.as_user(gwm_test.uid(1));
select gwm_test.expect_error('F1 unregister refused while a driver trip is scheduled', $q$select public.unregister_driver()$q$, 'GWM_DRIVER_ACTIVE_TRIP');
select gwm_test.expect_error('F2 delete_my_vehicle refused while a driver trip is active', $q$select public.delete_my_vehicle()$q$, 'GWM_VEHICLE_IN_USE');
select gwm_test.reset();
select gwm_test.chk('F3 refused unregister changed nothing',
  (select driver_registered and licence_declaration_version = 'd1-draft' from public.profiles where id = gwm_test.uid(1))
  and (select count(*) from public.vehicles where user_id = gwm_test.uid(1)) = 1);
select gwm_test.as_user(gwm_test.uid(1));
select gwm_test.expect_ok('F4 cancel the driver trip', $q$update public.trips set status = 'cancelled' where id = gwm_test.tid(1)$q$);
select gwm_test.expect_error('F5 registered driver cannot delete the vehicle (unregister first)', $q$select public.delete_my_vehicle()$q$, 'GWM_DRIVER_REGISTERED');
select gwm_test.expect_ok('F6 switch to driver mode again, turn share consent on', $q$select public.set_active_role('driver')$q$);
select gwm_test.chk('F7 share consent ON while registered', public.set_vehicle_share_consent(true) is not null);
select gwm_test.expect_ok('F8 unregister succeeds (no active driver trip / match)', $q$select public.unregister_driver()$q$);
select gwm_test.chk('F9 state after unregister: rider only, active_role rider, vehicle kept',
  (public.get_my_role_state() ->> 'driver_registered') = 'false' and (public.get_my_role_state() ->> 'active_role') = 'rider'
  and public.get_my_role_state() -> 'roles' = '["rider"]'::jsonb and (public.get_my_role_state() ->> 'has_vehicle') = 'true'
  and (public.get_my_role_state() ->> 'licence_declared_at') is null and (public.get_my_role_state() ->> 'licence_declaration_version') is null);
select gwm_test.expect_ok('F10 unregister again is a no-op success', $q$select public.unregister_driver()$q$);
select gwm_test.expect_error('F11 share consent cannot be turned ON while unregistered', $q$select public.set_vehicle_share_consent(true)$q$, 'GWM_NOT_A_DRIVER');
select gwm_test.expect_ok('F12 share consent OFF always allowed', $q$select public.set_vehicle_share_consent(false)$q$);
select gwm_test.expect_error('F13 driver trip refused right after unregister (other order of the race)', $q$select gwm_test.raw_trip(1, 'car', 'driver', 102)$q$, 'GWM_NOT_A_DRIVER');
select gwm_test.expect_error('F14 set_active_role driver refused after unregister', $q$select public.set_active_role('driver')$q$, 'GWM_NOT_A_DRIVER');
select gwm_test.expect_ok('F15 same account creates a RIDER trip after having had a driver trip (US-16: different time)', $q$select gwm_test.raw_trip(1, 'car', 'rider', 103)$q$);
select gwm_test.reset();
select gwm_test.chk('F16 unregister kept the vehicle (1 row), consent cleared, declaration ended',
  (select count(*) from public.vehicles where user_id = gwm_test.uid(1)) = 1
  and (select share_consent_at is null from public.vehicles where user_id = gwm_test.uid(1))
  and (select driver_registered_at is null and licence_declared_at is null and licence_declaration_version is null
         from public.profiles where id = gwm_test.uid(1)));
select gwm_test.as_user(gwm_test.uid(1));
select gwm_test.expect_ok('F17 register again while a RIDER trip is active (allowed)',
  $q$select public.register_driver('กข 1234', 'Toyota Vios', 'ดำ', 'd1-draft')$q$);
select gwm_test.chk('F18 re-registration: new declaration, vehicle reused (1 row), share consent still OFF',
  (public.get_my_role_state() ->> 'driver_registered') = 'true'
  and (select count(*) from public.vehicles where user_id = gwm_test.uid(1)) = 1
  and (select share_consent_at is null from public.vehicles where user_id = gwm_test.uid(1)));
select gwm_test.expect_ok('F19 unregister with only a rider trip active succeeds (rider trip does not block)', $q$select public.unregister_driver()$q$);
select gwm_test.expect_ok('F20 unregistered account may delete the retained vehicle', $q$select public.delete_my_vehicle()$q$);
select gwm_test.reset();
select gwm_test.chk('F21 vehicle gone; rider trip untouched',
  (select count(*) from public.vehicles where user_id = gwm_test.uid(1)) = 0
  and (select status = 'scheduled' from public.trips where id = gwm_test.tid(103)));

-- user 6: registered, only a rider trip; user 4/5: driver <-> rider accepted match
select gwm_test.force_reg(6);
select gwm_test.raw_trip(6, 'car', 'rider');
select gwm_test.as_user(gwm_test.uid(6));
select gwm_test.expect_ok('F22 registered user with only an active rider trip can unregister', $q$select public.unregister_driver()$q$);
select gwm_test.reset();
select gwm_test.chk('F23 F22 kept the rider trip and the vehicle',
  (select status = 'scheduled' from public.trips where id = gwm_test.tid(6))
  and (select count(*) from public.vehicles where user_id = gwm_test.uid(6)) = 1);

select gwm_test.force_reg(4);
select gwm_test.raw_trip(4, 'car', 'driver');
select gwm_test.raw_trip(5, 'car', 'rider');
select gwm_test.chk('F24 fixture: driver 4 and rider 5 are candidates', gwm_test.cand_count(5, 4) = 1);
select gwm_test.pair_accept(5, 4);
select gwm_test.chk('F25 fixture: match accepted', (select status = 'accepted' from public.matches where id = gwm_test.mid(4, 5)));
select gwm_test.as_user(gwm_test.uid(4));
select gwm_test.expect_error('F26 unregister refused: driver trip + accepted match', $q$select public.unregister_driver()$q$, 'GWM_DRIVER_ACTIVE_TRIP');
select gwm_test.reset();
select gwm_test.as_user(gwm_test.uid(5));
select gwm_test.chk('F27 Rider sees the registered driver vehicle (unchanged US-17 behaviour)',
  (select count(*) from public.get_match_vehicle(gwm_test.mid(4, 5))) = 1);
select gwm_test.reset();
-- soft-deleted (but still scheduled) driver trip with an accepted match: only the match check can catch it
update public.trips set deleted_at = now() where id = gwm_test.tid(4);
select gwm_test.as_user(gwm_test.uid(4));
select gwm_test.expect_error('F28 unregister refused: accepted match whose Driver trip is still scheduled', $q$select public.unregister_driver()$q$, 'GWM_DRIVER_ACTIVE_MATCH');
select gwm_test.reset();
select gwm_test.chk('F29 refused unregister left registration intact', (select driver_registered from public.profiles where id = gwm_test.uid(4)));
update public.trips set deleted_at = null where id = gwm_test.tid(4);
-- driver trip finished: match stays 'accepted' but Q11-2 = only ACTIVE driver trips block
update public.trips set status = 'in_progress' where id = gwm_test.tid(4);
update public.trips set status = 'completed'   where id = gwm_test.tid(4);
select gwm_test.as_user(gwm_test.uid(4));
select gwm_test.expect_ok('F30 unregister succeeds once the Driver trip ended (accepted match in the 24 h window does not block)', $q$select public.unregister_driver()$q$);
select gwm_test.reset();

-- ================= G. throttle ======================================================================
update public.app_config set value = '2' where key = 'throttle.driver_registration_per_hour';
select gwm_test.as_user(gwm_test.uid(9));
select gwm_test.expect_ok('G1 register call 1', $q$select public.register_driver('ขค 1', 'Vios', 'แดง', 'd1-draft')$q$);
select gwm_test.expect_ok('G2 register call 2 (idempotent)', $q$select public.register_driver('ขค 1', 'Vios', 'แดง', 'd1-draft')$q$);
select gwm_test.expect_error('G3 3rd call within the hour rate-limited', $q$select public.register_driver('ขค 1', 'Vios', 'แดง', 'd1-draft')$q$, 'GWM_RATE_LIMITED');
select gwm_test.reset();
update public.app_config set value = '1000' where key = 'throttle.driver_registration_per_hour';

-- ================= H. legacy dev data (round 3): driver trips/vehicles do not count as registered ==============
-- Simulate a 0006-era driver: trip + vehicle with share consent, inserted with the role guard disabled (as it did not exist yet).
alter table public.trips disable trigger trg_trips_role_guard;
select gwm_test.raw_trip(7, 'car', 'driver');
alter table public.trips enable trigger trg_trips_role_guard;
insert into public.vehicles (user_id, plate, model, color, share_consent_at) values (gwm_test.uid(7), 'ลก 999', 'Old', 'เทา', now());
select gwm_test.raw_trip(10, 'car', 'rider');
select gwm_test.chk('H1 before cleanup the legacy driver trip is still matchable', gwm_test.cand_count(10, 7) = 1);
select gwm_test.chk('H2 legacy account is NOT registered', (select not driver_registered from public.profiles where id = gwm_test.uid(7)));
-- same statements as section 9 of 0008
update public.trips t set status = 'cancelled'
 where t.role = 'driver' and t.status in ('scheduled','in_progress')
   and not exists (select 1 from public.profiles p where p.id = t.user_id and p.driver_registered_at is not null);
update public.vehicles v set share_consent_at = null
 where v.share_consent_at is not null
   and not exists (select 1 from public.profiles p where p.id = v.user_id and p.driver_registered_at is not null);
select gwm_test.chk('H3 cleanup: legacy driver trip cancelled and no longer matchable',
  (select status = 'cancelled' from public.trips where id = gwm_test.tid(7)) and gwm_test.cand_count(10, 7) = 0);
select gwm_test.chk('H4 cleanup: legacy vehicle kept (owner only) with share consent off',
  (select share_consent_at is null from public.vehicles where user_id = gwm_test.uid(7)));
select gwm_test.chk('H5 cleanup did not touch registered users trips/vehicles (user 9 still registered)',
  (select driver_registered from public.profiles where id = gwm_test.uid(9)));
-- registered-flag cleared while an accepted match exists (legacy): Rider no longer sees the vehicle
select gwm_test.force_reg(4);
update public.matches set status = 'accepted' where id = gwm_test.mid(4, 5);
select gwm_test.as_user(gwm_test.uid(5));
select gwm_test.chk('H6 registered driver: matched Rider can see vehicle', (select count(*) from public.get_match_vehicle(gwm_test.mid(4, 5))) = 1);
select gwm_test.reset();
update public.profiles set driver_registered_at = null, licence_declared_at = null, licence_declaration_version = null, active_role = 'rider'
 where id = gwm_test.uid(4);
select gwm_test.as_user(gwm_test.uid(5));
select gwm_test.chk('H7 unregistered owner: retained vehicle NOT visible to the matched Rider (can_view_vehicle)',
  (select count(*) from public.get_match_vehicle(gwm_test.mid(4, 5))) = 0);
select gwm_test.reset();
update public.matches set boarded_at = now() where id = gwm_test.mid(4, 5);
select gwm_test.as_user(gwm_test.uid(5));
select gwm_test.chk('H9 Q-2 kept: a BOARDED Rider still sees the vehicle although the Driver is unregistered',
  (select count(*) from public.get_match_vehicle(gwm_test.mid(4, 5))) = 1);
select gwm_test.reset();
select gwm_test.as_user(gwm_test.uid(4));
select gwm_test.chk('H8 owner still sees own retained vehicle', (select count(*) from public.vehicles where user_id = gwm_test.uid(4)) = 1);
select gwm_test.reset();

-- ================= I. export + account deletion =============================================================
select gwm_test.force_reg(8);
select gwm_test.as_user(gwm_test.uid(8));
select gwm_test.expect_ok('I1 switch to driver mode', $q$select public.set_active_role('driver')$q$);
select gwm_test.chk('I2 export includes registration state, declaration time and version',
  (public.export_my_data() -> 'driver_registration' ->> 'registered') = 'true'
  and (public.export_my_data() -> 'driver_registration' ->> 'licence_declared_at') is not null
  and (public.export_my_data() -> 'driver_registration' ->> 'licence_declaration_version') = 'd1-draft'
  and (public.export_my_data() -> 'driver_registration' ->> 'active_role') = 'driver'
  and (public.export_my_data() -> 'vehicle' ->> 'plate') is not null);
select gwm_test.chk('I3 export profile section has no duplicate registration keys',
  not ((public.export_my_data() -> 'profile') ? 'licence_declared_at') and not ((public.export_my_data() -> 'profile') ? 'active_role'));
select gwm_test.reset();
select gwm_test.as_user(gwm_test.uid(3));
select gwm_test.chk('I4 export for an unregistered account: registered=false, nulls',
  (public.export_my_data() -> 'driver_registration' ->> 'registered') = 'false'
  and (public.export_my_data() -> 'driver_registration' ->> 'licence_declared_at') is null
  and (public.export_my_data() -> 'driver_registration' ->> 'active_role') = 'rider');
select gwm_test.expect_ok('I5 account 3 cancels its rider trip (cleanup for deletion test isolation)', $q$update public.trips set status = 'cancelled' where id = gwm_test.tid(3)$q$);
select gwm_test.reset();
select gwm_test.as_user(gwm_test.uid(8));
select gwm_test.expect_ok('I6 account deletion by a registered driver in driver mode (guard must not block the vehicle erasure)', $q$select public.request_account_deletion()$q$);
select gwm_test.reset();
select gwm_test.chk('I7 deletion erased registration, declaration (time + version), active role and the vehicle',
  (select deleted_at is not null and driver_registered_at is null and licence_declared_at is null
          and licence_declaration_version is null and active_role = 'rider' and not driver_registered
     from public.profiles where id = gwm_test.uid(8))
  and (select count(*) from public.vehicles where user_id = gwm_test.uid(8)) = 0);

-- ---- report ---------------------------------------------------------------------------------------
select gwm_test.reset();
select n, case when ok then 'PASS' else 'FAIL' end as result, label, detail from gwm_test.results order by n;
select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed from gwm_test.results;
do $$
begin
  if exists (select 1 from gwm_test.results where not ok) then
    raise exception 'Dual role (round 4) SQL tests FAILED: % check(s)', (select count(*) from gwm_test.results where not ok);
  end if;
end $$;
rollback;
