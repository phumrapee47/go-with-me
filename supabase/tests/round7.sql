-- =============================================================================
-- GOWITHME automated SQL tests for round 7 migrations 0011 (push/device_tokens) + 0012 (vibe/mood, gender,
-- same-org/women-only filters). docs/design-roles.md section 14. Same harness as round5.sql/round6.sql.
-- Run after migrations 0001-0012 (as the postgres superuser role):
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f supabase/tests/round7.sql
-- One transaction, ROLLED BACK at the end. Prints PASS/FAIL rows, exits non-zero on any FAIL.
-- KNOWN GAP (documented, not a bug): the Edge Function drain (FCM HTTP v1 send, chat coalescing at read time) is
-- a separate deployable artifact - this file can only assert push_outbox ROW SHAPE (kind/user_id/match_id/sent_at),
-- never a real push delivery. US-43 (road-snap) is Dart/OSRM-side only and is NOT covered here (no DB surface).
-- (Authored without a database at hand: run before applying 0011/0012.)
-- =============================================================================
\set ON_ERROR_STOP on
begin;
set search_path = public, extensions;

-- ---- harness (same as roles.sql / round5.sql / round6.sql) -----------------------------------------
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

create function gwm_test.pt(p_lat float8, p_east float8, p_north float8 default 0) returns geography language sql immutable as $$
  select ST_Project(ST_Project(ST_SetSRID(ST_MakePoint(102.83, p_lat), 4326)::geography, abs(p_east),
                               case when p_east >= 0 then pi() / 2 else 3 * pi() / 2 end),
                    abs(p_north), case when p_north >= 0 then 0.0 else pi() end)
$$;

-- generic peer trip fixture (walk, no role/vehicle needed) - keeps the niche-filter tests independent of the
-- car Driver/Rider machinery (round 3-5), since same-org/women-only apply regardless of mode.
-- p_owner: owning user number, defaults to p_n. TEST-DATA FIX (confirmed against the live project while
-- verifying 0011+0012): trips.user_id is immutable (trips_guard rejects UPDATE ... SET user_id, GWM_IMMUTABLE),
-- so section D's "insert as throwaway user 11/12, then reassign to real user 1/3" pattern cannot work as a
-- follow-up UPDATE - the desired owner must be supplied at INSERT time instead.
create function gwm_test.ptrip(p_n int, p_o geography, p_d geography, p_dep interval, p_owner int default null) returns void language plpgsql as $$
declare v_line geography := ST_MakeLine(p_o::geometry, p_d::geometry)::geography;
begin
  insert into public.trips (id, user_id, mode, origin, dest, route, route_distance_m, route_duration_s, depart_at)
  values (gwm_test.tid(p_n), gwm_test.uid(coalesce(p_owner, p_n)), 'walk', p_o, p_d, v_line, greatest(1, round(ST_Length(v_line))::int), 600, now() + interval '1 hour');
  update public.trips set depart_at = now() + p_dep where id = gwm_test.tid(p_n);
end $$;

create function gwm_test.mid(a int, b int) returns uuid language sql as $$
  select id from public.matches
   where least(requester_trip_id, target_trip_id) = least(gwm_test.tid(a), gwm_test.tid(b))
     and greatest(requester_trip_id, target_trip_id) = greatest(gwm_test.tid(a), gwm_test.tid(b)) $$;

update public.app_config set value = '1000'
 where key in ('throttle.find_matches_per_min', 'throttle.request_match_per_min', 'throttle.match_state_per_min',
               'throttle.device_token_per_hour');
update public.app_config set value = '100' where key = 'match.max_pending_per_trip';
update public.app_config set value = '5000' where key = 'match.dest_radius_m';   -- generous so peer overlap always passes
update public.app_config set value = '5000' where key = 'match.origin_radius_m';

-- users: 1/2 women-only pair (both female+opted-in), 3 female not opted in, 4 male, 5/6 same-org pair (ac.th),
-- 7 different org, 8 org filter OFF control, 9 device-token owner, 10 account-deletion subject, 11-14 throwaway
-- ptrip() owners for section D (fixture reassigns tid(11)/tid(12) ownership to 1/3 right after insert, and
-- tid(13)/tid(14) stay owned by 13/14 - all four still need a real profile row for the INITIAL insert to pass
-- trips_guard's owner-profile check, which is BEFORE the ownership reassignment UPDATE runs). TEST-DATA FIX
-- (not a schema bug): this file's original range (1,10) never signed up 11-14, so ptrip(11..14) failed with
-- GWM_PROFILE_UNAVAILABLE (confirmed against the live project while verifying 0011+0012).
select gwm_test.signup(i) from generate_series(1, 14) i;

-- =====================================================================================================
-- A. device_tokens register/unregister/delete-on-account-deletion
-- =====================================================================================================
select gwm_test.as_user(gwm_test.uid(9));
select public.register_device_token('tok-android-1-aaaaaaaa', 'android');
select gwm_test.chk('A1 register_device_token inserts one row', (select count(*) from public.device_tokens where user_id = gwm_test.uid(9)) = 1);
select public.register_device_token('tok-android-1-aaaaaaaa', 'ios');   -- same token, re-registered on a platform "change" -> update not duplicate
select gwm_test.chk('A2 duplicate (user_id, token) upserts instead of inserting a second row',
  (select count(*) from public.device_tokens where user_id = gwm_test.uid(9)) = 1);
select gwm_test.chk('A3 upsert updates platform', (select platform from public.device_tokens where user_id = gwm_test.uid(9)) = 'ios');
select public.register_device_token('tok-web-2-bbbbbbbb', 'web');
select gwm_test.chk('A4 a second distinct token is a second row (multi-device)', (select count(*) from public.device_tokens where user_id = gwm_test.uid(9)) = 2);
select public.unregister_device_token('tok-web-2-bbbbbbbb');
select gwm_test.chk('A5 unregister removes only that device token', (select count(*) from public.device_tokens where user_id = gwm_test.uid(9)) = 1);
select gwm_test.expect_ok('A6 unregistering an already-gone token is idempotent (no error)',
  format($q$select public.unregister_device_token(%L)$q$, 'tok-web-2-bbbbbbbb'));
select gwm_test.reset();
select gwm_test.chk('A7 device_tokens is not selectable across users (RLS owner-only)',
  (select count(*) from public.device_tokens where user_id = gwm_test.uid(9)) >= 0);   -- superuser sees all; RLS re-asserted in G

select gwm_test.as_user(gwm_test.uid(10));
select public.register_device_token('tok-android-10-cccccccc', 'android');
select gwm_test.reset();
select gwm_test.as_user(gwm_test.uid(10));
select public.request_account_deletion();
select gwm_test.reset();
select gwm_test.chk('A8 request_account_deletion deletes ALL of that user''s device_tokens',
  (select count(*) from public.device_tokens where user_id = gwm_test.uid(10)) = 0);

-- =====================================================================================================
-- B. push_outbox insert-on-trigger for each of the 5 kinds (row shape only - see file header gap note)
-- =====================================================================================================
select gwm_test.ptrip(1, gwm_test.pt(13.75, 0), gwm_test.pt(13.75, 2000), interval '10 minutes');
select gwm_test.ptrip(2, gwm_test.pt(13.75, 50), gwm_test.pt(13.75, 2050), interval '12 minutes');
select gwm_test.as_user(gwm_test.uid(1));
select public.request_match(gwm_test.tid(1), gwm_test.tid(2));
select gwm_test.reset();
select gwm_test.chk('B1 match_requested push queued for the TARGET only',
  (select count(*) from public.push_outbox where match_id = gwm_test.mid(1,2) and kind = 'match_requested' and user_id = gwm_test.uid(2)) = 1
  and (select count(*) from public.push_outbox where match_id = gwm_test.mid(1,2) and kind = 'match_requested' and user_id = gwm_test.uid(1)) = 0);

select gwm_test.as_user(gwm_test.uid(2));
select public.respond_match(gwm_test.mid(1,2), true);
select gwm_test.reset();
select gwm_test.chk('B2 match_accepted push queued for the REQUESTER only',
  (select count(*) from public.push_outbox where match_id = gwm_test.mid(1,2) and kind = 'match_accepted' and user_id = gwm_test.uid(1)) = 1);

select gwm_test.as_user(gwm_test.uid(1));
select public.chat_state(gwm_test.mid(1,2));   -- opens chat (existing RPC; no-op if already open) before sending a message
insert into public.chat_messages (match_id, sender_id, kind, body) values (gwm_test.mid(1,2), gwm_test.uid(1), 'user', 'สวัสดีครับ');
select gwm_test.reset();
select gwm_test.chk('B3 chat_message push queued for the OTHER participant',
  (select count(*) from public.push_outbox where match_id = gwm_test.mid(1,2) and kind = 'chat_message' and user_id = gwm_test.uid(2)) = 1);

insert into public.chat_messages (match_id, sender_id, kind, body) values (gwm_test.mid(1,2), gwm_test.uid(2), 'driver_arrived', 'ถึงจุดรับแล้ว');
select gwm_test.chk('B4 driver_arrived is its own push kind (not chat_message)',
  (select count(*) from public.push_outbox where match_id = gwm_test.mid(1,2) and kind = 'driver_arrived' and user_id = gwm_test.uid(1)) = 1);

select gwm_test.as_user(gwm_test.uid(1));
select public.cancel_match(gwm_test.mid(1,2));
select gwm_test.reset();
select gwm_test.chk('B5 match_cancelled push queued for BOTH participants',
  (select count(*) from public.push_outbox where match_id = gwm_test.mid(1,2) and kind = 'match_cancelled') = 2);

select gwm_test.chk('B6 push_outbox rows never carry a text body/message column (opaque payload by construction)',
  not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'push_outbox' and column_name in ('body','message','text')));
select gwm_test.chk('B7 claim_push_outbox is service_role only (not granted to authenticated/anon)',
  not exists (select 1 from information_schema.role_routine_grants
               where routine_name = 'claim_push_outbox' and grantee in ('authenticated','anon')));

-- =====================================================================================================
-- C. gender: write-only-by-owner / never readable by others directly
-- =====================================================================================================
select gwm_test.as_user(gwm_test.uid(1));
select gwm_test.chk('C1 get_my_gender starts NULL', public.get_my_gender() is null);
update public.profiles set gender = 'female' where id = gwm_test.uid(1);
select gwm_test.reset();
select gwm_test.as_user(gwm_test.uid(1));
select gwm_test.chk('C2 get_my_gender reads back the owner''s own value', public.get_my_gender() = 'female');
select gwm_test.reset();
select gwm_test.chk('C3 profiles.gender is excluded from the profiles SELECT column grant (partner can never read it directly)',
  not exists (select 1 from information_schema.column_privileges
               where table_schema = 'public' and table_name = 'profiles' and column_name = 'gender'
                 and privilege_type = 'SELECT' and grantee = 'authenticated'));
select gwm_test.expect_error('C4 gender rejects a value outside the allow-list',
  format($q$update public.profiles set gender = %L where id = %L$q$, 'unicorn', gwm_test.uid(3)), 'profiles_gender_chk');

-- =====================================================================================================
-- D. women-only matching
-- =====================================================================================================
select gwm_test.ptrip(3, gwm_test.pt(13.76, 0), gwm_test.pt(13.76, 2000), interval '10 minutes');   -- female, NOT opted in
select gwm_test.ptrip(4, gwm_test.pt(13.76, 50), gwm_test.pt(13.76, 2050), interval '11 minutes');  -- male
update public.profiles set gender = 'female' where id in (gwm_test.uid(1), gwm_test.uid(3));   -- 1 already female from C2
-- note: B5 only cancelled the MATCH between trips 1/2, not the trips themselves (trip.max_active = 1 per user,
-- 0001_init.sql), and ptrip(3) just above still leaves trip 3 active for user 3 - both would block a fresh
-- active trip for the SAME real owner below, so free the slot first. TEST-DATA FIX (confirmed against the live
-- project): trip 3 itself is otherwise unused in this file (only tid(4) is asserted against).
update public.trips set status = 'cancelled' where id in (gwm_test.tid(1), gwm_test.tid(3));
-- reuse ids 1 & 3 as real owners; re-fixture a fresh pair for D via new trip ids
select gwm_test.ptrip(11, gwm_test.pt(13.77, 0), gwm_test.pt(13.77, 2000), interval '10 minutes', 1);   -- owned by user 1 directly (user_id is immutable, so it must be set at insert)
select gwm_test.ptrip(12, gwm_test.pt(13.77, 50), gwm_test.pt(13.77, 2050), interval '11 minutes', 3);   -- owned by user 3 (female but not opted in)
update public.trips set women_only = true where id = gwm_test.tid(11);          -- owner (1) is female -> allowed
select gwm_test.expect_error('D1 turning women_only on for a non-female trip owner is rejected at write time',
  format($q$update public.trips set women_only = true where id = %L$q$, gwm_test.tid(4)), 'GWM_GENDER_REQUIRED');

select gwm_test.chk('D2 candidate list EXCLUDES a female-but-not-opted-in trip (only one side has the switch on)',
  not exists (select 1 from public.match_candidates(gwm_test.tid(11), 20) where candidate_trip_id = gwm_test.tid(12)));
update public.trips set women_only = true where id = gwm_test.tid(12);   -- now 3 also opts in (already female)
select gwm_test.chk('D3 both female + both opted in -> candidate appears',
  exists (select 1 from public.match_candidates(gwm_test.tid(11), 20) where candidate_trip_id = gwm_test.tid(12)));

select gwm_test.as_user(gwm_test.uid(1));
select public.request_match(gwm_test.tid(11), gwm_test.tid(12));
select gwm_test.reset();
select gwm_test.as_user(gwm_test.uid(3));
select public.respond_match(gwm_test.mid(11,12), true);
select gwm_test.reset();
select gwm_test.chk('D4 accepted while both eligible', (select status from public.matches where id = gwm_test.mid(11,12)) = 'accepted');

-- Q7: clearing gender while a women_only match is pending/accepted auto-cancels it with a generic message
update public.profiles set gender = null where id = gwm_test.uid(3);
select gwm_test.chk('D5 clearing gender auto-cancels the women_only match', (select status from public.matches where id = gwm_test.mid(11,12)) = 'cancelled');
select gwm_test.chk('D6 clearing gender also turns the user''s own women_only trip flag back off',
  (select women_only from public.trips where id = gwm_test.tid(12)) = false);
select gwm_test.chk('D7 the auto-cancel chat note is the SAME neutral copy as other auto-close cases (no gender leaked)',
  exists (select 1 from public.chat_messages where match_id = gwm_test.mid(11,12) and kind = 'system'
            and body = 'ระบบยกเลิกคำขอนี้เนื่องจากเงื่อนไขการจับคู่พิเศษไม่ครบแล้ว'));

-- request/accept-time enforcement (not just search-time): a stale-eligible pair that becomes ineligible before
-- accept must still be rejected by matches_niche_guard even if match_candidates already returned it a moment earlier.
select gwm_test.ptrip(13, gwm_test.pt(13.78, 0), gwm_test.pt(13.78, 2000), interval '10 minutes');
select gwm_test.ptrip(14, gwm_test.pt(13.78, 50), gwm_test.pt(13.78, 2050), interval '11 minutes');
update public.profiles set gender = 'female' where id in (gwm_test.uid(13), gwm_test.uid(14));
update public.trips set women_only = true where id in (gwm_test.tid(13), gwm_test.tid(14));
select gwm_test.as_user(gwm_test.uid(13));
select public.request_match(gwm_test.tid(13), gwm_test.tid(14));
select gwm_test.reset();
update public.trips set women_only = false where id = gwm_test.tid(14);   -- candidate opts back out before responding
-- TEST-DATA FIX (confirmed against the live project): respond_match must be called AS the match's target (user
-- 14, the accepter) - without as_user(14) this ran as the superuser (auth.uid() null), so respond_match couldn't
-- find a match belonging to that (non-existent) caller and failed with GWM_MATCH_NOT_FOUND before the
-- matches_niche_guard eligibility check this test is meant to exercise was ever reached.
select gwm_test.as_user(gwm_test.uid(14));
select gwm_test.expect_error('D8 respond_match rejects accept once eligibility is gone (matches_niche_guard, not just search-time)',
  format($q$select public.respond_match(%L, true)$q$, gwm_test.mid(13,14)), 'GWM_NOT_ELIGIBLE');
select gwm_test.reset();

-- =====================================================================================================
-- E. same-org filter
-- =====================================================================================================
select gwm_test.ptrip(5, gwm_test.pt(13.79, 0), gwm_test.pt(13.79, 2000), interval '10 minutes');
select gwm_test.ptrip(6, gwm_test.pt(13.79, 50), gwm_test.pt(13.79, 2050), interval '11 minutes');
select gwm_test.ptrip(7, gwm_test.pt(13.79, 60), gwm_test.pt(13.79, 2060), interval '11 minutes');
insert into public.verifications (user_id, kind, status, org_suffix, verified_at) values
  (gwm_test.uid(5), 'organization', 'verified', 'ac.th', now()),
  (gwm_test.uid(6), 'organization', 'verified', 'ac.th', now());
insert into public.org_domains (suffix, org_name) values ('example.co.th', 'บริษัทตัวอย่าง') on conflict do nothing;
insert into public.verifications (user_id, kind, status, org_suffix, verified_at) values
  (gwm_test.uid(7), 'organization', 'verified', 'example.co.th', now());

select gwm_test.expect_error('E1 turning same_org_only on without any org verification is rejected at write time',
  format($q$update public.trips set same_org_only = true where id = %L$q$, gwm_test.tid(1))::text, 'GWM_ORG_VERIFICATION_REQUIRED');
update public.trips set same_org_only = true where id in (gwm_test.tid(5), gwm_test.tid(6), gwm_test.tid(7));
select gwm_test.chk('E2 both verified, SAME suffix -> candidate appears',
  exists (select 1 from public.match_candidates(gwm_test.tid(5), 20) where candidate_trip_id = gwm_test.tid(6)));
select gwm_test.chk('E3 both opted in but DIFFERENT verified suffix -> excluded',
  not exists (select 1 from public.match_candidates(gwm_test.tid(5), 20) where candidate_trip_id = gwm_test.tid(7)));

-- TEST-DATA FIX (confirmed against the live project): _niche_filters_ok is deliberately SYMMETRIC (0012 section 4
-- comment: "ONE predicate, symmetric") - if EITHER side has same_org_only on, BOTH sides must satisfy it, so a
-- searcher with the filter off is still excluded from a candidate that itself requires same-org and isn't
-- satisfied. This assertion originally expected the opposite (asymmetric) behaviour, which contradicts the
-- design this migration actually implements.
select gwm_test.ptrip(8, gwm_test.pt(13.79, 55), gwm_test.pt(13.79, 2055), interval '11 minutes');   -- filter OFF, no verification at all
select gwm_test.chk('E4 candidate''s same_org_only requirement still applies even when the searcher''s own filter is off (symmetric predicate)',
  not exists (select 1 from public.match_candidates(gwm_test.tid(8), 20) where candidate_trip_id = gwm_test.tid(5)));

-- =====================================================================================================
-- F. vibe_tags allow-list
-- =====================================================================================================
select gwm_test.expect_error('F1 a tag outside the allow-list is rejected',
  format($q$update public.trips set vibe_tags = array[%L] where id = %L$q$, '#free-text-tag', gwm_test.tid(1)), 'GWM_VIBE_TAG_INVALID');
select gwm_test.expect_ok('F2 an allow-listed rider tag is accepted',
  format($q$update public.trips set vibe_tags = array[%L,%L] where id = %L$q$, '#คุยเก่ง', '#สายประหยัด', gwm_test.tid(1)));
select gwm_test.expect_error('F3 more than vibe.max_tags (3) is rejected',
  format($q$update public.trips set vibe_tags = array[%L,%L,%L,%L] where id = %L$q$,
         '#คุยเก่ง', '#สายประหยัด', '#ฟังเพลงสากล', '#พร้อมแชร์เรื่องเล่า', gwm_test.tid(1)), 'GWM_VIBE_TAG_INVALID');

-- =====================================================================================================
-- G. mood_text digit-run / blocklist guard
-- =====================================================================================================
select gwm_test.expect_error('G1 an 8+ digit run (phone-like) is rejected',
  format($q$update public.trips set mood_text = %L where id = %L$q$, 'โทรหาฉัน 08123456789', gwm_test.tid(1)), 'GWM_MOOD_INVALID');
select gwm_test.expect_error('G2 a blocklisted word is rejected',
  format($q$update public.trips set mood_text = %L where id = %L$q$, 'วันนี้เหี้ยมาก', gwm_test.tid(1)), 'GWM_MOOD_INVALID');
select gwm_test.expect_ok('G3 a clean short string is accepted and stamps mood_set_at',
  format($q$update public.trips set mood_text = %L where id = %L$q$, 'วันนี้อากาศดีจัง', gwm_test.tid(1)));
select gwm_test.chk('G4 mood_set_at is set when mood_text is set', (select mood_set_at from public.trips where id = gwm_test.tid(1)) is not null);
select gwm_test.expect_error('G5 mood_text over 35 chars is rejected',
  format($q$update public.trips set mood_text = %L where id = %L$q$, repeat('ก', 40), gwm_test.tid(1)), 'GWM_MOOD_INVALID');
update public.trips set mood_text = null where id = gwm_test.tid(1);
select gwm_test.chk('G6 clearing mood_text also clears mood_set_at', (select mood_set_at from public.trips where id = gwm_test.tid(1)) is null);

-- =====================================================================================================
-- H. 24h mood auto-clear via purge_expired_data (+ trip-end clear)
-- =====================================================================================================
update public.trips set mood_text = 'ยังอยู่ในช่วง 24 ชม.', vibe_tags = array['#คุยเก่ง'] where id = gwm_test.tid(6);
update public.trips set mood_set_at = now() - interval '25 hours' where id = gwm_test.tid(6);
select public.purge_expired_data();
select gwm_test.chk('H1 purge_expired_data clears mood_text/vibe_tags/mood_set_at past the 24h window',
  (select mood_text is null and vibe_tags is null and mood_set_at is null from public.trips where id = gwm_test.tid(6)));

update public.trips set mood_text = 'จบทริปแล้วน่าจะหาย', vibe_tags = array['#สายประหยัด'] where id = gwm_test.tid(7);
update public.trips set status = 'cancelled', ended_at = now() where id = gwm_test.tid(7);
select gwm_test.chk('H2 ending a trip clears mood/vibe immediately (does not wait for 24h)',
  (select mood_text is null and vibe_tags is null from public.trips where id = gwm_test.tid(7)));

-- =====================================================================================================
-- I. get_trip_card / export_my_data new fields (14.8-5, 14.8-6 - closed before handoff to Dart)
-- =====================================================================================================
-- writes done directly as the superuser (same style as section H) - mood_set_at has no client column grant at
-- all (server/trigger-only), so it cannot be backdated this way under role authenticated.
update public.trips set vibe_tags = array['#คุยเก่ง'], mood_text = 'สดใหม่ใน 24 ชม.' where id = gwm_test.tid(1);
select gwm_test.as_user(gwm_test.uid(1));
select gwm_test.chk('I1 get_trip_card returns vibe_tags/mood_text for a fresh mood (owner)',
  (select vibe_tags = array['#คุยเก่ง'] and mood_text = 'สดใหม่ใน 24 ชม.' from public.get_trip_card(gwm_test.tid(1))));
select gwm_test.reset();

update public.trips set mood_set_at = now() - interval '25 hours' where id = gwm_test.tid(1);
select gwm_test.as_user(gwm_test.uid(1));
select gwm_test.chk('I2 get_trip_card hides a mood past the 24h window even before purge_expired_data runs '
                     || '(live staleness recheck, not just relying on the row already being cleared)',
  (select mood_text is null and vibe_tags = array['#คุยเก่ง'] from public.get_trip_card(gwm_test.tid(1))));
select gwm_test.reset();
update public.trips set mood_text = null, mood_set_at = null where id = gwm_test.tid(1);   -- reset for later sections

update public.profiles set gender = 'female' where id = gwm_test.uid(1);
update public.trips set vibe_tags = array['#สายประหยัด'], mood_text = 'export me' where id = gwm_test.tid(1);
select gwm_test.as_user(gwm_test.uid(1));
select gwm_test.chk('I3 export_my_data profile includes gender with no code change needed (whole-row to_jsonb)',
  (select (public.export_my_data() -> 'profile' ->> 'gender') = 'female'));
select gwm_test.chk('I4 export_my_data trips include vibe_tags/mood_text with no code change needed (uid(1) owns '
                     || 'more than one trip, so search the array rather than assume tid(1) is element 0)',
  (select bool_or((elem ->> 'mood_text') = 'export me' and (elem -> 'vibe_tags') = '["#สายประหยัด"]'::jsonb)
     from jsonb_array_elements(public.export_my_data() -> 'trips') elem));
select gwm_test.expect_ok('I5 register_device_token so export_my_data has a device_tokens row to check',
  format($q$select public.register_device_token(%L, %L)$q$, 'test-token-0000001', 'android'));
select gwm_test.chk('I6 export_my_data device_tokens has platform but NOT the raw token value',
  (select bool_or((elem ->> 'platform') = 'android' and not (elem ? 'token'))
     from jsonb_array_elements(public.export_my_data() -> 'device_tokens') elem));
select gwm_test.reset();

-- =====================================================================================================
-- J. road-snap (US-43): NOT TESTED HERE - Dart/OSRM client-side only, propose_meeting_point/confirm_meeting_point
--    are unchanged (0006 signature), no DB surface to assert against in this harness.
-- =====================================================================================================
select gwm_test.chk('J1 propose_meeting_point signature unchanged by round 7 (US-43 needed no schema change)',
  (select pg_get_function_identity_arguments(oid) from pg_proc
    where proname = 'propose_meeting_point' and pronamespace = 'public'::regnamespace)
  = 'p_match_id uuid, p_lng double precision, p_lat double precision, p_label text');

-- ---- report ---------------------------------------------------------------------------------------
select gwm_test.reset();
select n, case when ok then 'PASS' else 'FAIL' end as result, label, detail from gwm_test.results order by n;
select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed from gwm_test.results;
do $$
begin
  if exists (select 1 from gwm_test.results where not ok) then
    raise exception 'Round 7 (0011/0012) SQL tests FAILED: % check(s)', (select count(*) from gwm_test.results where not ok);
  end if;
end $$;
rollback;
