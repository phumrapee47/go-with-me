-- =====================================================================================================
-- 0012 (DRAFT - NOT APPLIED): Round 7 Stage B - US-44 (vibe tags & daily mood, per-trip) + US-45 (same-org
-- switch + women-only switch). Delta on top of 0001-0011. Design: docs/design-roles.md section 14.
-- Idempotent (re-runnable). Tests: supabase/tests/round7.sql. Depends on 0011 (device_tokens/push_outbox exist,
-- used only for the auto-cancel notice; no other coupling).
--
-- What it does
--   1. trips.vibe_tags / mood_text / mood_set_at: bound to the TRIP (Q5), not profiles - auto-cleared at trip end
--      or 24h, whichever first. Allow-list + mood guard enforced by a trigger (config-driven, so product can edit
--      the tag list without a migration); NOT a CHECK constraint (CHECK cannot safely read app_config - see 14.4).
--   2. profiles.gender: self-view-only (never added to the profiles SELECT column grant from 0008/0009 - a
--      matched partner can already read that whole row). Read back only via get_my_gender(); write is a plain
--      owner-gated UPDATE (existing profiles RLS), which a trigger turns into the Q7 auto-cancel cascade.
--   3. trips.same_org_only / women_only: per-trip switches (same level as trips.max_dropoff_m, for the same
--      reason - 1:1 with the trip, guarded at write time, no cache). See design-roles.md 14.3 for why these are
--      NOT extra `find_matches`/`match_candidates` parameters despite the requirements draft's "e.g. p_same_org
--      boolean" suggestion.
--   4. `_niche_filters_ok(trip_a, trip_b)`: ONE predicate, symmetric, re-evaluated live (never cached) against
--      `verifications`/`profiles.gender` every time - reused by match_candidates (search-time visibility) AND by
--      a matches trigger (request/accept-time enforcement), so no existing RPC body (request_match, respond_match,
--      _accept_match) needs to change.
--   5. (14.8-5/14.8-6, closing the two open questions before handoff to Dart) `get_trip_card` gains vibe_tags/
--      mood_text (drop+create - return type changed), `export_my_data` gains a device_tokens key (create or
--      replace - jsonb return type unchanged; gender/vibe_tags/mood_text need no explicit key, see section 8's
--      comment), and `purge_expired_data` gains the 24h vibe/mood clear that was promised in section 3's comment
--      but not actually added until now.
-- =====================================================================================================

-- 1. Config ----------------------------------------------------------------------------------------------------
insert into public.app_config (key, value, description, is_public) values
  ('vibe.tags_driver', '["#เปิดแอร์เย็น","#เปิดเพลงฟังเพลิน","#ขับนิ่มไม่ซิ่ง","#ไม่สูบบุหรี่","#มีที่เก็บกระเป๋า"]',
     'US-44: allow-list of vibe tags for role=driver / non-car trips shown as driver-style', true),
  ('vibe.tags_rider',  '["#คุยเก่ง","#ขอพักสายตาเงียบๆ","#ฟังเพลงสากล","#สายประหยัด","#พร้อมแชร์เรื่องเล่า"]',
     'US-44: allow-list of vibe tags for role=rider / peer trips', true),
  ('vibe.max_tags',     '3', 'US-44: max vibe tags per trip', true),
  ('mood.max_len',      '35', 'US-44: max mood_text length', true),
  ('mood.blocklist_words', '["เหี้ย","สัส","ควย"]',
     'US-44/Q6: small profanity blocklist for mood_text, checked client AND server (cheap guard, not full moderation)', true)
on conflict (key) do nothing;

-- 2. profiles.gender ---------------------------------------------------------------------------------------------
alter table public.profiles add column if not exists gender text;
do $$ begin
  alter table public.profiles add constraint profiles_gender_chk check (gender is null or gender in ('female','male','other'));
exception when duplicate_object then null; end $$;
-- Write: owner-gated by the existing profiles RLS/UPDATE policy; a plain column grant (same shape as
-- display_name/avatar_path/locale from 0001, extended in 0008) - no new RPC needed to WRITE or CLEAR it.
grant update (gender) on public.profiles to authenticated;
-- Read: deliberately NOT added to the profiles SELECT column grant (0008/0009's explicit column list) - that
-- grant is what lets a MATCHED PARTNER read the rest of the row, so adding gender there would leak it. Self-view
-- only via get_my_gender() (same shape as get_my_role_state, 0008).
create or replace function public.get_my_gender() returns text
language sql stable security definer set search_path = public, pg_temp as $$
  select gender from public.profiles where id = auth.uid()
$$;
revoke execute on function public.get_my_gender() from public, anon;
grant execute on function public.get_my_gender() to authenticated;

-- Q7: clearing/changing gender away from 'female' turns off women_only on this user's own trips AND auto-cancels
-- any pending/accepted match that depends on a women_only trip of theirs - a women_only match is a specific safety
-- promise; once the condition is false it must not be left dangling. The chat note is the SAME neutral copy
-- design-roles.md 5.6 uses for auto-close ("system.match_cancelled") - never the real reason.
create or replace function public.profiles_gender_guard() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_match record;
begin
  if old.gender = 'female' and new.gender is distinct from 'female' then
    update public.trips set women_only = false where user_id = new.id and women_only;
    for v_match in
      select m.id from public.matches m
      join public.trips ta on ta.id = m.requester_trip_id
      join public.trips tb on tb.id = m.target_trip_id
      where m.status in ('pending', 'accepted')
        and (ta.user_id = new.id or tb.user_id = new.id)
        and (ta.women_only or tb.women_only)
    loop
      update public.matches set status = 'cancelled', responded_at = now() where id = v_match.id;
      insert into public.chat_messages (match_id, sender_id, kind, body)
        values (v_match.id, null, 'system', 'ระบบยกเลิกคำขอนี้เนื่องจากเงื่อนไขการจับคู่พิเศษไม่ครบแล้ว');  -- neutral, no gender detail
    end loop;
  end if;
  return new;
end $$;
drop trigger if exists trg_profiles_gender_guard on public.profiles;
create trigger trg_profiles_gender_guard after update of gender on public.profiles
  for each row execute function public.profiles_gender_guard();
revoke execute on function public.profiles_gender_guard() from public, anon, authenticated;

-- 3. trips: vibe tags, mood, same-org switch, women-only switch --------------------------------------------------
alter table public.trips add column if not exists vibe_tags   text[];
-- BUGFIX (found verifying 0011+0012, round7.sql test G5): plain `text`, not varchar(35). The length limit is meant
-- to be config-driven (mood.max_len, checked in trips_vibe_mood_guard below) "so product can edit... without a
-- migration" (section 3 comment) - but a varchar(35) column enforces its OWN hard cap at the type level, which
-- Postgres applies while building the row BEFORE the BEFORE INSERT/UPDATE trigger ever runs. So today, with
-- mood.max_len = 35, any string over 35 chars never reaches the trigger's nicer 'GWM_MOOD_INVALID' error at all -
-- it fails first with a raw "value too long for type character varying(35)" (sqlstate 22001), and if product ever
-- raises mood.max_len past 35 without a migration (the whole point of making it config-driven), the column would
-- still silently cap it at 35 regardless of the new config value.
alter table public.trips add column if not exists mood_text   text;
alter table public.trips add column if not exists mood_set_at timestamptz;
alter table public.trips add column if not exists same_org_only boolean not null default false;
alter table public.trips add column if not exists women_only    boolean not null default false;
do $$ begin
  alter table public.trips add constraint trips_mood_consistency check ((mood_text is null) = (mood_set_at is null));
exception when duplicate_object then null; end $$;

grant insert (vibe_tags, mood_text, same_org_only, women_only), update (vibe_tags, mood_text, same_org_only, women_only)
  on public.trips to authenticated;   -- values still validated by triggers below before they land

-- config-driven allow-list + cheap PII/profanity guard (Q6). A trigger, not a CHECK, because CHECK constraints
-- must not depend on other tables and app_config needs to stay editable by product without a migration.
create or replace function public.trips_vibe_mood_guard() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_allowed jsonb; v_tag text; v_max int := public.cfg_num('vibe.max_tags')::int;
        v_blocklist jsonb := public.cfg('mood.blocklist_words'); v_word text; v_low text;
begin
  if new.vibe_tags is not null then
    if array_length(new.vibe_tags, 1) > v_max then raise exception 'GWM_VIBE_TAG_INVALID' using errcode = 'P0001'; end if;
    v_allowed := case when new.role = 'driver' then public.cfg('vibe.tags_driver') else public.cfg('vibe.tags_rider') end;
    foreach v_tag in array new.vibe_tags loop
      if not (v_allowed @> to_jsonb(v_tag)) then raise exception 'GWM_VIBE_TAG_INVALID' using errcode = 'P0001'; end if;
    end loop;
  end if;

  if new.mood_text is not null then
    if char_length(new.mood_text) > public.cfg_num('mood.max_len')::int then
      raise exception 'GWM_MOOD_INVALID' using errcode = 'P0001';
    end if;
    if new.mood_text ~ '[0-9]{8,}' then raise exception 'GWM_MOOD_INVALID' using errcode = 'P0001'; end if;  -- Q6: phone-like digit run
    v_low := lower(new.mood_text);
    for v_word in select jsonb_array_elements_text(v_blocklist) loop
      if v_low like '%' || lower(v_word) || '%' then raise exception 'GWM_MOOD_INVALID' using errcode = 'P0001'; end if;
    end loop;
    if old.mood_text is distinct from new.mood_text then new.mood_set_at := now(); end if;
  else
    new.mood_set_at := null;   -- cleared by the user before the 24h/trip-end window
  end if;
  return new;
end $$;
drop trigger if exists trg_trips_vibe_mood_guard on public.trips;
create trigger trg_trips_vibe_mood_guard before insert or update of vibe_tags, mood_text on public.trips
  for each row execute function public.trips_vibe_mood_guard();
revoke execute on function public.trips_vibe_mood_guard() from public, anon, authenticated;

-- clear vibe/mood the moment a trip ends (the OTHER half of the 24h-or-trip-end rule; the 24h half lives in
-- purge_expired_data below). A BEFORE trigger on the SAME row avoids a second UPDATE statement / re-entrancy.
create or replace function public.trips_vibe_clear_on_end() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if new.status in ('completed','cancelled','expired') and old.status not in ('completed','cancelled','expired') then
    new.vibe_tags := null; new.mood_text := null; new.mood_set_at := null;
  end if;
  return new;
end $$;
drop trigger if exists trg_trips_vibe_clear_on_end on public.trips;
create trigger trg_trips_vibe_clear_on_end before update of status on public.trips
  for each row execute function public.trips_vibe_clear_on_end();
revoke execute on function public.trips_vibe_clear_on_end() from public, anon, authenticated;

-- write-time gates: same_org_only/women_only can only be turned ON when the live condition holds NOW. Q8 still
-- applies to SEARCH time (see _niche_filters_ok below, re-checked on every find_matches call) - this is just the
-- "you can't flip the switch on if you were never eligible" guard, so the UI's own error copy makes sense.
create or replace function public.trips_niche_switch_guard() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if new.same_org_only and not exists (
       select 1 from public.verifications v where v.user_id = new.user_id and v.kind = 'organization' and v.status = 'verified') then
    raise exception 'GWM_ORG_VERIFICATION_REQUIRED' using errcode = 'P0001';
  end if;
  if new.women_only and coalesce((select gender from public.profiles where id = new.user_id), '') <> 'female' then
    raise exception 'GWM_GENDER_REQUIRED' using errcode = 'P0001';
  end if;
  return new;
end $$;
drop trigger if exists trg_trips_niche_switch_guard on public.trips;
create trigger trg_trips_niche_switch_guard before insert or update of same_org_only, women_only on public.trips
  for each row execute function public.trips_niche_switch_guard();
revoke execute on function public.trips_niche_switch_guard() from public, anon, authenticated;

-- 4. Shared eligibility predicate (search-time AND request/accept-time; symmetric; live, never cached) -----------
create or replace function public._niche_filters_ok(p_trip_a uuid, p_trip_b uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((
    select
      (not (ta.same_org_only or tb.same_org_only) or (
        ta.same_org_only and tb.same_org_only and exists (
          select 1 from public.verifications va join public.verifications vb on vb.org_suffix = va.org_suffix
           where va.user_id = ta.user_id and va.kind = 'organization' and va.status = 'verified'
             and vb.user_id = tb.user_id and vb.kind = 'organization' and vb.status = 'verified')
      ))
      and
      (not (ta.women_only or tb.women_only) or (
        ta.women_only and tb.women_only and pa.gender = 'female' and pb.gender = 'female'
      ))
    from public.trips ta, public.trips tb, public.profiles pa, public.profiles pb
    where ta.id = p_trip_a and tb.id = p_trip_b and pa.id = ta.user_id and pb.id = tb.user_id
  ), false)
$$;
revoke execute on function public._niche_filters_ok(uuid, uuid) from public, anon, authenticated;   -- internal only

-- match_candidates: SAME signature/return type as 0009 (CREATE OR REPLACE, no drop/grant dance needed) - the
-- 0009 body verbatim plus ONE extra AND in the `cand` CTE's WHERE clause.
create or replace function public.match_candidates(p_trip_id uuid, p_limit int default 20, p_only_trip uuid default null)
returns table (candidate_trip_id uuid, candidate_user_id uuid, origin_distance_m double precision,
               dest_distance_m double precision, time_diff_min double precision,
               overlap_pct double precision, score double precision, detour_m double precision)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
#variable_conflict use_column
declare
  v_t      public.trips%rowtype;
  v_car    boolean;
  v_cor    boolean := (public.cfg('match.car_rule') #>> '{}') = 'corridor';
  v_r_o    double precision := public.cfg_num('match.origin_radius_m');
  v_r_d    double precision := public.cfg_num('match.dest_radius_m');
  v_roc    double precision := public.cfg_num('match.car_origin_radius_m');
  v_dmax   double precision := public.cfg_num('match.car_dest_radius_max_m');
  v_win    double precision := public.cfg_num('match.time_window_min');
  v_min_ov double precision := public.cfg_num('match.min_overlap_pct');
  v_max    int              := public.cfg_num('match.max_matches_per_trip')::int;
  v_buf    double precision := public.cfg_num('match.route_buffer_m');
  v_corr   double precision := public.cfg_num('match.car_corridor_m');
  v_det    double precision := public.cfg_num('match.car_max_detour_m');
  v_w      jsonb            := public.cfg('match.weights');
  v_cw     jsonb            := public.cfg('match.car_weights');
  v_compat jsonb            := public.cfg('match.mode_compat');
  v_wd double precision := (v_w ->> 'distance')::double precision;
  v_wt double precision := (v_w ->> 'time')::double precision;
  v_wo double precision := (v_w ->> 'overlap')::double precision;
  v_cd double precision := (v_cw ->> 'detour')::double precision;
  v_ct double precision := (v_cw ->> 'time')::double precision;
  v_cc double precision := (v_cw ->> 'coverage')::double precision;
  v_cutoff timestamptz      := now() - public.cfg_num('trip.expire_after_min') * interval '1 minute';
  v_lim    int;
begin
  select * into v_t from public.trips where id = p_trip_id and deleted_at is null;
  if not found or v_t.status <> 'scheduled' or v_t.depart_at <= v_cutoff then return; end if;
  v_car := (v_t.mode = 'car');
  if v_car and v_t.role is null then return; end if;
  v_lim := case when v_car then public.car_seats() else v_max end;
  if (select count(*) from public.matches m where m.status = 'accepted'
        and v_t.id in (m.requester_trip_id, m.target_trip_id)) >= v_lim then return; end if;

  return query
  with cand as (
    select o.id as tid, o.user_id as uid, o.created_at as cat, o.route as route, o.origin as oo, o.dest as od,
           o.max_dropoff_m as mdo,
           ST_Distance(o.origin, v_t.origin) as p_d_o,
           ST_Distance(o.dest,   v_t.dest)   as p_d_d,
           (abs(extract(epoch from (o.depart_at - v_t.depart_at))) / 60.0)::double precision as dt
      from public.trips o
      join public.profiles p on p.id = o.user_id and p.deleted_at is null
     where o.status = 'scheduled' and o.deleted_at is null
       and o.depart_at > v_cutoff
       and o.user_id <> v_t.user_id
       and (p_only_trip is null or o.id = p_only_trip)
       and case when v_car and v_cor then ST_DWithin(o.route, v_t.route, v_corr)
                when v_car then ST_DWithin(o.origin, v_t.origin, v_roc) and ST_DWithin(o.dest, v_t.dest, v_dmax)
                else ST_DWithin(o.origin, v_t.origin, v_r_o) and ST_DWithin(o.dest, v_t.dest, v_r_d) end
       and o.depart_at between v_t.depart_at - v_win * interval '1 minute'
                           and v_t.depart_at + v_win * interval '1 minute'
       and case when v_car
                then o.mode = 'car' and o.role is not null and o.role <> v_t.role
                else o.mode <> 'car' and (v_compat -> v_t.mode::text) @> to_jsonb(o.mode::text)
           end
       and not exists (select 1 from public.blocks b
                        where (b.blocker_id = v_t.user_id and b.blocked_id = o.user_id)
                           or (b.blocker_id = o.user_id  and b.blocked_id = v_t.user_id))
       and not exists (select 1 from public.matches m
                        where m.status <> 'pending' and not (m.status = 'cancelled' and m.auto_closed)
                          and ((m.requester_trip_id = v_t.id and m.target_trip_id = o.id)
                            or (m.requester_trip_id = o.id  and m.target_trip_id = v_t.id)))
       and (select count(*) from public.matches m where m.status = 'accepted'
              and o.id in (m.requester_trip_id, m.target_trip_id)) < v_lim
       and public._niche_filters_ok(v_t.id, o.id)                                    -- NEW (0012, US-45)
  ), scored as (
    select c.tid, c.uid, c.cat, c.dt,
           case when v_car then ev.d_o else c.p_d_o end as d_o,
           case when v_car then ev.d_d else c.p_d_d end as d_d,
           case when v_car then ev.ov
                else public.route_overlap_pct(v_t.route, c.route, v_buf) end as ov,
           ev.detour_m as dm, ev.stage as stage, ev.lim as dlim
      from cand c
      left join lateral (
        select e.* from public._car_rule_eval(
                 case when v_t.role = 'driver' then v_t.origin else c.oo end,
                 case when v_t.role = 'driver' then v_t.dest   else c.od end,
                 case when v_t.role = 'driver' then v_t.route  else c.route end,
                 case when v_t.role = 'driver' then v_t.max_dropoff_m else c.mdo end,
                 case when v_t.role = 'driver' then c.oo       else v_t.origin end,
                 case when v_t.role = 'driver' then c.od       else v_t.dest end,
                 case when v_t.role = 'driver' then c.route    else v_t.route end) e
         where v_car) ev on true
  )
  select s.tid, s.uid, s.d_o, s.d_d, s.dt, s.ov,
         case when v_car and v_cor then
                100.0 * ( v_cd * (1 - least(1.0, s.dm / nullif(v_det, 0)))
                        + v_ct * (1 - s.dt / nullif(v_win, 0))
                        + v_cc * (s.ov / 100.0) ) / nullif(v_cd + v_ct + v_cc, 0)
              when v_car then
                100.0 * ( v_wd * (1 - least(1.0, (s.d_o / nullif(v_roc, 0) + s.d_d / nullif(s.dlim, 0)) / 2.0))
                        + v_wt * (1 - s.dt / nullif(v_win, 0))
                        + v_wo * (s.ov / 100.0) ) / nullif(v_wd + v_wt + v_wo, 0)
              else
                100.0 * ( v_wd * (1 - least(1.0, (s.d_o / v_r_o + s.d_d / v_r_d) / 2.0))
                        + v_wt * (1 - s.dt / nullif(v_win, 0))
                        + v_wo * (s.ov / 100.0) ) / nullif(v_wd + v_wt + v_wo, 0)
         end as score,
         s.dm
    from scored s
   where case when v_car then s.stage = 0 else s.ov >= v_min_ov end
   order by 7 desc, (case when v_car then s.cat end) asc, s.tid asc
   limit p_limit;
end $$;
revoke execute on function public.match_candidates(uuid, int, uuid) from public, anon, authenticated;

-- request/accept-time enforcement WITHOUT touching request_match/_accept_match/respond_match: every path that
-- creates or accepts a match does so by writing the `matches` row (INSERT as pending, or UPDATE status), so a
-- single trigger on that table is a strictly-cannot-be-bypassed gate, reusing the exact same predicate as search.
create or replace function public.matches_niche_guard() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if (tg_op = 'INSERT' and new.status = 'pending')
     or (tg_op = 'UPDATE' and new.status = 'accepted' and old.status is distinct from 'accepted') then
    if not public._niche_filters_ok(new.requester_trip_id, new.target_trip_id) then
      raise exception 'GWM_NOT_ELIGIBLE' using errcode = 'P0001';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_matches_niche_guard on public.matches;
create trigger trg_matches_niche_guard before insert or update of status on public.matches
  for each row execute function public.matches_niche_guard();
revoke execute on function public.matches_niche_guard() from public, anon, authenticated;

-- 5. Indexes -------------------------------------------------------------------------------------------------
-- verifications(user_id, kind, status) already exists as the table's implicit PK-adjacent lookup via
-- `unique (user_id, kind)` (0001) - the org-match EXISTS join above hits that unique index directly, no new index
-- needed. profiles(gender) gets NO index: it is read only through _niche_filters_ok's per-row equality check
-- against two already-identified trip owners (≤ 1 row lookup each via the profiles PK), never scanned/filtered
-- over the whole table - an index would add write cost for zero read benefit (see design-roles.md 14.5 EXPLAIN notes).
create index if not exists trips_niche_flags_idx on public.trips (user_id) where same_org_only or women_only;
  -- cheap support for profiles_gender_guard's per-user "which of my trips are women_only" scan on gender change

-- 6. purge_expired_data: the 24h HALF of the vibe/mood auto-clear rule (Q5) - the trip-end half is
-- trg_trips_vibe_clear_on_end above (section 3). This is the piece the section-3 comment called "below" but that
-- was never actually added until now (round7.sql test H1 already asserted it - closing that gap here, not in a
-- new 0013). CREATE OR REPLACE only: return type (jsonb) is unchanged, so no drop/grant dance. Body = 0011's
-- verbatim (supabase/migrations/0011_push_pindrop.sql, push_outbox retention added there) plus ONE new clause and
-- ONE new key in the returned jsonb - nothing removed, nothing else reordered.
create or replace function public.purge_expired_data() returns jsonb
language plpgsql security definer set search_path = public, extensions, auth, pg_temp as $$
declare
  v_loc_days int := public.cfg_num('retention.location_days')::int;
  v_del_days int := public.cfg_num('retention.account_deletion_days')::int;
  v_sos_days int := public.cfg_num('retention.sos_precise_days')::int;
  v_expired int; v_loc int; v_reduced int; v_trips int; v_users int; v_sos int; v_rev int; v_push int; v_mood int;
begin
  update public.trips set status = 'expired'
   where status = 'scheduled' and depart_at < now() - public.cfg_num('trip.expire_after_min') * interval '1 minute';
  get diagnostics v_expired = row_count;

  delete from public.trip_locations tl using public.trips t
   where t.id = tl.trip_id and (t.deleted_at is not null or t.ended_at < now() - v_loc_days * interval '1 day');
  get diagnostics v_loc = row_count;

  update public.trips set origin = public.blur_point(origin), dest = public.blur_point(dest),
         route = ST_MakeLine(public.blur_point(origin)::geometry, public.blur_point(dest)::geometry)::geography,
         origin_label = null, dest_label = null, last_location = null, last_location_at = null, precision_reduced_at = now()
   where ended_at < now() - v_loc_days * interval '1 day' and precision_reduced_at is null;
  get diagnostics v_reduced = row_count;

  update public.sos_events set location = public.blur_point(location), precision_reduced_at = now()
   where created_at < now() - v_sos_days * interval '1 day' and precision_reduced_at is null and location is not null;
  get diagnostics v_sos = row_count;
  update public.sos_events set vehicle_snapshot = null
   where created_at < now() - v_sos_days * interval '1 day' and vehicle_snapshot is not null;

  delete from public.match_outcomes
   where created_at < now() - public.cfg_num('retention.match_outcome_months') * interval '1 month';

  v_rev := public._reveal_due_reviews();

  -- (0011, US-42): drain hygiene - SENT rows are audit trail only for a few days; UNSENT rows this old mean the
  -- Edge Function has been down/unapproved for a week - drop rather than send a week-stale "new message" push.
  delete from public.push_outbox where sent_at is not null
    and sent_at < now() - public.cfg_num('push.outbox_sent_retention_days') * interval '1 day';
  delete from public.push_outbox where sent_at is null
    and created_at < now() - public.cfg_num('push.outbox_stale_retention_days') * interval '1 day';
  get diagnostics v_push = row_count;

  -- NEW (0012, US-44/Q5): vibe_tags/mood_text/mood_set_at are per-trip and must not outlive 24h even when the
  -- trip itself is still 'scheduled'/'in_progress' (trg_trips_vibe_clear_on_end only covers the trip-END case).
  update public.trips set vibe_tags = null, mood_text = null, mood_set_at = null
   where mood_set_at < now() - interval '24 hours';
  get diagnostics v_mood = row_count;

  delete from public.trips where deleted_at < now() - v_loc_days * interval '1 day';
  get diagnostics v_trips = row_count;

  delete from public.trip_shares where expires_at < now() - interval '30 days' or revoked_at < now() - interval '30 days';
  delete from public.api_throttle where window_start < now() - interval '1 day';

  delete from auth.users u using public.profiles p
   where p.id = u.id and p.deleted_at < now() - v_del_days * interval '1 day';
  get diagnostics v_users = row_count;

  return jsonb_build_object('expired_trips', v_expired, 'deleted_locations', v_loc, 'reduced_trips', v_reduced,
                            'reduced_sos', v_sos, 'deleted_trips', v_trips, 'deleted_users', v_users,
                            'revealed_reviews', v_rev, 'purged_push_outbox', v_push, 'cleared_mood', v_mood);
end $$;

-- 7. get_trip_card (14.8-5): read path confirmed against lib/features/matching/data/supabase_match_repositories.dart:141
-- (`_client.rpc('get_trip_card', ...)`) and docs/design-roles.md 14.4/595 - this IS the RPC the Dart CommuteCardDeck
-- reads trip summaries from; no separate view, no find_matches/match_candidates change needed (those already return
-- no per-trip vibe/mood data by design, per design-roles.md line 576). Return type changes (2 new OUT columns) so
-- CREATE OR REPLACE is not legal here (Postgres rejects changing a TABLE-returning function's columns in place,
-- same reason 0006/0009 dropped it) - DROP + CREATE, same as those two rounds, with the grant re-issued after
-- (dropping a function drops its ACL). Body is the 0009 definition verbatim (see
-- supabase/migrations/0009_corridor_matching_avatars_ratings.sql:335-358) with only two additions: the two new
-- output columns, and a live mood-staleness recheck (defensive: does not rely on purge_expired_data having already
-- run this cycle - see section 6) so a not-yet-purged expired mood is never shown to the OTHER party even for the
-- few minutes before the next purge_expired_data run. vibe_tags needs no such recheck: it has no independent
-- expiry anchor distinct from mood_set_at in this draft (see section 3) and is cleared in full alongside mood_text
-- by both auto-clear paths (trip-end trigger, section 6's 24h purge) - it is never left behind once mood_text is
-- cleared. Every existing column and existing behavior (forbidden check, car-mode dest privacy blur) is unchanged.
drop function if exists public.get_trip_card(uuid);
create function public.get_trip_card(p_trip_id uuid)
returns table (trip_id uuid, display_name text, badges jsonb, mode public.travel_mode, depart_at timestamptz, status public.trip_status,
               approx_origin_lat double precision, approx_origin_lng double precision,
               approx_dest_lat double precision, approx_dest_lng double precision, role public.trip_role,
               vibe_tags text[], mood_text text)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
#variable_conflict use_column
begin
  if not exists (
       select 1 from public.trips t where t.id = p_trip_id and t.user_id = auth.uid())
     and not exists (
       select 1 from public.matches m
        where m.status in ('pending','accepted') and auth.uid() in (m.requester_id, m.target_id)
          and p_trip_id in (m.requester_trip_id, m.target_trip_id)) then
    raise exception 'GWM_FORBIDDEN' using errcode = '42501';
  end if;
  return query
  select t.id, pr.display_name, public.user_badges(t.user_id), t.mode, t.depart_at, t.status,
         ST_Y(public.blur_point(t.origin)::geometry), ST_X(public.blur_point(t.origin)::geometry),
         case when t.mode = 'car' and t.role = 'rider' and t.user_id <> auth.uid() then null else ST_Y(public.blur_point(t.dest)::geometry) end,
         case when t.mode = 'car' and t.role = 'rider' and t.user_id <> auth.uid() then null else ST_X(public.blur_point(t.dest)::geometry) end,
         t.role,
         t.vibe_tags,
         case when t.mood_text is not null and t.mood_set_at > now() - interval '24 hours' then t.mood_text else null end::text
    from public.trips t join public.profiles pr on pr.id = t.user_id
   where t.id = p_trip_id;
end $$;
revoke execute on function public.get_trip_card(uuid) from public, anon;
grant execute on function public.get_trip_card(uuid) to authenticated;

-- 8. export_my_data (14.8-6): gender/vibe_tags/mood_text need NO body change to appear - read in full (see
-- supabase/migrations/0009_corridor_matching_avatars_ratings.sql:1035-1065) before writing this: the 'profile' key
-- is `to_jsonb(p) - <explicit exclusion list>` (whole row minus a few fields) and 'trips' is the same
-- whole-row-minus-exclusions pattern, and neither exclusion list mentions gender/vibe_tags/mood_text/mood_set_at/
-- same_org_only/women_only - so those columns surface automatically once they exist (sections 2/3 above), no
-- explicit key needed, no risk of double-counting. Return type (jsonb) is unchanged so CREATE OR REPLACE is legal
-- (unlike get_trip_card above). The one real gap: device_tokens had no key at all - added below, own rows only,
-- with the raw token value stripped (the user has no use for that opaque push identifier back, and PDPA "right to
-- access own data" is satisfied by knowing which platforms/when without also re-exporting a live credential-shaped
-- value). Every existing key, exclusion, and computed field is preserved verbatim.
create or replace function public.export_my_data() returns jsonb
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select jsonb_build_object(
    'profile',  (select to_jsonb(p) - 'driver_registered' - 'driver_registered_at' - 'licence_declared_at'
                        - 'licence_declaration_version' - 'active_role'
                   from public.profiles p where p.id = auth.uid()),
    'driver_registration', (select jsonb_build_object(
                        'registered', p.driver_registered, 'registered_at', p.driver_registered_at,
                        'licence_declared_at', p.licence_declared_at,
                        'licence_declaration_version', p.licence_declaration_version,
                        'active_role', p.active_role)
                   from public.profiles p where p.id = auth.uid()),
    'consents', coalesce((select jsonb_agg(to_jsonb(c)) from public.consents c where c.user_id = auth.uid()), '[]'),
    'verifications', coalesce((select jsonb_agg(to_jsonb(v)) from public.verifications v where v.user_id = auth.uid()), '[]'),
    'emergency_contacts', coalesce((select jsonb_agg(to_jsonb(e)) from public.emergency_contacts e where e.user_id = auth.uid()), '[]'),
    'trips', coalesce((select jsonb_agg(to_jsonb(t) - 'origin' - 'dest' - 'route' - 'last_location'
                 || jsonb_build_object('origin', ST_AsGeoJSON(t.origin::geometry)::jsonb, 'dest', ST_AsGeoJSON(t.dest::geometry)::jsonb,
                                       'route', ST_AsGeoJSON(t.route::geometry)::jsonb))
                 from public.trips t where t.user_id = auth.uid()), '[]'),
    'sos_events', coalesce((select jsonb_agg(to_jsonb(s) - 'location' || jsonb_build_object('location', ST_AsGeoJSON(s.location::geometry)::jsonb))
                 from public.sos_events s where s.user_id = auth.uid()), '[]'),
    'messages_sent', coalesce((select jsonb_agg(to_jsonb(m)) from public.chat_messages m where m.sender_id = auth.uid()), '[]'),
    'vehicle', (select to_jsonb(v) from public.vehicles v where v.user_id = auth.uid()),
    'device_tokens', coalesce((select jsonb_agg(to_jsonb(d) - 'token') from public.device_tokens d where d.user_id = auth.uid()), '[]'),
    'reviews_written', coalesce((select jsonb_agg(jsonb_build_object('match_id', r.match_id, 'role_reviewed', r.role, 'stars', r.stars,
                          'tags', coalesce((select array_agg(st.tag order by st.tag) from public.review_selected_tags st where st.review_id = r.id), '{}'), 'comment', r.comment, 'created_at', r.created_at))
                 from public.reviews r where r.reviewer_id = auth.uid()), '[]'),
    'reviews_received', coalesce((select jsonb_agg(jsonb_build_object('match_id', r.match_id, 'role', r.role, 'stars', r.stars,
                          'tags', coalesce((select array_agg(st.tag order by st.tag) from public.review_selected_tags st where st.review_id = r.id), '{}'), 'comment', r.comment, 'created_at', r.created_at))
                 from public.reviews r where r.reviewee_id = auth.uid() and (r.revealed_at is not null or r.reveal_at <= now())
                  and r.held_at is null and r.removed_at is null), '[]'))
$$;

notify pgrst, 'reload schema';
