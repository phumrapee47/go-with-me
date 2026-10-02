-- =====================================================================================================
-- 0011 (DRAFT - NOT APPLIED): Round 7 Stage A - US-42 Remote Push Notifications. US-43 (road-snapped pickup
-- pin) needs NO schema change: propose_meeting_point(p_match_id, p_lng, p_lat, p_label) (0006) already accepts
-- arbitrary lng/lat, so OSRM `nearest` snapping is a pure Dart-side change before that existing RPC call.
-- Design: docs/design-roles.md section 14. Idempotent (re-runnable). Tests: supabase/tests/round7.sql.
--
-- What it does
--   1. device_tokens: one row per (user_id, token); written only via register_device_token/unregister_device_token
--      (RPC, not a raw grant) so token churn/validation stays server-controlled; deleted on sign-out (client calls
--      unregister_device_token for its OWN token, Q1: device-bound, not "all devices") and on account deletion.
--   2. push_outbox: append-only queue, service_role only (same shape as storage_purge_queue / claim+complete).
--      Populated entirely by triggers on matches/chat_messages - no existing RPC body is touched.
--   3. Chat-message coalescing (Q2, 60s/match window) is done by the Edge Function consumer at drain time, NOT
--      in SQL (see design-roles.md 14.2 for the reasoning) - this migration only adds the index that makes that
--      batch read cheap.
--   4. "Driver arrived at pickup" (US-33, round 6) is today a plain chat message with a canned body - opaque
--      push payloads cannot key off message text, so message_kind gains a 'driver_arrived' value (sender still
--      present, unlike 'system') and the existing chat insert trigger branches on it. The enum value itself is
--      added by 0011a_message_kind.sql (14.8-1), which must be applied before this file.
--   5. Edge Function drain (service_role + cron secret, same pattern as purge-storage-queue) is OUT OF SCOPE for
--      this SQL migration - it is a separate deployable artifact that needs explicit user approval before deploy
--      (R7.36), same as purge-storage-queue itself (still pending from round 5).
-- =====================================================================================================

-- 1. Enums -------------------------------------------------------------------------------------------------
do $$ begin create type public.device_platform as enum ('android','ios','web'); exception when duplicate_object then null; end $$;
do $$ begin create type public.push_kind as enum
  ('match_requested','match_accepted','chat_message','driver_arrived','match_cancelled');
exception when duplicate_object then null; end $$;

-- message_kind's 'driver_arrived' value is added by 0011a_message_kind.sql, which MUST run (and commit) before
-- this file - DEPENDENCY (14.8-1): a value just added to an enum can be unusable to a statement later in the
-- SAME transaction/migration on some poolers, so it is no longer added here.

-- relax the sender/kind CHECK. 14.8-2: confirmed against the exact source text (no live \d available, draft-only)
-- at supabase/migrations/0001_init.sql:220 -
--   check ((kind = 'user') = (sender_id is not null))
-- - which Postgres stores/renders via pg_get_constraintdef as roughly
--   CHECK (((kind = 'user'::message_kind) = (sender_id IS NOT NULL)))
-- so the pattern below is anchored on the two literal fragments either side of the "=" that pg_get_constraintdef
-- is guaranteed to preserve ("kind = 'user'" and "sender_id is not null"), not a bare "kind"/"sender_id" substring
-- match, to avoid matching an unrelated future CHECK on this table that merely mentions both column names.
-- Scoped by conrelid + contype='c' regardless, so this only ever inspects chat_messages's own CHECK constraints.
do $$
declare v_con text;
begin
  select conname into v_con from pg_constraint
   where conrelid = 'public.chat_messages'::regclass and contype = 'c'
     and pg_get_constraintdef(oid) ilike '%kind = ''user''%) = (sender_id is not null)%';
  if v_con is not null then execute format('alter table public.chat_messages drop constraint %I', v_con); end if;
end $$;
do $$ begin
  alter table public.chat_messages add constraint chat_messages_kind_sender_chk
    check ((kind in ('user','driver_arrived')) = (sender_id is not null));
exception when duplicate_object then null; end $$;

-- BUGFIX (found verifying 0011+0012 together, round7.sql test B3/B4): the CHECK above allows a client-authored
-- 'driver_arrived' row, but two gates that predate 0011 were never updated to match, so a real client insert of
-- either kind still fails before the CHECK is even reached:
--   (a) 0001's column grant `grant insert (match_id, sender_id, body, client_msg_id) on chat_messages` never
--       included `kind` at all, so ANY insert that names the kind column explicitly - including the existing
--       kind = 'user' canned-message path - is rejected with a bare "permission denied for table chat_messages"
--       (a GRANT-level error, checked before RLS).
--   (b) the 0001 RLS policy chat_insert_when_open hard-codes `kind = 'user'` in its WITH CHECK, so even with the
--       grant fixed a driver_arrived row is rejected by RLS - the "ถึงจุดรับแล้ว" canned message (US-33, round 6)
--       is a plain client-authored chat_messages row per design-roles.md 14.8-notes, so the client path must be
--       allowed to use the new kind, not just the AFTER INSERT push trigger reading it.
grant insert (kind) on public.chat_messages to authenticated;
drop policy if exists chat_insert_when_open on public.chat_messages;
create policy chat_insert_when_open on public.chat_messages for insert to authenticated
  with check (sender_id = (select auth.uid()) and kind in ('user', 'driver_arrived') and public.is_chat_open(match_id));

-- 2. Config --------------------------------------------------------------------------------------------------
insert into public.app_config (key, value, description, is_public) values
  ('throttle.device_token_per_hour', '20',  'per-user register_device_token/unregister_device_token calls per hour', false),
  ('push.chat_coalesce_window_s',    '60',  'US-42/Q2: Edge Function drain window to collapse chat_message pushes per match into one', true),
  ('push.outbox_sent_retention_days','3',   'purge_expired_data: delete SENT push_outbox rows older than this', false),
  ('push.outbox_stale_retention_days','7',  'purge_expired_data: drop UNSENT rows this old (drain has failed for too long)', false)
on conflict (key) do nothing;

-- 3. device_tokens ---------------------------------------------------------------------------------------------
create table if not exists public.device_tokens (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  token       text not null check (char_length(token) between 8 and 4096),
  platform    public.device_platform not null,
  updated_at  timestamptz not null default now(),
  created_at  timestamptz not null default now(),
  unique (user_id, token)
);
alter table public.device_tokens enable row level security;
revoke all on public.device_tokens from anon, authenticated;
grant select on public.device_tokens to authenticated;               -- read own rows only, for a future "your devices" screen
drop policy if exists device_tokens_select on public.device_tokens;
create policy device_tokens_select on public.device_tokens for select to authenticated using (user_id = auth.uid());
-- INSERT/UPDATE/DELETE: no client grant at all - only through the two RPCs below (server validates/throttles/normalises).
create index if not exists device_tokens_user_idx on public.device_tokens (user_id);   -- FK + per-user fan-out at send time

create or replace function public.register_device_token(p_token text, p_platform public.device_platform) returns void
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'GWM_UNAUTHENTICATED' using errcode = '42501'; end if;
  if p_token is null or char_length(btrim(p_token)) not between 8 and 4096 then
    raise exception 'GWM_DEVICE_TOKEN_INVALID' using errcode = 'P0001';
  end if;
  perform public._throttle('device_token', public.cfg_num('throttle.device_token_per_hour')::int, 3600);
  insert into public.device_tokens (user_id, token, platform, updated_at)
  values (v_uid, btrim(p_token), p_platform, now())
  on conflict (user_id, token) do update set platform = excluded.platform, updated_at = now();
end $$;

-- idempotent: unregistering a token that is already gone (or was never this user's) is a silent success.
create or replace function public.unregister_device_token(p_token text) returns void
language sql volatile security definer set search_path = public, pg_temp as $$
  delete from public.device_tokens where user_id = auth.uid() and token = btrim(p_token)
$$;

-- service_role only: called by the drain Edge Function when FCM returns NotRegistered/InvalidRegistration for a token.
create or replace function public.revoke_device_token(p_user_id uuid, p_token text) returns void
language sql volatile security definer set search_path = public, pg_temp as $$
  delete from public.device_tokens where user_id = p_user_id and token = p_token
$$;

-- 4. push_outbox -----------------------------------------------------------------------------------------------
create table if not exists public.push_outbox (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,   -- recipient
  match_id    uuid not null references public.matches(id) on delete cascade,    -- every US-42 event kind is match-scoped
  kind        public.push_kind not null,
  created_at  timestamptz not null default now(),
  sent_at     timestamptz,
  attempts    smallint not null default 0,
  last_error  text
);
alter table public.push_outbox enable row level security;
revoke all on public.push_outbox from anon, authenticated;            -- NO client access at all (service_role/Edge Function only)
-- drain query: unsent rows oldest-first, and per-match/per-kind grouping for the coalesce read in the Edge Function
create index if not exists push_outbox_pending_idx on public.push_outbox (created_at) where sent_at is null;
create index if not exists push_outbox_pending_match_kind_idx on public.push_outbox (match_id, kind, created_at) where sent_at is null;
create index if not exists push_outbox_user_idx on public.push_outbox (user_id);    -- FK (cascade on account deletion)
create index if not exists push_outbox_match_idx on public.push_outbox (match_id);  -- FK (cascade on match delete - never happens today, defensive)

-- claim/complete mirrors claim_storage_purge/complete_storage_purge (0009 12.3): SKIP LOCKED so two overlapping
-- drain runs never double-send, and attempts increments even if the Edge Function crashes before completing.
create or replace function public.claim_push_outbox(p_limit int default 200)
returns table (id uuid, user_id uuid, match_id uuid, kind public.push_kind, created_at timestamptz)
language plpgsql volatile security definer set search_path = public, pg_temp as $$
begin
  return query
  with c as (
    select o.id from public.push_outbox o
     where o.sent_at is null
     order by o.created_at
     limit least(greatest(coalesce(p_limit, 200), 1), 1000)
     for update skip locked)
  update public.push_outbox o set attempts = o.attempts + 1 from c where o.id = c.id
  returning o.id, o.user_id, o.match_id, o.kind, o.created_at;
end $$;

-- the Edge Function calls this once per FCM batch send, passing EVERY claimed id it coalesced into that one
-- notification (Q2: coalescing collapses N chat_message rows into 1 FCM call, but all N rows are marked sent).
create or replace function public.complete_push_outbox(p_ids uuid[]) returns int
language sql volatile security definer set search_path = public, pg_temp as $$
  with d as (update public.push_outbox set sent_at = now(), last_error = null
              where id = any (p_ids) and sent_at is null returning 1)
  select count(*)::int from d
$$;

create or replace function public.fail_push_outbox(p_ids uuid[], p_error text) returns int
language sql volatile security definer set search_path = public, pg_temp as $$
  with d as (update public.push_outbox set last_error = left(p_error, 300)
              where id = any (p_ids) and sent_at is null returning 1)          -- stays unsent -> retried next drain
  select count(*)::int from d
$$;

revoke execute on function public.claim_push_outbox(int), public.complete_push_outbox(uuid[]),
                           public.fail_push_outbox(uuid[], text), public.revoke_device_token(uuid, text)
                           from public, anon, authenticated;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.claim_push_outbox(int), public.complete_push_outbox(uuid[]),
                              public.fail_push_outbox(uuid[], text), public.revoke_device_token(uuid, text)
      to service_role;
  end if;
end $$;

-- 5. Triggers: matches/chat_messages -> push_outbox (no existing RPC body touched) --------------------------------

-- new request (always INSERTed as 'pending' by request_match) -> notify the target only.
create or replace function public.push_outbox_match_requested() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if new.status = 'pending' then
    insert into public.push_outbox (user_id, match_id, kind) values (new.target_id, new.id, 'match_requested');
  end if;
  return new;
end $$;
drop trigger if exists trg_push_outbox_match_requested on public.matches;
create trigger trg_push_outbox_match_requested after insert on public.matches
  for each row execute function public.push_outbox_match_requested();

-- accepted -> notify the requester (the target already knows, they just tapped accept); cancelled/declined -> notify
-- both participants. This also fires for auto-closed pending requests (status -> cancelled, auto_closed = true):
-- accepted per design-roles.md 5.6 ("the sender may infer the Driver matched someone else") - not a new leak.
create or replace function public.push_outbox_match_status() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if new.status is distinct from old.status then
    if new.status = 'accepted' then
      insert into public.push_outbox (user_id, match_id, kind) values (new.requester_id, new.id, 'match_accepted');
    elsif new.status in ('cancelled', 'declined') then
      insert into public.push_outbox (user_id, match_id, kind) values (new.requester_id, new.id, 'match_cancelled');
      insert into public.push_outbox (user_id, match_id, kind) values (new.target_id, new.id, 'match_cancelled');
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_push_outbox_match_status on public.matches;
create trigger trg_push_outbox_match_status after update of status on public.matches
  for each row execute function public.push_outbox_match_status();

-- one row per chat message; 'driver_arrived' is its own kind so the client renders the right copy without ever
-- reading body text (payload stays opaque per US-42 AC). Coalescing 'chat_message' rows is done at drain time.
create or replace function public.push_outbox_chat() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_m public.matches%rowtype; v_recipient uuid;
begin
  if new.kind not in ('user', 'driver_arrived') then return new; end if;
  select * into v_m from public.matches where id = new.match_id;
  if not found then return new; end if;
  v_recipient := case when new.sender_id = v_m.requester_id then v_m.target_id else v_m.requester_id end;
  insert into public.push_outbox (user_id, match_id, kind)
  values (v_recipient, new.match_id, case when new.kind = 'driver_arrived' then 'driver_arrived'::public.push_kind
                                           else 'chat_message'::public.push_kind end);
  return new;
end $$;
drop trigger if exists trg_push_outbox_chat on public.chat_messages;
create trigger trg_push_outbox_chat after insert on public.chat_messages
  for each row execute function public.push_outbox_chat();

revoke execute on function public.push_outbox_match_requested(), public.push_outbox_match_status(), public.push_outbox_chat()
                           from public, anon, authenticated;   -- trigger functions, never called directly

-- 6. request_account_deletion (0009 body) + device_tokens cleanup ------------------------------------------------
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
  delete from public.reviews where reviewee_id = v_uid;
  update public.reviews set comment = null, reviewer_id = null where reviewer_id = v_uid;
  delete from public.content_reports where kind = 'avatar' and reported_user_id = v_uid;
  update public.content_reports set reporter_id = null where reporter_id = v_uid;
  delete from public.device_tokens where user_id = v_uid;                      -- NEW (0011, US-42): all of this user's tokens
  update public.profiles set deleted_at = now(), display_name = 'ผู้ใช้ที่ลบบัญชีแล้ว', avatar_path = null,
         driver_registered_at = null, licence_declared_at = null, licence_declaration_version = null, active_role = 'rider'
   where id = v_uid;
  update auth.users set banned_until = now() + interval '100 years' where id = v_uid;
  delete from auth.sessions where user_id = v_uid;
end $$;

-- 7. purge_expired_data (0009 body) + push_outbox retention -------------------------------------------------------
create or replace function public.purge_expired_data() returns jsonb
language plpgsql security definer set search_path = public, extensions, auth, pg_temp as $$
declare
  v_loc_days int := public.cfg_num('retention.location_days')::int;
  v_del_days int := public.cfg_num('retention.account_deletion_days')::int;
  v_sos_days int := public.cfg_num('retention.sos_precise_days')::int;
  v_expired int; v_loc int; v_reduced int; v_trips int; v_users int; v_sos int; v_rev int; v_push int;
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

  -- NEW (0011, US-42): drain hygiene - SENT rows are audit trail only for a few days; UNSENT rows this old mean the
  -- Edge Function has been down/unapproved for a week - drop rather than send a week-stale "new message" push.
  delete from public.push_outbox where sent_at is not null
    and sent_at < now() - public.cfg_num('push.outbox_sent_retention_days') * interval '1 day';
  delete from public.push_outbox where sent_at is null
    and created_at < now() - public.cfg_num('push.outbox_stale_retention_days') * interval '1 day';
  get diagnostics v_push = row_count;

  delete from public.trips where deleted_at < now() - v_loc_days * interval '1 day';
  get diagnostics v_trips = row_count;

  delete from public.trip_shares where expires_at < now() - interval '30 days' or revoked_at < now() - interval '30 days';
  delete from public.api_throttle where window_start < now() - interval '1 day';

  delete from auth.users u using public.profiles p
   where p.id = u.id and p.deleted_at < now() - v_del_days * interval '1 day';
  get diagnostics v_users = row_count;

  return jsonb_build_object('expired_trips', v_expired, 'deleted_locations', v_loc, 'reduced_trips', v_reduced,
                            'reduced_sos', v_sos, 'deleted_trips', v_trips, 'deleted_users', v_users,
                            'revealed_reviews', v_rev, 'purged_push_outbox', v_push);
end $$;

-- 8. Grants ---------------------------------------------------------------------------------------------------
revoke execute on function public.register_device_token(text, public.device_platform), public.unregister_device_token(text)
                           from public, anon;
grant execute on function public.register_device_token(text, public.device_platform), public.unregister_device_token(text)
  to authenticated;

notify pgrst, 'reload schema';
