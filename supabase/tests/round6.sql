-- =============================================================================
-- GOWITHME automated SQL tests for migration 0010 (round 6: US-36 rating on deck cards via find_matches, US-35 undo guard
-- cancel_pending_match; docs/design-roles.md section 13).
-- Run after migrations 0001-0010 (as the postgres superuser role):
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f supabase/tests/round6.sql
-- One transaction, ROLLED BACK at the end. Same harness as round5.sql. Prints PASS/FAIL rows, exits non-zero on any FAIL.
-- (Authored without a database at hand: run it before applying 0010. True two-session concurrency: see design-roles.md 13.6.)
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

update public.app_config set value = '1000'
 where key in ('throttle.find_matches_per_min', 'throttle.request_match_per_min', 'throttle.match_state_per_min');
update public.app_config set value = '100' where key = 'match.max_pending_per_trip';

-- users: 1 rider searcher; 2..6 candidate drivers; 10..16 reviewers; 20 driver searcher, 21 rider candidate; 30..43 undo zone
select gwm_test.signup(i) from generate_series(1, 6) i;
select gwm_test.signup(i) from generate_series(10, 16) i;
select gwm_test.signup(i) from generate_series(20, 21) i;
select gwm_test.signup(i) from generate_series(30, 43) i;

-- review fixture: a (cancelled) match reviewer-trip -> target-trip carries the review of the TARGET in p_role
-- p_state: revealed | unrevealed (reveal_at in the future, revealed_at null) | timeout (reveal_at passed, revealed_at null) | held | removed
create function gwm_test.rev(p_reviewer int, p_target int, p_role text, p_stars int, p_state text default 'revealed') returns void language plpgsql as $$
declare v_m uuid;
begin
  select id into v_m from public.matches where requester_trip_id = gwm_test.tid(p_reviewer) and target_trip_id = gwm_test.tid(p_target);
  if v_m is null then
    insert into public.matches (requester_trip_id, target_trip_id, requester_id, target_id, status, responded_at)
    values (gwm_test.tid(p_reviewer), gwm_test.tid(p_target), gwm_test.uid(p_reviewer), gwm_test.uid(p_target), 'cancelled', now())
    returning id into v_m;
  end if;
  insert into public.reviews (match_id, reviewer_id, reviewee_id, role, stars, reveal_at, revealed_at, held_at, removed_at)
  values (v_m, gwm_test.uid(p_reviewer), gwm_test.uid(p_target), p_role::public.trip_role, p_stars,
          case when p_state = 'unrevealed' then now() + interval '5 days' else now() - interval '1 day' end,
          case when p_state in ('revealed', 'held', 'removed') then now() - interval '1 day' end,
          case when p_state = 'held' then now() end, case when p_state = 'removed' then now() end);
end $$;

-- find_matches snapshot taken AS the searcher (through the RPC and its grants), stored for superuser assertions
create table gwm_test.fm (run text, trip_id uuid, role public.trip_role, approx_dest_lat float8, rating_avg numeric, rating_count int);
grant all on gwm_test.fm to public;
create table gwm_test.cres (n int, r text);
grant all on gwm_test.cres to public;
create function gwm_test.snap(p_run text, p_searcher int, p_trip int) returns void language plpgsql as $$
begin
  perform gwm_test.as_user(gwm_test.uid(p_searcher));
  insert into gwm_test.fm select p_run, f.trip_id, f.role, f.approx_dest_lat, f.rating_avg, f.rating_count
    from public.find_matches(gwm_test.tid(p_trip), 50) f;
  perform gwm_test.reset();
end $$;
create function gwm_test.avg_of(p_run text, p_n int) returns numeric language sql as
$$ select rating_avg from gwm_test.fm where run = p_run and trip_id = gwm_test.tid(p_n) $$;
create function gwm_test.cnt_of(p_run text, p_n int) returns int language sql as
$$ select rating_count from gwm_test.fm where run = p_run and trip_id = gwm_test.tid(p_n) $$;
create function gwm_test.present(p_run text, p_n int) returns boolean language sql as
$$ select exists (select 1 from gwm_test.fm where run = p_run and trip_id = gwm_test.tid(p_n)) $$;

-- =============================================================================
-- A. schema / contract
-- =============================================================================
-- NOTE: 0016 (BUG-R7-01) appended vibe_tags/mood_text after rating_count -- this snapshot check is updated to
-- match that later, intentional contract change (not a regression caused by round 6 itself).
select gwm_test.chk('A1 find_matches column list: 16 unchanged columns then rating_avg, rating_count appended',
  (select proargnames[3:22] = array['trip_id','display_name','badges','mode','depart_at','time_diff_min','overlap_pct',
     'approx_distance_m','score','approx_origin_lat','approx_origin_lng','approx_dest_lat','approx_dest_lng','request_status','role','max_dropoff_m',
     'rating_avg','rating_count','vibe_tags','mood_text']::text[]
     from pg_proc where oid = 'public.find_matches(uuid,int)'::regprocedure));
select gwm_test.chk('A2 no column of find_matches can identify a user (trip_id is the only handle; no *user*/*uid*/reviewer/reviewee/profile column)',
  not exists (select 1 from pg_proc p, unnest(p.proargnames) a
               where p.oid = 'public.find_matches(uuid,int)'::regprocedure and (a ~* 'user|uid|reviewer|reviewee|profile' or a = 'id')));
select gwm_test.chk('A3 result types: rating_avg numeric, rating_count integer',
  (select pg_get_function_result(p.oid) like '%rating_avg numeric, rating_count integer, vibe_tags text[], mood_text text)' from pg_proc p where p.oid = 'public.find_matches(uuid,int)'::regprocedure));
select gwm_test.chk('A4 grants: find_matches + cancel_pending_match executable by authenticated only',
  has_function_privilege('authenticated', 'public.find_matches(uuid,int)', 'execute')
  and has_function_privilege('authenticated', 'public.cancel_pending_match(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.find_matches(uuid,int)', 'execute')
  and not has_function_privilege('anon', 'public.cancel_pending_match(uuid)', 'execute')
  and not has_function_privilege('public', 'public.cancel_pending_match(uuid)', 'execute'));
select gwm_test.chk('A5 covering partial index exists', exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'reviews_agg_cover_idx'));
select gwm_test.chk('A6 review.show_in_search = true and min count = 3 by default', public.cfg_bool('review.show_in_search') and public.cfg_num('review.min_count_for_aggregate') = 3);

-- =============================================================================
-- B. rating on deck cards. Zone lat 16.50: searcher rider 1, candidate drivers 2..6 (same route). Reviewers 10..16: completed trips far away.
--    Zone lat 16.60: searcher driver 20, candidate rider 21.
-- =============================================================================
select gwm_test.rtrip(1, 'car', 'rider', gwm_test.pt(16.5, 500), gwm_test.pt(16.5, 4000), interval '1 hour');
select gwm_test.rtrip(i, 'car', 'driver', gwm_test.pt(16.5, 0), gwm_test.pt(16.5, 5000), interval '1 hour') from generate_series(2, 6) i;
select gwm_test.rtrip(i, 'car', 'rider', gwm_test.pt(16.9, 0), gwm_test.pt(16.9, 4000), interval '1 hour') from generate_series(10, 16) i;
select gwm_test.tstate(i, 'in_progress') from generate_series(10, 16) i;
select gwm_test.tstate(i, 'completed') from generate_series(10, 16) i;
select gwm_test.rtrip(20, 'car', 'driver', gwm_test.pt(16.6, 0), gwm_test.pt(16.6, 5000), interval '1 hour');
select gwm_test.rtrip(21, 'car', 'rider', gwm_test.pt(16.6, 500), gwm_test.pt(16.6, 4000), interval '1 hour');

-- D2: 3 driver reviews 5,4,4 (avg 4.33 -> 4.3) + 2 RIDER-role reviews of 1 star (per-role separation)
select gwm_test.rev(10, 2, 'driver', 5); select gwm_test.rev(11, 2, 'driver', 4); select gwm_test.rev(12, 2, 'driver', 4);
select gwm_test.rev(13, 2, 'rider', 1);  select gwm_test.rev(14, 2, 'rider', 1);
-- D3: 4 driver reviews 5,4,4,4 (avg 4.25 -> 4.3, half rounds up) + noise that must never count: unrevealed, held, removed (1 star each)
select gwm_test.rev(10, 3, 'driver', 5); select gwm_test.rev(11, 3, 'driver', 4); select gwm_test.rev(12, 3, 'driver', 4); select gwm_test.rev(13, 3, 'driver', 4);
select gwm_test.rev(14, 3, 'driver', 1, 'unrevealed'); select gwm_test.rev(15, 3, 'driver', 1, 'held'); select gwm_test.rev(16, 3, 'driver', 1, 'removed');
-- D4: 2 revealed + 1 unrevealed => only 2 counted => hidden
select gwm_test.rev(10, 4, 'driver', 5); select gwm_test.rev(11, 4, 'driver', 5); select gwm_test.rev(12, 4, 'driver', 1, 'unrevealed');
-- D5: 3 five-star reviews but as RIDER only => hidden on a driver trip
select gwm_test.rev(10, 5, 'rider', 5); select gwm_test.rev(11, 5, 'rider', 5); select gwm_test.rev(12, 5, 'rider', 5);
-- D6: 2 stamped + 1 past its reveal_at (timeout reveal, revealed_at still null; same rule as review_aggregates) => 3.67 -> 3.7
select gwm_test.rev(10, 6, 'driver', 3); select gwm_test.rev(11, 6, 'driver', 4); select gwm_test.rev(12, 6, 'driver', 4, 'timeout');
-- 21 (rider candidate for driver 20): 3 rider reviews 5,5,4 (4.67 -> 4.7) + 2 driver-role 1-star
select gwm_test.rev(10, 21, 'rider', 5); select gwm_test.rev(11, 21, 'rider', 5); select gwm_test.rev(12, 21, 'rider', 4);
select gwm_test.rev(13, 21, 'driver', 1); select gwm_test.rev(14, 21, 'driver', 1);

select gwm_test.snap('on', 1, 1);
select gwm_test.snap('on20', 20, 20);
select gwm_test.chk('B0 fixture sanity: all five candidate drivers are in the deck', (select count(*) from gwm_test.fm where run = 'on') = 5);
select gwm_test.chk('B1 shown at 3 revealed reviews: D2 = 4.3 / 3 (rider-role reviews not mixed in: count is 3, not 5)',
  gwm_test.avg_of('on', 2) = 4.3 and gwm_test.cnt_of('on', 2) = 3);
select gwm_test.chk('B2 rounding to 0.1 (half up): D3 = 4.25 -> 4.3, count 4; unrevealed/held/removed reviews are not counted',
  gwm_test.avg_of('on', 3) = 4.3 and gwm_test.cnt_of('on', 3) = 4);
select gwm_test.chk('B3 hidden below 3: D4 (2 revealed + 1 unrevealed) -> NULL / NULL, the row is still in the deck',
  gwm_test.present('on', 4) and gwm_test.avg_of('on', 4) is null and gwm_test.cnt_of('on', 4) is null);
select gwm_test.chk('B4 per-role separation: D5 has 3 rider-role reviews only -> NULL on a driver trip',
  gwm_test.present('on', 5) and gwm_test.avg_of('on', 5) is null and gwm_test.cnt_of('on', 5) is null);
select gwm_test.chk('B5 timeout-revealed review counts like in review_aggregates: D6 = 3.7 / 3',
  gwm_test.avg_of('on', 6) = 3.7 and gwm_test.cnt_of('on', 6) = 3);
select gwm_test.chk('B6 rider candidate seen by a Driver: RIDER-role rating (4.7 / 3, driver-role reviews ignored), destination still hidden',
  gwm_test.avg_of('on20', 21) = 4.7 and gwm_test.cnt_of('on20', 21) = 3
  and (select approx_dest_lat is null and role = 'rider' from gwm_test.fm where run = 'on20' and trip_id = gwm_test.tid(21)));
select gwm_test.chk('B7 the aggregate equals the review_aggregates view for every candidate (predicate never drifts)',
  not exists (select 1 from gwm_test.fm f
               join public.trips t on t.id = f.trip_id
               left join public.review_aggregates a on a.user_id = t.user_id and a.role = f.role
              where f.run in ('on', 'on20') and (f.rating_avg, f.rating_count) is distinct from (a.avg_stars, a.review_count)));
select gwm_test.chk('B8 unrevealed reviews exist in the fixture (D3 has one, future reveal_at) and D3 is still 4 counted',
  (select count(*) from public.reviews r where r.reviewee_id = gwm_test.uid(3) and r.revealed_at is null and r.reveal_at > now()) = 1
  and gwm_test.cnt_of('on', 3) = 4);

select gwm_test.setcfg('review.show_in_search', 'false');
select gwm_test.snap('off', 1, 1);
select gwm_test.chk('B9 review.show_in_search = false: every rating NULL; same rows in the deck',
  (select count(*) = 5 and bool_and(rating_avg is null and rating_count is null) from gwm_test.fm where run = 'off')
  and (select array_agg(trip_id order by trip_id) from gwm_test.fm where run = 'off') = (select array_agg(trip_id order by trip_id) from gwm_test.fm where run = 'on'));
select gwm_test.setcfg('review.show_in_search', 'true');

select gwm_test.setcfg('review.min_count_for_aggregate', '2');
select gwm_test.snap('min2', 1, 1);
select gwm_test.chk('B10 the threshold comes from review.min_count_for_aggregate (=2: D4 shows 5.0 / 2)', gwm_test.avg_of('min2', 4) = 5.0 and gwm_test.cnt_of('min2', 4) = 2);
select gwm_test.setcfg('review.min_count_for_aggregate', '3');

select gwm_test.chk('B11 Driver candidates keep their (blurred) destination for a Rider searcher (privacy rule unchanged)',
  (select bool_and(approx_dest_lat is not null) from gwm_test.fm where run = 'on'));
do $$
begin
  perform gwm_test.as_user(gwm_test.uid(1));
  begin
    perform 1 from public.find_matches(gwm_test.tid(21), 5);      -- somebody else's trip
    perform gwm_test.chk('B12 find_matches on a trip that is not mine is still refused', false, 'no error');
  exception when others then
    perform gwm_test.chk('B12 find_matches on a trip that is not mine is still refused', sqlerrm ilike '%GWM_TRIP_NOT_FOUND%', sqlerrm);
  end;
  perform gwm_test.reset();
end $$;

-- =============================================================================
-- C. undo guard: cancel_pending_match. Zone lat 16.20: riders 30 32 34 36 38 40, drivers 31 33 35 37 39 41.
-- =============================================================================
select gwm_test.rtrip(i, 'car', 'rider',  gwm_test.pt(16.2, 500), gwm_test.pt(16.2, 4000), interval '1 hour') from unnest(array[30, 32, 34, 36, 38, 40]) i;
select gwm_test.rtrip(i, 'car', 'driver', gwm_test.pt(16.2, 0),   gwm_test.pt(16.2, 5000), interval '1 hour') from unnest(array[31, 33, 35, 37, 39, 41]) i;

-- C1-C4: pending -> cancelled, repeat is idempotent, pending cap released
update public.app_config set value = '1' where key = 'match.max_pending_per_trip';
select gwm_test.as_user(gwm_test.uid(30));
select public.request_match(gwm_test.tid(30), gwm_test.tid(31));
select gwm_test.expect_error('C1 cap = 1: a second pending request is refused while the first is pending',
  format($q$select public.request_match(%L, %L)$q$, gwm_test.tid(30), gwm_test.tid(33)), 'GWM_PENDING_LIMIT');
insert into gwm_test.cres select 1, public.cancel_pending_match(gwm_test.mid(30, 31));
select gwm_test.reset();
select gwm_test.chk('C2 pending -> cancelled by the requester (returns cancelled; status cancelled; responded_at set)',
  (select r from gwm_test.cres where n = 1) = 'cancelled'
  and (select status = 'cancelled' and responded_at is not null from public.matches where id = gwm_test.mid(30, 31)));
select gwm_test.as_user(gwm_test.uid(30));
insert into gwm_test.cres select 2, public.cancel_pending_match(gwm_test.mid(30, 31));
select gwm_test.reset();
select gwm_test.chk('C3 idempotent: the repeat returns already_cancelled, no error, still cancelled',
  (select r from gwm_test.cres where n = 2) = 'already_cancelled' and (select status = 'cancelled' from public.matches where id = gwm_test.mid(30, 31)));
select gwm_test.as_user(gwm_test.uid(30));
select gwm_test.expect_ok('C4 cap released: a new pending request to another driver now succeeds (cap still 1)',
  format($q$select public.request_match(%L, %L)$q$, gwm_test.tid(30), gwm_test.tid(33)));
select gwm_test.reset();
select gwm_test.chk('C4b exactly one pending match for the trip (the undone request is not counted)',
  (select count(*) from public.matches where requester_trip_id = gwm_test.tid(30) and status = 'pending') = 1);
update public.app_config set value = '100' where key = 'match.max_pending_per_trip';

-- C5: the other side accepted first -> refused, the match stays accepted
select gwm_test.pair_accept(34, 35);
select gwm_test.as_user(gwm_test.uid(34));
select gwm_test.expect_error('C5 after the other side accepted: GWM_MATCH_NOT_PENDING',
  format($q$select public.cancel_pending_match(%L)$q$, gwm_test.mid(34, 35)), 'GWM_MATCH_NOT_PENDING');
select gwm_test.reset();
select gwm_test.chk('C5b the accepted match is untouched (status accepted)', (select status from public.matches where id = gwm_test.mid(34, 35)) = 'accepted');

-- C6: cancel_match semantics for accepted matches unchanged (not boarded -> still cancellable)
select gwm_test.pair_accept(36, 37);
select gwm_test.as_user(gwm_test.uid(36));
select gwm_test.expect_ok('C6 cancel_match still cancels an ACCEPTED match (unchanged)', format($q$select public.cancel_match(%L)$q$, gwm_test.mid(36, 37)));
select gwm_test.reset();
select gwm_test.chk('C6b status cancelled', (select status from public.matches where id = gwm_test.mid(36, 37)) = 'cancelled');

-- C7: declined -> NOT_PENDING (status stays declined)
select gwm_test.as_user(gwm_test.uid(38));
select public.request_match(gwm_test.tid(38), gwm_test.tid(39));
select gwm_test.reset();
select gwm_test.as_user(gwm_test.uid(39));
select public.respond_match(gwm_test.mid(38, 39), false);
select gwm_test.reset();
select gwm_test.as_user(gwm_test.uid(38));
select gwm_test.expect_error('C7 declined match: GWM_MATCH_NOT_PENDING', format($q$select public.cancel_pending_match(%L)$q$, gwm_test.mid(38, 39)), 'GWM_MATCH_NOT_PENDING');
select gwm_test.reset();
select gwm_test.chk('C7b stays declined', (select status from public.matches where id = gwm_test.mid(38, 39)) = 'declined');

-- C8: non-requester refused (target and a stranger), the match stays pending; unknown id; unauthenticated
select gwm_test.as_user(gwm_test.uid(40));
select public.request_match(gwm_test.tid(40), gwm_test.tid(41));
select gwm_test.reset();
select gwm_test.as_user(gwm_test.uid(41));
select gwm_test.expect_error('C8 the target (not the requester) cannot use it: GWM_MATCH_NOT_FOUND', format($q$select public.cancel_pending_match(%L)$q$, gwm_test.mid(40, 41)), 'GWM_MATCH_NOT_FOUND');
select gwm_test.reset();
select gwm_test.as_user(gwm_test.uid(42));
select gwm_test.expect_error('C8b a stranger: GWM_MATCH_NOT_FOUND', format($q$select public.cancel_pending_match(%L)$q$, gwm_test.mid(40, 41)), 'GWM_MATCH_NOT_FOUND');
select gwm_test.expect_error('C8c unknown id: GWM_MATCH_NOT_FOUND', $q$select public.cancel_pending_match('99999999-0000-4000-8000-000000000001')$q$, 'GWM_MATCH_NOT_FOUND');
select gwm_test.reset();
select gwm_test.chk('C8d the match is still pending', (select status from public.matches where id = gwm_test.mid(40, 41)) = 'pending');
select gwm_test.expect_error('C8e no auth.uid(): GWM_UNAUTHENTICATED', format($q$select public.cancel_pending_match(%L)$q$, gwm_test.mid(40, 41)), 'GWM_UNAUTHENTICATED');

-- C9: statement ordering / lock. The guard is ONE UPDATE whose WHERE holds status = 'pending' (row lock + re-check after a lock wait). Both
--     serialisation orders leave a consistent row: accept-first => NOT_PENDING (C5); cancel-first => the accept finds no pending row (C9b).
select gwm_test.chk('C9 single guarded UPDATE: UPDATE ... SET status = cancelled WHERE requester_id = v_uid AND status = pending (no select-then-update)',
  (select pg_get_functiondef(p.oid) ~* 'update public\.matches set status = ''cancelled''[^;]*requester_id = v_uid and status = ''pending'''
     from pg_proc p where p.oid = 'public.cancel_pending_match(uuid)'::regprocedure));
select gwm_test.as_user(gwm_test.uid(40));
select public.cancel_pending_match(gwm_test.mid(40, 41));
select gwm_test.reset();
select gwm_test.as_user(gwm_test.uid(41));
select gwm_test.expect_error('C9b cancel committed first: the target accepting afterwards is refused (GWM_MATCH_NOT_FOUND)',
  format($q$select public.respond_match(%L, true)$q$, gwm_test.mid(40, 41)), 'GWM_MATCH_NOT_FOUND');
select gwm_test.reset();
select gwm_test.chk('C9c the match ends cancelled, never accepted', (select status from public.matches where id = gwm_test.mid(40, 41)) = 'cancelled');

-- C10: request throttle unchanged: request, undo, request still consume the request bucket (limit 2 -> the third send is rate limited)
update public.app_config set value = '2' where key = 'throttle.request_match_per_min';
select gwm_test.as_user(gwm_test.uid(32));
select public.request_match(gwm_test.tid(32), gwm_test.tid(31));
select public.cancel_pending_match(gwm_test.mid(32, 31));
select public.request_match(gwm_test.tid(32), gwm_test.tid(33));
select gwm_test.expect_error('C10 undone requests still count against throttle.request_match_per_min (third send -> GWM_RATE_LIMITED)',
  format($q$select public.request_match(%L, %L)$q$, gwm_test.tid(32), gwm_test.tid(35)), 'GWM_RATE_LIMITED');
select gwm_test.reset();
update public.app_config set value = '1000' where key = 'throttle.request_match_per_min';
select gwm_test.chk('C11 request_match / cancel_match / respond_match / _accept_match do not reference the new RPC (behaviour untouched)',
  not exists (select 1 from pg_proc where proname in ('request_match', 'cancel_match', 'respond_match', '_accept_match')
                and pronamespace = 'public'::regnamespace and pg_get_functiondef(oid) ilike '%cancel_pending_match%'));

-- ---- report ---------------------------------------------------------------------------------------
select gwm_test.reset();
select n, case when ok then 'PASS' else 'FAIL' end as result, label, detail from gwm_test.results order by n;
select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed from gwm_test.results;
do $$
begin
  if exists (select 1 from gwm_test.results where not ok) then
    raise exception 'Round 6 (0010) SQL tests FAILED: % check(s)', (select count(*) from gwm_test.results where not ok);
  end if;
end $$;
rollback;
