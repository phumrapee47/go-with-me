-- =============================================================================
-- GOWITHME automated SQL tests for QA round 1 (T5.11 signup validation, T5.12 account deletion, T5.14 expiry filter,
-- T5.15 matching formula / blur / organisation domain). Run after migrations 0001-0003 (as the postgres superuser role):
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f supabase/tests/qa_round1.sql
-- One transaction, ROLLED BACK at the end. Uses Khon Kaen coordinates so it cannot collide with seed.sql / rls_checklist.sql.
-- Prints PASS/FAIL rows and exits non-zero on any FAIL (CI job: .github/workflows/ci.yml).
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

-- =============================================================================
-- T5.11 handle_new_user: reject signup without 18+ / current policy; server-set timestamps; client grants
-- =============================================================================
select gwm_test.chk('T5.11 config policy.current_version exists', public.cfg('policy.current_version') is not null);

select gwm_test.expect_error('T5.11a signup without adult_confirmed rejected',
  $q$select gwm_test.signup(1, null, '{"adult_confirmed": null}')$q$, 'GWM_ADULT_REQUIRED');
select gwm_test.expect_error('T5.11a signup with adult_confirmed=false rejected',
  $q$select gwm_test.signup(1, null, '{"adult_confirmed": false}')$q$, 'GWM_ADULT_REQUIRED');
select gwm_test.expect_error('T5.11a signup with adult_confirmed="yes" (not true) rejected',
  $q$select gwm_test.signup(1, null, '{"adult_confirmed": "yes"}')$q$, 'GWM_ADULT_REQUIRED');
select gwm_test.expect_error('T5.11b signup without policy_version rejected',
  $q$select gwm_test.signup(1, null, '{"policy_version": null}')$q$, 'GWM_CONSENT_REQUIRED');
select gwm_test.expect_error('T5.11b signup with blank policy_version rejected',
  $q$select gwm_test.signup(1, null, '{"policy_version": "  "}')$q$, 'GWM_CONSENT_REQUIRED');
select gwm_test.expect_error('T5.11b signup with a stale/unknown policy_version rejected',
  $q$select gwm_test.signup(1, null, '{"policy_version": "0.0-old"}')$q$, 'GWM_CONSENT_REQUIRED');
select gwm_test.chk('T5.11 rejected signups leave no auth user and no profile',
  gwm_test.n($q$select count(*) from auth.users where id = gwm_test.uid(1)$q$) = 0
  and gwm_test.n($q$select count(*) from public.profiles where id = gwm_test.uid(1)$q$) = 0);

-- (c) valid signup; forged timestamps in metadata are ignored (time comes from the server)
select gwm_test.signup(2, null, '{"adult_confirmed_at": "2001-01-01T00:00:00Z", "created_at": "2001-01-01T00:00:00Z"}');
select gwm_test.chk('T5.11c profile created with server time (now()), metadata time ignored',
  (select adult_confirmed_at = now() from public.profiles where id = gwm_test.uid(2)));
select gwm_test.chk('T5.11c privacy_policy + terms consents created with the current version and server time',
  gwm_test.n($q$select count(*) from public.consents where user_id = gwm_test.uid(2) and kind in ('privacy_policy','terms')
     and granted and policy_version = public.cfg('policy.current_version') #>> '{}' and created_at = now()$q$) = 2);

-- (d) authenticated clients cannot change 18+ time or write consents directly
select gwm_test.as_user(gwm_test.uid(2));
select gwm_test.expect_error('T5.11d authenticated cannot update adult_confirmed_at',
  format($q$update public.profiles set adult_confirmed_at = '2001-01-01' where id = %L$q$, gwm_test.uid(2)), '42501');
select gwm_test.expect_error('T5.11d authenticated cannot insert consents directly',
  format($q$insert into public.consents (user_id, kind, granted, policy_version) values (%L, 'privacy_policy', true, 'x')$q$, gwm_test.uid(2)), '42501');
select gwm_test.expect_ok('T5.11d authenticated can still update display_name',
  format($q$update public.profiles set display_name = 'renamed' where id = %L$q$, gwm_test.uid(2)));
select gwm_test.expect_ok('T5.11d record_consent RPC still works', $q$select public.record_consent('location', true, '0.1-draft')$q$);
select gwm_test.reset();

-- =============================================================================
-- T5.12 account deletion: banned, sessions revoked, data cancelled
-- =============================================================================
select gwm_test.signup(3);
select gwm_test.trip(3, 102.8300, 16.4400, 102.8000, 16.4600);
do $$
begin
  insert into auth.sessions (id, user_id, created_at, updated_at) values (gen_random_uuid(), gwm_test.uid(3), now(), now());
exception when others then
  raise notice 'auth.sessions insert skipped on this GoTrue version: %', sqlerrm;
end $$;
select gwm_test.as_user(gwm_test.uid(3));
select gwm_test.expect_ok('T5.12 request_account_deletion succeeds', 'select public.request_account_deletion()');
select gwm_test.reset();
select gwm_test.chk('T5.12 auth user is banned far into the future (cannot sign in / refresh)',
  (select banned_until > now() + interval '50 years' from auth.users where id = gwm_test.uid(3)));
select gwm_test.chk('T5.12 no sessions remain', gwm_test.n($q$select count(*) from auth.sessions where user_id = gwm_test.uid(3)$q$) = 0);
select gwm_test.chk('T5.12 profile flagged deleted + anonymised',
  (select deleted_at is not null and display_name <> 'user3' from public.profiles where id = gwm_test.uid(3)));
select gwm_test.chk('T5.12 trips cancelled and soft-deleted',
  (select status = 'cancelled' and deleted_at is not null from public.trips where id = gwm_test.tid(3)));
select gwm_test.chk('T5.12 other users are not banned',
  (select banned_until is null from auth.users where id = gwm_test.uid(2)));

-- =============================================================================
-- T5.14 + T5.15 match_candidates: formula, filters, expiry edge cases
--   base trip: origin (102.8300,16.4400) -> dest (102.8000,16.4600). 0.0009 deg lat ~ 100 m; 0.009 ~ 1 km; 0.03 ~ 3.3 km.
--   config used: origin/dest radius 2000 m, window 30 min, min overlap 40 %, route buffer 200 m, expire_after 120 min.
-- =============================================================================
update public.app_config set value = '120' where key = 'trip.expire_after_min';
update public.app_config set value = '10' where key = 'trip.max_per_day';

select gwm_test.signup(n) from generate_series(10, 30) n;
-- requester R = 10 departs in 60 min
select gwm_test.trip(10, 102.8300, 16.4400, 102.8000, 16.4600, interval '60 minutes');
select gwm_test.trip(11, 102.8300, 16.4400, 102.8000, 16.4600, interval '60 minutes');   -- identical trip, same time
select gwm_test.trip(12, 102.8300, 16.4409, 102.8000, 16.4609, interval '75 minutes');   -- ~100 m off, +15 min
select gwm_test.trip(13, 102.8300, 16.4700, 102.8000, 16.4600, interval '60 minutes');   -- origin ~3.3 km away
select gwm_test.trip(14, 102.8300, 16.4400, 102.8000, 16.4900, interval '60 minutes');   -- destination ~3.3 km away
select gwm_test.trip(15, 102.8300, 16.4400, 102.8000, 16.4600, interval '100 minutes');  -- +40 min: outside window
select gwm_test.trip(16, 102.8300, 16.4400, 102.8000, 16.4600, interval '89 minutes');   -- +29 min: inside window
select gwm_test.trip(17, 102.8300, 16.4490, 102.8000, 16.4690, interval '60 minutes');   -- parallel 1 km away: overlap 0
select gwm_test.trip(18, 102.8300, 16.4400, 102.8000, 16.4600, interval '60 minutes');   -- different mode
update public.trips set mode = 'car' where id = gwm_test.tid(18);
select gwm_test.trip(19, 102.8300, 16.4400, 102.8000, 16.4600, interval '60 minutes');   -- blocked by R
insert into public.blocks (blocker_id, blocked_id) values (gwm_test.uid(10), gwm_test.uid(19));
select gwm_test.trip(20, 102.8300, 16.4400, 102.8000, 16.4600, interval '60 minutes');   -- owner deleted
update public.profiles set deleted_at = now() where id = gwm_test.uid(20);

select gwm_test.chk('formula: identical trip is eligible', gwm_test.cand_count(10, 11) = 1);
select gwm_test.chk('formula: identical trip / same time scores 100',
  (select abs(score - 100.0) < 0.001 from public.match_candidates(gwm_test.tid(10)) where candidate_trip_id = gwm_test.tid(11)));
select gwm_test.chk('formula: near trip (+100 m, +15 min) eligible', gwm_test.cand_count(10, 12) = 1);
select gwm_test.chk('formula: origin > radius excluded', gwm_test.cand_count(10, 13) = 0);
select gwm_test.chk('formula: destination > radius excluded', gwm_test.cand_count(10, 14) = 0);
select gwm_test.chk('formula: +40 min excluded, +29 min included', gwm_test.cand_count(10, 15) = 0 and gwm_test.cand_count(10, 16) = 1);
select gwm_test.chk('formula: overlap below 40 % excluded (parallel route 1 km away)', gwm_test.cand_count(10, 17) = 0);
select gwm_test.chk('formula: incompatible mode excluded', gwm_test.cand_count(10, 18) = 0);
select gwm_test.chk('formula: blocked user excluded (either direction)', gwm_test.cand_count(10, 19) = 0 and gwm_test.cand_count(19, 10) = 0);
select gwm_test.chk('formula: deleted owner excluded', gwm_test.cand_count(10, 20) = 0);
select gwm_test.chk('formula: never returns the requester own trip', gwm_test.cand_count(10, 10) = 0);
select gwm_test.chk('formula: closer + same time scores higher than farther + later',
  (select a.score > b.score from public.match_candidates(gwm_test.tid(10)) a, public.match_candidates(gwm_test.tid(10)) b
    where a.candidate_trip_id = gwm_test.tid(11) and b.candidate_trip_id = gwm_test.tid(12)));
select gwm_test.chk('formula: scores are within 0..100',
  gwm_test.n($q$select count(*) from public.match_candidates(gwm_test.tid(10)) where score < 0 or score > 100$q$) = 0);
select gwm_test.chk('formula: deterministic (two calls give identical rows in identical order)',
  (select jsonb_agg(to_jsonb(m)) from public.match_candidates(gwm_test.tid(10)) m)
  = (select jsonb_agg(to_jsonb(m)) from public.match_candidates(gwm_test.tid(10)) m));
select gwm_test.chk('formula: order is score desc',
  (select coalesce(bool_and(score <= prev), true) from (
     select score, lag(score) over () as prev from public.match_candidates(gwm_test.tid(10))) s where prev is not null));

-- ---- T5.14 expiry edge cases (requester R2 = 21 departed 110 min ago, so the window is still centred on "now") -----------
select gwm_test.trip(21, 102.8300, 16.4400, 102.8000, 16.4600, interval '-110 minutes');
select gwm_test.trip(22, 102.8300, 16.4400, 102.8000, 16.4600, interval '-119 minutes');  -- 1 min before expiry: still shown
select gwm_test.trip(23, 102.8300, 16.4400, 102.8000, 16.4600, interval '-121 minutes');  -- just expired, cron has NOT run
select gwm_test.trip(24, 102.8300, 16.4400, 102.8000, 16.4600, interval '-100 minutes');  -- not expired
select gwm_test.chk('T5.14 status is still scheduled for the just-expired trip (cron did not run)',
  (select status = 'scheduled' from public.trips where id = gwm_test.tid(23)));
select gwm_test.chk('T5.14 candidate 121 min past departure is filtered by the query itself', gwm_test.cand_count(21, 23) = 0);
select gwm_test.chk('T5.14 candidate 119 min past departure is still returned', gwm_test.cand_count(21, 22) = 1);
select gwm_test.chk('T5.14 candidate 100 min past departure is returned', gwm_test.cand_count(21, 24) = 1);
select gwm_test.chk('T5.14 an expired requester trip gets no candidates at all',
  gwm_test.n($q$select count(*) from public.match_candidates(gwm_test.tid(23))$q$) = 0);
update public.app_config set value = '180' where key = 'trip.expire_after_min';
select gwm_test.chk('T5.14 config 180 min: 121 min-old trip is candidate again', gwm_test.cand_count(21, 23) = 1);
update public.app_config set value = '120' where key = 'trip.expire_after_min';

-- =============================================================================
-- T5.15 blur_point (privacy.blur_cell_m = 1000): deterministic, bounded error, cell-stable, not reversible by averaging
-- =============================================================================
select gwm_test.chk('blur: null in, null out', public.blur_point(null) is null);
select gwm_test.chk('blur: deterministic',
  public.blur_point(ST_SetSRID(ST_MakePoint(102.8312, 16.4437), 4326)::geography)
  = public.blur_point(ST_SetSRID(ST_MakePoint(102.8312, 16.4437), 4326)::geography));
select gwm_test.chk('blur: idempotent (blurring a blurred point changes nothing)',
  ST_Distance(public.blur_point(public.blur_point(ST_SetSRID(ST_MakePoint(102.8312, 16.4437), 4326)::geography)),
              public.blur_point(ST_SetSRID(ST_MakePoint(102.8312, 16.4437), 4326)::geography)) < 0.01);
select gwm_test.chk('blur: error stays within half a cell diagonal (~708 m) for 400 points across latitudes',
  (select bool_and(ST_Distance(p, public.blur_point(p)) <= 720)
     from (select ST_SetSRID(ST_MakePoint(95 + (i % 20) * 0.37 + i * 0.00031, 6 + (i % 20) * 0.9 + i * 0.00017), 4326)::geography p
             from generate_series(1, 400) i) s));
select gwm_test.chk('blur: points in the same cell collapse to the same output (repeat queries cannot average out)',
  (with c as (select public.blur_point(ST_SetSRID(ST_MakePoint(102.8312, 16.4437), 4326)::geography) b)
   select ST_Distance(public.blur_point(ST_Project(c.b, 60, 45)), c.b) < 0.01
      and ST_Distance(public.blur_point(ST_Project(c.b, 60, 225)), c.b) < 0.01 from c));
select gwm_test.chk('blur: a point is generally moved (>= 1 m) unless it sits on the cell centre',
  (select count(*) filter (where ST_Distance(p, public.blur_point(p)) >= 1) >= 350
     from (select ST_SetSRID(ST_MakePoint(102.8 + i * 0.00123, 16.4 + i * 0.00087), 4326)::geography p
             from generate_series(1, 400) i) s));
select gwm_test.chk('blur: custom 500 m cell halves the error bound (<= 360 m)',
  (select bool_and(ST_Distance(p, public.blur_point(p, 500)) <= 360)
     from (select ST_SetSRID(ST_MakePoint(102.8 + i * 0.00123, 16.4 + i * 0.00087), 4326)::geography p
             from generate_series(1, 200) i) s));

-- find_matches (client-facing) exposes only blurred coordinates / bucketed distance
create table gwm_test.fm (trip_id uuid, approx_origin_lat double precision, approx_origin_lng double precision, approx_distance_m int);
grant all on gwm_test.fm to public;
select gwm_test.as_user(gwm_test.uid(10));
insert into gwm_test.fm
  select trip_id, approx_origin_lat, approx_origin_lng, approx_distance_m from public.find_matches(gwm_test.tid(10));
select gwm_test.reset();
select gwm_test.chk('blur: find_matches returns candidates', (select count(*) from gwm_test.fm) >= 2);
select gwm_test.chk('blur: find_matches never returns the true candidate origin, and stays within ~708 m of it',
  (select bool_and(ST_Distance(ST_SetSRID(ST_MakePoint(f.approx_origin_lng, f.approx_origin_lat), 4326)::geography, t.origin) <= 720
                   and ST_Distance(ST_SetSRID(ST_MakePoint(f.approx_origin_lng, f.approx_origin_lat), 4326)::geography, t.origin) > 0)
     from gwm_test.fm f join public.trips t on t.id = f.trip_id));
select gwm_test.chk('blur: approx_distance_m is bucketed to 500 m', (select bool_and(approx_distance_m % 500 = 0) from gwm_test.fm));

-- =============================================================================
-- T5.15 organisation domain (suffix / subdomain / alias aware)
-- =============================================================================
insert into public.org_domains (suffix, org_name) values ('uni.ac.th', 'Uni University'), ('example.edu', 'Example College')
on conflict (suffix) do nothing;
select gwm_test.signup(40, 'a@chula.ac.th');
select gwm_test.signup(41, 'b@mail.chula.ac.th');
select gwm_test.signup(42, 'c@evilac.th');
select gwm_test.signup(43, 'd@ac.th.evil.com');
select gwm_test.signup(44, 'E@CHULA.AC.TH');
select gwm_test.signup(45, 'f@gmail.com');
select gwm_test.signup(46, 'g@cs.uni.ac.th');
select gwm_test.signup(47, 'h@chula.ac.th', '{}', false);         -- email NOT confirmed
select gwm_test.signup(48, 'i@ac.th');                           -- bare suffix
select gwm_test.signup(49, 'j@fakeuni.ac.th');                   -- different label ending in a listed suffix
select gwm_test.signup(50, 'k@example.edu');
update public.org_domains set is_active = false where suffix = 'example.edu';
select gwm_test.signup(51, 'l@example.edu');

create function gwm_test.org(p_n int) returns text language sql as
$$ select org_suffix from public.verifications where user_id = gwm_test.uid(p_n) and kind = 'organization' and status = 'verified' $$;

select gwm_test.chk('org: x@chula.ac.th -> ac.th', gwm_test.org(40) = 'ac.th');
select gwm_test.chk('org: subdomain mail.chula.ac.th -> ac.th', gwm_test.org(41) = 'ac.th');
select gwm_test.chk('org: lookalike evilac.th is NOT verified', gwm_test.org(42) is null);
select gwm_test.chk('org: ac.th.evil.com is NOT verified', gwm_test.org(43) is null);
select gwm_test.chk('org: upper-case address is matched case-insensitively', gwm_test.org(44) = 'ac.th');
select gwm_test.chk('org: gmail.com gets the email badge only',
  gwm_test.org(45) is null and gwm_test.n($q$select count(*) from public.verifications where user_id = gwm_test.uid(45) and kind = 'email' and status = 'verified'$q$) = 1);
select gwm_test.chk('org: the most specific suffix wins (cs.uni.ac.th -> uni.ac.th)', gwm_test.org(46) = 'uni.ac.th');
select gwm_test.chk('org: unconfirmed email gets no badge at all',
  gwm_test.n($q$select count(*) from public.verifications where user_id = gwm_test.uid(47) and status = 'verified'$q$) = 0);
select gwm_test.chk('org: bare suffix domain ac.th matches', gwm_test.org(48) = 'ac.th');
select gwm_test.chk('org: fakeuni.ac.th matches ac.th but not uni.ac.th', gwm_test.org(49) = 'ac.th');
select gwm_test.chk('org: active custom suffix example.edu verified', gwm_test.org(50) = 'example.edu');
select gwm_test.chk('org: inactive suffix is ignored', gwm_test.org(51) is null);
select public.sync_user_verifications(gwm_test.uid(40), 'a@chula.ac.th', null);
select gwm_test.chk('org: losing email confirmation revokes email + organization',
  gwm_test.n($q$select count(*) from public.verifications where user_id = gwm_test.uid(40) and status = 'verified'$q$) = 0);
select gwm_test.chk('org: user_badges exposes the organisation name',
  (select public.user_badges(gwm_test.uid(41)) @> '[{"kind":"organization","org_name":"สถาบันการศึกษา (.ac.th)"}]'::jsonb));

-- ---- report ---------------------------------------------------------------------------------------
select gwm_test.reset();
select n, case when ok then 'PASS' else 'FAIL' end as result, label, detail from gwm_test.results order by n;
select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed from gwm_test.results;
do $$
begin
  if exists (select 1 from gwm_test.results where not ok) then
    raise exception 'QA round 1 SQL tests FAILED: % check(s)', (select count(*) from gwm_test.results where not ok);
  end if;
end $$;
rollback;
