-- =============================================================================
-- GOWITHME 0003: QA round 1 fixes (T5.11, T5.12, T5.14). Re-runnable. Apply after 0001 + 0002.
--   T5.11 BUG-3  handle_new_user rejects signups without 18+/current policy; server-set timestamps;
--                revoke client write access to adult_confirmed_at and consents
--   T5.12 BUG-1  request_account_deletion bans the auth user and revokes all sessions/refresh tokens (fail-closed)
--   T5.14 BUG-10 match_candidates filters expired trips itself (does not rely on the pg_cron expiry job)
-- Not touched on purpose: trip_locations_rate_guard (5 s), trips_guard (second layer for 18+/consent).
-- =============================================================================

-- 1. Current policy version (server-side source of truth; keep equal to AppConstants.policyVersion) ----------
insert into public.app_config (key, value, description, is_public) values
  ('policy.current_version', '"0.1-draft"', 'SECURITY: signup is rejected unless raw_user_meta_data.policy_version equals this', true)
on conflict (key) do nothing;

-- 2. T5.11 handle_new_user --------------------------------------------------------------------------------------
-- Uses ONLY display_name, adult_confirmed, policy_version from metadata. Timestamps come from now() on the server.
-- RAISE aborts the auth.users insert => GoTrue answers "Database error saving new user"; no profile/user is left behind.
-- Note: applies to every path that inserts into auth.users (OAuth/anonymous/admin API too). MVP is email+password only.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_name text; v_ver text; v_cur text;
begin
  if coalesce(new.raw_user_meta_data ->> 'adult_confirmed', '') <> 'true' then
    raise exception 'GWM_ADULT_REQUIRED' using errcode = 'P0001';
  end if;
  v_ver := nullif(btrim(coalesce(new.raw_user_meta_data ->> 'policy_version', '')), '');
  v_cur := public.cfg('policy.current_version') #>> '{}';
  if v_ver is null or v_cur is null or v_ver <> v_cur then     -- fail closed when config is missing
    raise exception 'GWM_CONSENT_REQUIRED' using errcode = 'P0001';
  end if;

  v_name := left(coalesce(nullif(btrim(new.raw_user_meta_data ->> 'display_name'), ''),
                          nullif(split_part(coalesce(new.email, ''), '@', 1), ''), 'ผู้ใช้'), 60);
  insert into public.profiles (id, display_name, adult_confirmed_at)
  values (new.id, v_name, now())
  on conflict (id) do nothing;

  insert into public.consents (user_id, kind, granted, policy_version, created_at)
  values (new.id, 'privacy_policy', true, v_ver, now()), (new.id, 'terms', true, v_ver, now());

  perform public.sync_user_verifications(new.id, new.email, new.email_confirmed_at);
  return new;
end $$;

-- Clients may no longer write the 18+ timestamp or insert consent rows directly (record_consent RPC remains).
revoke update (adult_confirmed_at) on public.profiles from authenticated;
revoke insert on public.consents from authenticated;
revoke insert, update, delete on public.consents from anon;

-- 3. T5.12 account deletion: cannot sign in again, existing sessions die -------------------------------------------
-- SECURITY DEFINER runs as the function owner (postgres), which may write auth.* on Supabase (purge_expired_data does
-- the same for hard delete). No exception handler: if the ban fails the whole deletion rolls back (fail closed) and the
-- client shows an error, instead of a "deleted" account that can still sign in.
-- Fallback if a Supabase version forbids this: call auth.admin.updateUserById(ban_duration) from an Edge Function.
-- Residual: an already issued access token (JWT) stays valid until it expires (default 1 h) but every row of the user is
-- cancelled/hidden and the client signs out immediately; refresh is impossible.
create or replace function public.request_account_deletion() returns void
language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'GWM_UNAUTHENTICATED' using errcode = '42501'; end if;
  update public.trips set status = 'cancelled' where user_id = v_uid and status in ('scheduled','in_progress');
  update public.trips set deleted_at = now() where user_id = v_uid and deleted_at is null;
  update public.matches set status = 'cancelled', responded_at = now()
   where status in ('pending','accepted') and v_uid in (requester_id, target_id);
  update public.trip_shares set revoked_at = now() where user_id = v_uid and revoked_at is null;
  delete from public.trip_locations where user_id = v_uid;
  delete from public.emergency_contacts where user_id = v_uid;
  update public.profiles set deleted_at = now(), display_name = 'ผู้ใช้ที่ลบบัญชีแล้ว', avatar_path = null where id = v_uid;

  update auth.users set banned_until = now() + interval '100 years' where id = v_uid;   -- sign-in and refresh refused
  delete from auth.sessions where user_id = v_uid;                                     -- cascades refresh_tokens
end $$;

-- 4. T5.14 match_candidates: filter expired trips in the query itself -----------------------------------------------
-- Same body as 0001 plus: candidate AND requester trip must be newer than depart_at - expire_after_min.
create or replace function public.match_candidates(p_trip_id uuid, p_limit int default 20, p_only_trip uuid default null)
returns table (candidate_trip_id uuid, candidate_user_id uuid, origin_distance_m double precision,
               dest_distance_m double precision, time_diff_min double precision,
               overlap_pct double precision, score double precision)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
#variable_conflict use_column
declare
  v_t      public.trips%rowtype;
  v_r_o    double precision := public.cfg_num('match.origin_radius_m');
  v_r_d    double precision := public.cfg_num('match.dest_radius_m');
  v_win    double precision := public.cfg_num('match.time_window_min');
  v_min_ov double precision := public.cfg_num('match.min_overlap_pct');
  v_max    int              := public.cfg_num('match.max_matches_per_trip')::int;
  v_buf    double precision := public.cfg_num('match.route_buffer_m');
  v_w      jsonb            := public.cfg('match.weights');
  v_compat jsonb            := public.cfg('match.mode_compat');
  v_wd double precision := (v_w ->> 'distance')::double precision;
  v_wt double precision := (v_w ->> 'time')::double precision;
  v_wo double precision := (v_w ->> 'overlap')::double precision;
  v_cutoff timestamptz      := now() - public.cfg_num('trip.expire_after_min') * interval '1 minute';
begin
  select * into v_t from public.trips where id = p_trip_id and deleted_at is null;
  if not found or v_t.status <> 'scheduled' or v_t.depart_at <= v_cutoff then return; end if;
  if (select count(*) from public.matches m where m.status = 'accepted'
        and v_t.id in (m.requester_trip_id, m.target_trip_id)) >= v_max then return; end if;

  return query
  with cand as (
    select o.id as tid, o.user_id as uid, o.route as route,
           ST_Distance(o.origin, v_t.origin) as d_o,
           ST_Distance(o.dest,   v_t.dest)   as d_d,
           (abs(extract(epoch from (o.depart_at - v_t.depart_at))) / 60.0)::double precision as dt
      from public.trips o
      join public.profiles p on p.id = o.user_id and p.deleted_at is null
     where o.status = 'scheduled' and o.deleted_at is null
       and o.depart_at > v_cutoff                                   -- T5.14: expired but not yet swept by cron
       and o.user_id <> v_t.user_id
       and (p_only_trip is null or o.id = p_only_trip)
       and ST_DWithin(o.origin, v_t.origin, v_r_o)
       and ST_DWithin(o.dest,   v_t.dest,   v_r_d)
       and o.depart_at between v_t.depart_at - v_win * interval '1 minute'
                           and v_t.depart_at + v_win * interval '1 minute'
       and (v_compat -> v_t.mode::text) @> to_jsonb(o.mode::text)
       and not exists (select 1 from public.blocks b
                        where (b.blocker_id = v_t.user_id and b.blocked_id = o.user_id)
                           or (b.blocker_id = o.user_id  and b.blocked_id = v_t.user_id))
       and not exists (select 1 from public.matches m              -- only a still-pending pair stays visible
                        where m.status <> 'pending'
                          and ((m.requester_trip_id = v_t.id and m.target_trip_id = o.id)
                            or (m.requester_trip_id = o.id  and m.target_trip_id = v_t.id)))
       and (select count(*) from public.matches m where m.status = 'accepted'
              and o.id in (m.requester_trip_id, m.target_trip_id)) < v_max
  ), scored as (
    select c.tid, c.uid, c.d_o, c.d_d, c.dt,
           public.route_overlap_pct(v_t.route, c.route, v_buf) as ov
      from cand c
  )
  select s.tid, s.uid, s.d_o, s.d_d, s.dt, s.ov,
         100.0 * ( v_wd * (1 - least(1.0, (s.d_o / v_r_o + s.d_d / v_r_d) / 2.0))
                 + v_wt * (1 - s.dt / nullif(v_win, 0))
                 + v_wo * (s.ov / 100.0) ) / nullif(v_wd + v_wt + v_wo, 0)
    from scored s
   where s.ov >= v_min_ov
   order by 7 desc, s.tid asc
   limit p_limit;
end $$;

-- grants: create or replace keeps existing privileges; re-assert the intended surface (idempotent)
revoke execute on function public.match_candidates(uuid, int, uuid) from public, anon, authenticated;
