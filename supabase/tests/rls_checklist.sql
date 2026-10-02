-- =============================================================================
-- GOWITHME RLS / privacy checklist (docs/design-security.md s.8 items 1-10 + migration 0002 checks)
-- Run against a LOCAL database after migrations 0001 + 0002 (connect as the postgres superuser role):
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f supabase/tests/rls_checklist.sql
-- Everything runs in ONE transaction that is ROLLED BACK at the end (no data is left behind, seed data untouched).
-- Test data lives around Chiang Mai / Phuket so it never collides with supabase/seed.sql (Bangkok).
-- Exit code is non-zero if any check fails. WARN rows are informational (production gates).
-- =============================================================================
\set ON_ERROR_STOP on
begin;
set search_path = public, extensions;

-- ---- harness ---------------------------------------------------------------------------------
create schema gwm_test;
create table gwm_test.results (n serial primary key, label text, ok boolean, detail text);
create table gwm_test.vars (k text primary key, v text);
grant usage on schema gwm_test to public;
grant all on all tables in schema gwm_test to public;
grant all on all sequences in schema gwm_test to public;

create function gwm_test.chk(p_label text, p_ok boolean, p_detail text default null) returns void
language sql as $$ insert into gwm_test.results (label, ok, detail) values (p_label, coalesce(p_ok, false), p_detail) $$;

create function gwm_test.warn(p_label text, p_bad boolean, p_detail text default null) returns void
language sql as $$ insert into gwm_test.results (label, ok, detail)
                   values ('WARN ' || p_label, true, case when p_bad then 'ATTENTION: ' || coalesce(p_detail, '') else 'ok' end) $$;

create function gwm_test.setv(p_k text, p_v text) returns void
language sql as $$ insert into gwm_test.vars values (p_k, p_v) on conflict (k) do update set v = excluded.v $$;
create function gwm_test.getv(p_k text) returns text language sql as $$ select v from gwm_test.vars where k = p_k $$;

-- expected failure: passes when the statement raises an error whose message or SQLSTATE contains p_needle
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
create function gwm_test.as_anon() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('request.jwt.claim.sub', '', true);
  execute 'set local role anon';
end $$;
create function gwm_test.reset() returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
end $$;

-- p_confirmed=false => email NOT verified. Since 0003 handle_new_user REJECTS signups without 18+/current policy,
-- so p_adult=false / p_policy=false users are created valid and then stripped as the superuser (simulates a legacy row
-- and keeps the trips_guard second layer testable).
create function gwm_test.mkuser(p_id uuid, p_email text, p_adult boolean default true, p_policy boolean default true,
                                p_confirmed boolean default true) returns void language plpgsql as $$
begin
  insert into auth.users (instance_id, id, aud, role, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', p_id, 'authenticated', 'authenticated', p_email,
          case when p_confirmed then now() end, '{"provider":"email"}'::jsonb,
          jsonb_build_object('display_name', split_part(p_email, '@', 1), 'adult_confirmed', true,
                             'policy_version', public.cfg('policy.current_version') #>> '{}'),
          now(), now());
  if not p_adult  then update public.profiles set adult_confirmed_at = null where id = p_id; end if;
  if not p_policy then delete from public.consents where user_id = p_id; end if;
end $$;

create function gwm_test.trip_sql(p_id uuid, p_uid uuid, olng float8, olat float8, dlng float8, dlat float8,
                                  p_dep interval default interval '2 hours') returns text language sql as $$
  select format($f$insert into public.trips (id, user_id, mode, origin, dest, route, route_distance_m, route_duration_s, depart_at)
    values (%L, %L, 'walk', ST_SetSRID(ST_MakePoint(%s,%s),4326)::geography, ST_SetSRID(ST_MakePoint(%s,%s),4326)::geography,
            ST_MakeLine(ST_SetSRID(ST_MakePoint(%s,%s),4326), ST_SetSRID(ST_MakePoint(%s,%s),4326))::geography,
            3000, 1800, now() + %L::interval)$f$,
    p_id, p_uid, olng, olat, dlng, dlat, olng, olat, dlng, dlat, p_dep::text)
$$;
create function gwm_test.mktrip(p_id uuid, p_uid uuid, olng float8, olat float8, dlng float8, dlat float8) returns void
language plpgsql as $$ begin execute gwm_test.trip_sql(p_id, p_uid, olng, olat, dlng, dlat, interval '1 hour'); end $$;

-- ---- fixtures (as postgres) ---------------------------------------------------------------------
-- users: A,B,G = cluster X (Chiang Mai, mutually eligible); C = probe user far away; D,E = cluster Y (Phuket);
--        F = signed up WITHOUT 18+/policy metadata; H = no trip yet; I = unverified email
select gwm_test.mkuser('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'a@t.test');
select gwm_test.mkuser('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'b@t.test');
select gwm_test.mkuser('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'c@t.test');
select gwm_test.mkuser('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'd@t.test');
select gwm_test.mkuser('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'e@t.test');
select gwm_test.mkuser('ffffffff-ffff-4fff-8fff-ffffffffffff', 'f@t.test', false, false);
select gwm_test.mkuser('99999999-9999-4999-8999-999999999999', 'g@t.test');
select gwm_test.mkuser('88888888-8888-4888-8888-888888888888', 'h@t.test');
select gwm_test.mkuser('77777777-7777-4777-8777-777777777777', 'i@t.test', true, true, false);

insert into public.consents (user_id, kind, granted, policy_version)
select u, 'location', true, '1.0' from (values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid), ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid),
  ('dddddddd-dddd-4ddd-8ddd-dddddddddddd'::uuid), ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'::uuid)) v(u);

select gwm_test.mktrip('a0000000-0000-4000-8000-00000000000a', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 98.9853, 18.7883, 98.9500, 18.8000);
select gwm_test.mktrip('b0000000-0000-4000-8000-00000000000b', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 98.9863, 18.7888, 98.9510, 18.8005);
select gwm_test.mktrip('90000000-0000-4000-8000-000000000009', '99999999-9999-4999-8999-999999999999', 98.9858, 18.7885, 98.9505, 18.8002);
select gwm_test.mktrip('c0000000-0000-4000-8000-00000000000c', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 99.5000, 19.0000, 99.5500, 19.0500);
select gwm_test.mktrip('d0000000-0000-4000-8000-00000000000d', 'dddddddd-dddd-4ddd-8ddd-dddddddddddd', 98.3923, 7.8804, 98.3000, 7.9000);
select gwm_test.mktrip('e0000000-0000-4000-8000-00000000000e', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 98.3930, 7.8808, 98.3010, 7.9004);

select gwm_test.chk('setup: signup trigger created profile + email verification for A',
  (select count(*) from public.verifications where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' and kind = 'email' and status = 'verified') = 1);

-- ---- 1. isolation ---------------------------------------------------------------------------------
select gwm_test.as_user('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
select gwm_test.chk('1 B cannot read A trip', gwm_test.n($q$select count(*) from public.trips where id = 'a0000000-0000-4000-8000-00000000000a'$q$) = 0);
select gwm_test.chk('1 B sees only own trips', gwm_test.n('select count(*) from public.trips') = 1);
select gwm_test.reset();
select gwm_test.as_anon();
select gwm_test.expect_error('1 anon cannot select trips', 'select * from public.trips', '42501');
select gwm_test.expect_error('1 anon cannot select profiles', 'select * from public.profiles', '42501');
select gwm_test.reset();

-- ---- 2. find_matches privacy ------------------------------------------------------------------------
select gwm_test.as_user('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
select gwm_test.chk('2 find_matches returns B', gwm_test.n($q$select count(*) from public.find_matches('a0000000-0000-4000-8000-00000000000a') where trip_id = 'b0000000-0000-4000-8000-00000000000b'$q$) = 1);
select gwm_test.chk('2 distances are multiples of 500', gwm_test.n($q$select count(*) from public.find_matches('a0000000-0000-4000-8000-00000000000a') where approx_distance_m % 500 <> 0$q$) = 0);
select gwm_test.chk('2 no true origin coordinates leak', gwm_test.n($q$select count(*) from public.find_matches('a0000000-0000-4000-8000-00000000000a')
   where abs(approx_origin_lat - 18.7888) < 1e-9 and abs(approx_origin_lng - 98.9863) < 1e-9$q$) = 0);
select gwm_test.chk('2 deterministic (two calls identical)',
  (select jsonb_agg(to_jsonb(f) order by trip_id) from public.find_matches('a0000000-0000-4000-8000-00000000000a') f)
  = (select jsonb_agg(to_jsonb(f) order by trip_id) from public.find_matches('a0000000-0000-4000-8000-00000000000a') f));
select gwm_test.expect_error('2 find_matches on someone else trip denied', $q$select * from public.find_matches('b0000000-0000-4000-8000-00000000000b')$q$, 'GWM_TRIP_NOT_FOUND');
select gwm_test.reset();

-- ---- 3. probing caps + T3.18 throttle ----------------------------------------------------------------
select gwm_test.as_user('cccccccc-cccc-4ccc-8ccc-cccccccccccc');
select gwm_test.expect_ok('3 geometry edit #' || i,
  format($q$update public.trips set origin = ST_SetSRID(ST_MakePoint(99.5%s, 19.0), 4326)::geography where id = 'c0000000-0000-4000-8000-00000000000c'$q$, i))
  from generate_series(1, 3) i;
select gwm_test.expect_error('3 4th geometry edit raises GWM_TRIP_EDIT_LIMIT',
  $q$update public.trips set origin = ST_SetSRID(ST_MakePoint(99.504, 19.0), 4326)::geography where id = 'c0000000-0000-4000-8000-00000000000c'$q$, 'GWM_TRIP_EDIT_LIMIT');
select gwm_test.reset();

update public.app_config set value = '2'  where key = 'trip.max_per_day';
update public.app_config set value = '50' where key = 'trip.max_active';
select gwm_test.as_user('cccccccc-cccc-4ccc-8ccc-cccccccccccc');
select gwm_test.expect_ok('3 trip #2 within daily cap', gwm_test.trip_sql('c1000000-0000-4000-8000-000000000001', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 99.6, 19.0, 99.65, 19.05));
select gwm_test.expect_error('3 trip beyond daily cap raises GWM_TRIP_RATE_LIMIT',
  gwm_test.trip_sql('c1000000-0000-4000-8000-000000000002', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 99.7, 19.0, 99.75, 19.05), 'GWM_TRIP_RATE_LIMIT');
select gwm_test.reset();
update public.app_config set value = '10' where key = 'trip.max_per_day';
update public.app_config set value = '1'  where key = 'trip.max_active';

update public.app_config set value = '2' where key = 'throttle.find_matches_per_min';
select gwm_test.as_user('cccccccc-cccc-4ccc-8ccc-cccccccccccc');
select gwm_test.expect_ok('3b find_matches call 1', $q$select * from public.find_matches('c0000000-0000-4000-8000-00000000000c')$q$);
select gwm_test.expect_ok('3b find_matches call 2', $q$select * from public.find_matches('c0000000-0000-4000-8000-00000000000c')$q$);
select gwm_test.expect_error('3b find_matches call 3 throttled (GWM_RATE_LIMITED)', $q$select * from public.find_matches('c0000000-0000-4000-8000-00000000000c')$q$, 'GWM_RATE_LIMITED');
select gwm_test.reset();
update public.app_config set value = '30' where key = 'throttle.find_matches_per_min';

-- ---- F-9b consent + 18+ (T3.19), unverified email gate (T3.18), idempotent trip create (T3.17) --------------
select gwm_test.as_user('ffffffff-ffff-4fff-8fff-ffffffffffff');
select gwm_test.expect_error('F-9b trip without 18+ declaration rejected', gwm_test.trip_sql('f0000000-0000-4000-8000-00000000000f', 'ffffffff-ffff-4fff-8fff-ffffffffffff', 98.5, 18.5, 98.55, 18.55), 'GWM_ADULT_REQUIRED');
select gwm_test.reset();
update public.profiles set adult_confirmed_at = now() where id = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
select gwm_test.as_user('ffffffff-ffff-4fff-8fff-ffffffffffff');
select gwm_test.expect_error('F-9b trip without privacy_policy consent rejected', gwm_test.trip_sql('f0000000-0000-4000-8000-00000000000f', 'ffffffff-ffff-4fff-8fff-ffffffffffff', 98.5, 18.5, 98.55, 18.55), 'GWM_CONSENT_REQUIRED');
select gwm_test.reset();
insert into public.consents (user_id, kind, granted, policy_version) values ('ffffffff-ffff-4fff-8fff-ffffffffffff', 'privacy_policy', true, '1.0');
select gwm_test.as_user('ffffffff-ffff-4fff-8fff-ffffffffffff');
select gwm_test.expect_ok('F-9b trip allowed once 18+ and consent present', gwm_test.trip_sql('f0000000-0000-4000-8000-00000000000f', 'ffffffff-ffff-4fff-8fff-ffffffffffff', 98.5, 18.5, 98.55, 18.55));
select gwm_test.reset();

select gwm_test.as_user('88888888-8888-4888-8888-888888888888');
select gwm_test.expect_ok('T3.17 trip create with client id (1st)', gwm_test.trip_sql('81000000-0000-4000-8000-000000000001', '88888888-8888-4888-8888-888888888888', 98.4, 18.4, 98.45, 18.45));
select gwm_test.expect_ok('T3.17 trip create retry with same id is a no-op', gwm_test.trip_sql('81000000-0000-4000-8000-000000000001', '88888888-8888-4888-8888-888888888888', 98.4, 18.4, 98.45, 18.45));
select gwm_test.chk('T3.17 exactly one trip row after retry', gwm_test.n($q$select count(*) from public.trips where id = '81000000-0000-4000-8000-000000000001'$q$) = 1);
select gwm_test.reset();

select gwm_test.as_user('77777777-7777-4777-8777-777777777777');
select gwm_test.expect_error('T3.18 unverified email cannot request_match', $q$select public.request_match(gen_random_uuid(), gen_random_uuid())$q$, 'GWM_EMAIL_NOT_VERIFIED');
select gwm_test.reset();

-- ---- T3.17 SOS idempotency + timestamp guard ------------------------------------------------------------------
select gwm_test.as_user('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
select gwm_test.expect_ok('T3.17 sos insert 1', $q$insert into public.sos_events (id, user_id, source, note) values ('50000000-0000-4000-8000-000000000001', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'trip', 'x') on conflict (id) do nothing$q$);
select gwm_test.expect_ok('T3.17 sos insert retry (same id) ignored', $q$insert into public.sos_events (id, user_id, source, note) values ('50000000-0000-4000-8000-000000000001', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'trip', 'x') on conflict (id) do nothing$q$);
select gwm_test.chk('T3.17 sos stored once', gwm_test.n($q$select count(*) from public.sos_events where id = '50000000-0000-4000-8000-000000000001'$q$) = 1);
select gwm_test.expect_ok('T3.17 sos with ancient client timestamp accepted', $q$insert into public.sos_events (id, user_id, source, client_created_at) values ('50000000-0000-4000-8000-000000000002', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'trip', '2000-01-01')$q$);
select gwm_test.expect_ok('T3.17 sos with future client timestamp accepted', $q$insert into public.sos_events (id, user_id, source, client_created_at) values ('50000000-0000-4000-8000-000000000003', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'trip', '2100-01-01')$q$);
select gwm_test.chk('T3.17 out-of-range timestamps clamped to server time',
  gwm_test.n($q$select count(*) from public.sos_events where id in ('50000000-0000-4000-8000-000000000002','50000000-0000-4000-8000-000000000003')
                 and client_created_at between now() - interval '1 minute' and now() + interval '1 minute'$q$) = 2);
select gwm_test.reset();

-- ---- Match M1 (A -> B): idempotent request, pending cap, F-5, chat, meeting point, live location, F-11 ------------
select gwm_test.as_user('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
select gwm_test.setv('m1', public.request_match('a0000000-0000-4000-8000-00000000000a', 'b0000000-0000-4000-8000-00000000000b')::text);
select gwm_test.chk('T3.18 request_match retry returns SAME id', public.request_match('a0000000-0000-4000-8000-00000000000a', 'b0000000-0000-4000-8000-00000000000b')::text = gwm_test.getv('m1'));
select gwm_test.chk('T3.18 only one match row', gwm_test.n('select count(*) from public.matches') = 1);
select gwm_test.reset();

update public.app_config set value = '1' where key = 'match.max_pending_per_trip';
select gwm_test.as_user('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
select gwm_test.expect_error('F-10 pending cap raises GWM_PENDING_LIMIT', $q$select public.request_match('a0000000-0000-4000-8000-00000000000a', '90000000-0000-4000-8000-000000000009')$q$, 'GWM_PENDING_LIMIT');
select gwm_test.reset();
update public.app_config set value = '5' where key = 'match.max_pending_per_trip';

-- F-5: pending match freezes A's geometry/time; G (no match) may still edit
select gwm_test.as_user('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
select gwm_test.expect_error('F-5 depart_at edit blocked while request pending', $q$update public.trips set depart_at = depart_at + interval '1 minute' where id = 'a0000000-0000-4000-8000-00000000000a'$q$, 'GWM_TRIP_HAS_MATCHES');
select gwm_test.expect_error('F-5 origin edit blocked while request pending', $q$update public.trips set origin = ST_SetSRID(ST_MakePoint(98.9854, 18.7884), 4326)::geography where id = 'a0000000-0000-4000-8000-00000000000a'$q$, 'GWM_TRIP_HAS_MATCHES');
select gwm_test.expect_error('F-5 mode edit blocked while request pending (PM round 2)', $q$update public.trips set mode = case when mode = 'car' then 'walk'::public.travel_mode else 'car'::public.travel_mode end where id = 'a0000000-0000-4000-8000-00000000000a'$q$, 'GWM_TRIP_HAS_MATCHES');
select gwm_test.expect_error('chat insert on a PENDING match fails', $q$insert into public.chat_messages (match_id, sender_id, body) values (gwm_test.getv('m1')::uuid, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'hi')$q$, '42501');
select gwm_test.chk('T3.22 chat_state = match_closed while pending', public.chat_state(gwm_test.getv('m1')::uuid) = 'match_closed');
select gwm_test.reset();
select gwm_test.as_user('99999999-9999-4999-8999-999999999999');
select gwm_test.expect_ok('F-5 trip without matches can still be edited', $q$update public.trips set depart_at = depart_at + interval '1 minute' where id = '90000000-0000-4000-8000-000000000009'$q$);
select gwm_test.reset();

-- B accepts with a meeting point => becomes a PROPOSAL by B (P-2)
select gwm_test.as_user('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
select gwm_test.chk('respond_match accept', public.respond_match(gwm_test.getv('m1')::uuid, true, 98.97, 18.79, 'ป้ายรถเมล์') = 'accepted');
select gwm_test.chk('P-2 meeting point only PROPOSED after accept', gwm_test.n($q$select count(*) from public.matches where id = gwm_test.getv('m1')::uuid
   and meeting_point is null and meeting_proposed_point is not null and meeting_proposed_by = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'$q$) = 1);
select gwm_test.expect_error('P-2 proposer cannot confirm own proposal', format('select public.confirm_meeting_point(%L)', gwm_test.getv('m1')), 'GWM_OWN_PROPOSAL');
select gwm_test.reset();
select gwm_test.as_user('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
select gwm_test.expect_error('P-2 direct set_meeting_point no longer callable', format($q$select public.set_meeting_point(%L, 98.9, 18.8, 'x')$q$, gwm_test.getv('m1')), '42501');
select gwm_test.expect_error('P-2 invalid point rejected', format($q$select public.propose_meeting_point(%L, 98.9, 99.0, 'x')$q$, gwm_test.getv('m1')), 'GWM_INVALID_POINT');
select gwm_test.expect_ok('P-2 A confirms B proposal', format('select public.confirm_meeting_point(%L)', gwm_test.getv('m1')));
select gwm_test.chk('P-2 meeting point set + proposal cleared', gwm_test.n($q$select count(*) from public.matches where id = gwm_test.getv('m1')::uuid
   and meeting_point is not null and meeting_proposed_point is null$q$) = 1);
select gwm_test.expect_error('P-2 nothing left to confirm', format('select public.confirm_meeting_point(%L)', gwm_test.getv('m1')), 'GWM_NO_PROPOSAL');
select gwm_test.expect_ok('P-2 A can propose a new point', format($q$select public.propose_meeting_point(%L, 98.96, 18.80, 'จุดใหม่')$q$, gwm_test.getv('m1')));

-- chat: open => 10 messages OK, 11th rate limited
select gwm_test.chk('T3.22 chat_state = open', public.chat_state(gwm_test.getv('m1')::uuid) = 'open');
select gwm_test.expect_ok('chat insert on accepted match', format($q$insert into public.chat_messages (match_id, sender_id, body) values (%L, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'hello')$q$, gwm_test.getv('m1')));
select gwm_test.expect_ok('chat 9 more messages (10 total)', format($q$insert into public.chat_messages (match_id, sender_id, body)
   select %L, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'm' || g from generate_series(1, 9) g$q$, gwm_test.getv('m1')));
select gwm_test.expect_error('4 11th message in 10 s raises GWM_RATE_LIMITED', format($q$insert into public.chat_messages (match_id, sender_id, body) values (%L, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'spam')$q$, gwm_test.getv('m1')), 'GWM_RATE_LIMITED');
select gwm_test.reset();

-- 5. live location
select gwm_test.as_user('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
select gwm_test.chk('5 no partner location while own trip not in_progress', gwm_test.n(format('select count(*) from public.get_partner_live_location(%L)', gwm_test.getv('m1'))) = 0);
select gwm_test.expect_ok('A starts trip', $q$update public.trips set status = 'in_progress' where id = 'a0000000-0000-4000-8000-00000000000a'$q$);
select gwm_test.reset();
select gwm_test.as_user('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
select gwm_test.expect_ok('B starts trip', $q$update public.trips set status = 'in_progress' where id = 'b0000000-0000-4000-8000-00000000000b'$q$);
select gwm_test.expect_ok('B pushes location (RLS + consent)', $q$insert into public.trip_locations (trip_id, user_id, location, accuracy_m)
   values ('b0000000-0000-4000-8000-00000000000b', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', ST_SetSRID(ST_MakePoint(98.9600, 18.8000), 4326)::geography, 10)$q$);
select gwm_test.reset();
select gwm_test.as_user('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
select gwm_test.chk('5 partner location visible when both travelling and far from dest', gwm_test.n(format('select count(*) from public.get_partner_live_location(%L)', gwm_test.getv('m1'))) = 1);
select gwm_test.reset();
update public.trips set last_location = dest where id = 'b0000000-0000-4000-8000-00000000000b';
select gwm_test.as_user('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
select gwm_test.chk('5 partner location hidden within 500 m of destination', gwm_test.n(format('select count(*) from public.get_partner_live_location(%L)', gwm_test.getv('m1'))) = 0);
select gwm_test.reset();
select gwm_test.as_user('cccccccc-cccc-4ccc-8ccc-cccccccccccc');
select gwm_test.chk('5 outsider gets no location / chat_state not_found', gwm_test.n(format('select count(*) from public.get_partner_live_location(%L)', gwm_test.getv('m1'))) = 0
   and public.chat_state(gwm_test.getv('m1')::uuid) = 'not_found');
select gwm_test.reset();

-- F-11 / T3.20: A finishes; B keeps profile access <= 24h, loses it afterwards
select gwm_test.as_user('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
select gwm_test.expect_ok('A completes trip', $q$update public.trips set status = 'completed' where id = 'a0000000-0000-4000-8000-00000000000a'$q$);
select gwm_test.reset();
select gwm_test.as_user('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
select gwm_test.expect_error('4 chat insert after trip ended fails', format($q$insert into public.chat_messages (match_id, sender_id, body) values (%L, 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'late')$q$, gwm_test.getv('m1')), '42501');
select gwm_test.chk('T3.22 chat_state = trip_ended', public.chat_state(gwm_test.getv('m1')::uuid) = 'trip_ended');
select gwm_test.chk('chat history still readable (read-only)', gwm_test.n(format('select count(*) from public.chat_messages where match_id = %L', gwm_test.getv('m1'))) >= 10);
select gwm_test.chk('F-11 partner profile readable <= 24h after trip end', gwm_test.n($q$select count(*) from public.profiles where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$q$) = 1);
select gwm_test.reset();
update public.trips set ended_at = now() - interval '25 hours' where id = 'a0000000-0000-4000-8000-00000000000a';
select gwm_test.as_user('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
select gwm_test.chk('F-11 partner profile NOT readable > 24h after trip end', gwm_test.n($q$select count(*) from public.profiles where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$q$) = 0);
select gwm_test.chk('F-11 partner verifications NOT readable > 24h', gwm_test.n($q$select count(*) from public.verifications where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$q$) = 0);
select gwm_test.reset();

-- ---- Match M2 (D -> E): P-10 block => read-only chat + live location stops, match stays --------------------------
select gwm_test.as_user('dddddddd-dddd-4ddd-8ddd-dddddddddddd');
select gwm_test.setv('m2', public.request_match('d0000000-0000-4000-8000-00000000000d', 'e0000000-0000-4000-8000-00000000000e')::text);
select gwm_test.reset();
select gwm_test.as_user('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
select gwm_test.chk('M2 accepted', public.respond_match(gwm_test.getv('m2')::uuid, true) = 'accepted');
select gwm_test.expect_ok('E starts trip', $q$update public.trips set status = 'in_progress' where id = 'e0000000-0000-4000-8000-00000000000e'$q$);
select gwm_test.expect_ok('E pushes location', $q$insert into public.trip_locations (trip_id, user_id, location, accuracy_m)
   values ('e0000000-0000-4000-8000-00000000000e', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', ST_SetSRID(ST_MakePoint(98.3500, 7.8900), 4326)::geography, 10)$q$);
select gwm_test.reset();
select gwm_test.as_user('dddddddd-dddd-4ddd-8ddd-dddddddddddd');
select gwm_test.expect_ok('D starts trip', $q$update public.trips set status = 'in_progress' where id = 'd0000000-0000-4000-8000-00000000000d'$q$);
select gwm_test.chk('P-10 before block: live location visible', gwm_test.n(format('select count(*) from public.get_partner_live_location(%L)', gwm_test.getv('m2'))) = 1);
select gwm_test.expect_ok('D blocks E', $q$insert into public.blocks (blocker_id, blocked_id) values ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee')$q$);
select gwm_test.chk('P-10 blocker: live location stops', gwm_test.n(format('select count(*) from public.get_partner_live_location(%L)', gwm_test.getv('m2'))) = 0);
select gwm_test.expect_error('4 chat insert after block fails (blocker)', format($q$insert into public.chat_messages (match_id, sender_id, body) values (%L, 'dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'x')$q$, gwm_test.getv('m2')), '42501');
select gwm_test.chk('P-10 chat still readable by blocker', gwm_test.n(format('select count(*) from public.chat_messages where match_id = %L', gwm_test.getv('m2'))) >= 1);
select gwm_test.chk('P-10 match stays accepted after block', gwm_test.n(format($q$select count(*) from public.matches where id = %L and status = 'accepted'$q$, gwm_test.getv('m2'))) = 1);
select gwm_test.chk('T3.22 chat_state = blocked', public.chat_state(gwm_test.getv('m2')::uuid) = 'blocked');
select gwm_test.reset();
select gwm_test.as_user('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
select gwm_test.chk('P-10 blocked user: live location stops', gwm_test.n(format('select count(*) from public.get_partner_live_location(%L)', gwm_test.getv('m2'))) = 0);
select gwm_test.expect_error('4 chat insert after block fails (blocked)', format($q$insert into public.chat_messages (match_id, sender_id, body) values (%L, 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'x')$q$, gwm_test.getv('m2')), '42501');
select gwm_test.chk('P-10 chat still readable by blocked user', gwm_test.n(format('select count(*) from public.chat_messages where match_id = %L', gwm_test.getv('m2'))) >= 1);
select gwm_test.reset();
select gwm_test.as_user('dddddddd-dddd-4ddd-8ddd-dddddddddddd');
select gwm_test.expect_ok('P-10 blocker can cancel the match themself', format('select public.cancel_match(%L)', gwm_test.getv('m2')));
select gwm_test.reset();

-- ---- 6. consents / reports / avatar ------------------------------------------------------------------------------
select gwm_test.as_user('cccccccc-cccc-4ccc-8ccc-cccccccccccc');
select gwm_test.expect_error('6 consents insert with created_at denied', $q$insert into public.consents (user_id, kind, granted, policy_version, created_at)
   values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'location', true, '1.0', now() + interval '1 day')$q$, '42501');
select gwm_test.expect_error('6 report citing foreign match_id denied', format($q$insert into public.reports (reporter_id, reported_user_id, match_id, reason)
   values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', %L, 'spam')$q$, gwm_test.getv('m1')), '42501');
select gwm_test.reset();
select gwm_test.as_user('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
select gwm_test.expect_error('6 avatar_path pointing at another user rejected', $q$update public.profiles set avatar_path = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/x.jpg' where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$q$, 'GWM_AVATAR_INVALID');
select gwm_test.reset();

-- ---- 7. shared trip -------------------------------------------------------------------------------------------------
select gwm_test.as_user('cccccccc-cccc-4ccc-8ccc-cccccccccccc');
select gwm_test.setv('tok', token), gwm_test.setv('sid', share_id::text)
  from public.create_trip_share('c0000000-0000-4000-8000-00000000000c', 60);
select gwm_test.reset();
select gwm_test.as_anon();
select gwm_test.chk('7 valid token: 1 row, no location while trip not in_progress',
  gwm_test.n($q$select count(*) from public.get_shared_trip(gwm_test.getv('tok')) where last_lat is null and last_lng is null$q$) = 1);
select gwm_test.chk('7 valid token: no origin/email/phone fields',
  not exists (select 1 from public.get_shared_trip(gwm_test.getv('tok')) g where to_jsonb(g) ?| array['origin','origin_lat','origin_lng','email','phone']));
select gwm_test.chk('7 wrong token: 0 rows', gwm_test.n($q$select count(*) from public.get_shared_trip(repeat('x', 64))$q$) = 0);
select gwm_test.reset();
select gwm_test.as_user('cccccccc-cccc-4ccc-8ccc-cccccccccccc');
select gwm_test.expect_ok('7 revoke share', format('select public.revoke_trip_share(%L)', gwm_test.getv('sid')));
select gwm_test.reset();
select gwm_test.as_anon();
select gwm_test.chk('7 revoked token: 0 rows', gwm_test.n($q$select count(*) from public.get_shared_trip(gwm_test.getv('tok'))$q$) = 0);
select gwm_test.reset();
select gwm_test.as_user('cccccccc-cccc-4ccc-8ccc-cccccccccccc');
select gwm_test.setv('tok2', token) from public.create_trip_share('c0000000-0000-4000-8000-00000000000c', 60);
select gwm_test.reset();
update public.trip_shares set expires_at = now() - interval '1 second' where user_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc' and revoked_at is null;
select gwm_test.as_anon();
select gwm_test.chk('7 expired token: 0 rows', gwm_test.n($q$select count(*) from public.get_shared_trip(gwm_test.getv('tok2'))$q$) = 0);
select gwm_test.reset();

-- ---- 8. column grants + state machine (T3.22: same-status PATCH is a harmless no-op) ---------------------------------------
select gwm_test.as_user('99999999-9999-4999-8999-999999999999');
select gwm_test.expect_error('8 update last_location denied', $q$update public.trips set last_location = origin where id = '90000000-0000-4000-8000-000000000009'$q$, '42501');
select gwm_test.expect_error('8 update started_at denied', $q$update public.trips set started_at = now() where id = '90000000-0000-4000-8000-000000000009'$q$, '42501');
select gwm_test.expect_error('8 scheduled -> completed rejected', $q$update public.trips set status = 'completed' where id = '90000000-0000-4000-8000-000000000009'$q$, 'GWM_INVALID_TRIP_TRANSITION');
select gwm_test.expect_ok('T3.22 PATCH status to the same value is a no-op', $q$update public.trips set status = 'scheduled' where id = '90000000-0000-4000-8000-000000000009'$q$);
select gwm_test.chk('T3.22 status unchanged after no-op PATCH', gwm_test.n($q$select count(*) from public.trips where id = '90000000-0000-4000-8000-000000000009' and status = 'scheduled' and started_at is null and ended_at is null$q$) = 1);
select gwm_test.reset();

-- ---- 9. config secrecy + T3.21 public keys -------------------------------------------------------------------------------
select gwm_test.as_user('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
select gwm_test.expect_error('9 cfg() not callable by authenticated', $q$select public.cfg('phone.mock_code')$q$, '42501');
select gwm_test.chk('9 non-public config hidden', gwm_test.n($q$select count(*) from public.app_config where key = 'phone.mock_enabled'$q$) = 0);
select gwm_test.chk('T3.21 public keys readable (client.min_version, share.web_base_url, match.max_pending_per_trip)',
  gwm_test.n($q$select count(*) from public.app_config where key in ('client.min_version','share.web_base_url','match.max_pending_per_trip')$q$) = 3);
select gwm_test.expect_error('T3.18 api_throttle not readable by clients', 'select * from public.api_throttle', '42501');
select gwm_test.reset();

-- ---- T3.21 role settings + F-15 SOS coarsening -------------------------------------------------------------------------------
select gwm_test.chk('T3.21 statement_timeout set on role authenticated',
  exists (select 1 from pg_roles where rolname = 'authenticated' and rolconfig::text ilike '%statement_timeout%'));

insert into public.sos_events (id, user_id, source, location, created_at)
values ('50000000-0000-4000-8000-0000000000f0', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'trip',
        ST_SetSRID(ST_MakePoint(98.98531, 18.78831), 4326)::geography, now() - interval '91 days');
select public.purge_expired_data();
select gwm_test.chk('F-15 SOS older than 90 d is blurred',
  (select precision_reduced_at is not null and abs(ST_X(location::geometry) - 98.98531) > 1e-7
     from public.sos_events where id = '50000000-0000-4000-8000-0000000000f0'));
select gwm_test.chk('F-15 recent SOS stays precise', gwm_test.n($q$select count(*) from public.sos_events
   where id = '50000000-0000-4000-8000-000000000001' and precision_reduced_at is null$q$) = 1);

-- ---- 10. production gates (informational; the real gate is the prod project config) -------------------------------------------------
select gwm_test.warn('10 phone.mock_enabled must be false in production', public.cfg_bool('phone.mock_enabled'), 'currently TRUE (ok for dev only)');
select gwm_test.warn('10 auth.require_verified_email should be true', not public.cfg_bool('auth.require_verified_email'), 'currently FALSE');
select gwm_test.chk('10 realtime publication contains only chat_messages + matches',
  case when exists (select 1 from pg_publication where pubname = 'supabase_realtime')
       then coalesce((select array_agg(tablename::text order by tablename) from pg_publication_tables
                       where pubname = 'supabase_realtime' and schemaname = 'public'), '{}') = array['chat_messages','matches']
       else true end);

-- ---- report -----------------------------------------------------------------------------------------------------------------------
select gwm_test.reset();
select n, case when ok then 'PASS' else 'FAIL' end as result, label, detail from gwm_test.results order by n;
select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed from gwm_test.results;
do $$
begin
  if exists (select 1 from gwm_test.results where not ok) then
    raise exception 'RLS checklist FAILED: % check(s)', (select count(*) from gwm_test.results where not ok);
  end if;
end $$;
rollback;
