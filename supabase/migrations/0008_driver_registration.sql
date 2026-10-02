-- =====================================================================================================
-- 0008 (DRAFT - NOT APPLIED): Dual role, round 4 (US-19 register/unregister driver, US-20 active role,
-- changed ACs of US-5/16/17). Delta on top of 0001-0007. Design: docs/design-roles.md section 11.
-- Idempotent (re-runnable). Tests: supabase/tests/dual_role.sql.
--
-- What it does
--   1. profiles: driver registration state + active_role, written ONLY by SECURITY DEFINER RPCs (no client write grant,
--      new columns not client-readable either: the licence declaration is owner-only data, read via get_my_role_state()).
--   2. RPCs: register_driver, unregister_driver, set_active_role, get_my_role_state (+ internal _role_state).
--   3. trips_role_guard: role='driver' needs a registered driver (row lock on the profile => race-safe vs unregister).
--   4. vehicles: a registered driver cannot delete the vehicle; share consent needs registration; can_view_vehicle needs it.
--   5. request_account_deletion / export_my_data cover the new fields.
--   6. Legacy dev data (driver trips / vehicles from round 3) does NOT count as registered (see section 7).
-- =====================================================================================================

-- 1. profiles columns -----------------------------------------------------------------------------------
alter table public.profiles add column if not exists driver_registered_at          timestamptz;   -- NULL = not a registered driver
alter table public.profiles add column if not exists licence_declared_at           timestamptz;   -- server time of the self-declaration
alter table public.profiles add column if not exists licence_declaration_version   text;          -- version of the declaration text shown
alter table public.profiles add column if not exists active_role                   public.trip_role not null default 'rider';
-- Derived flag (cannot drift from registered_at). Stored so it is cheap to filter on.
alter table public.profiles add column if not exists driver_registered boolean
  generated always as (driver_registered_at is not null) stored;

do $$ begin
  alter table public.profiles add constraint profiles_driver_state_chk check (
        (driver_registered_at is null) = (licence_declared_at is null)
    and (licence_declared_at  is null) = (licence_declaration_version is null)
    and (licence_declaration_version is null or char_length(licence_declaration_version) between 1 and 32)
    and (active_role = 'rider' or driver_registered_at is not null));      -- active driver mode implies registration
exception when duplicate_object then null; end $$;

-- No licence number / photo columns exist by design (MVP = self-declaration only).
-- Writes: the existing column-level UPDATE grant (display_name, avatar_path, locale) does not include the new columns; assert it.
revoke insert, update on public.profiles from authenticated, anon;
grant  update (display_name, avatar_path, locale) on public.profiles to authenticated;   -- adult_confirmed_at stays revoked (0003)
-- Reads: profiles_select policy lets a matched partner read the whole row. The declaration must stay private, so the table-level
-- SELECT is replaced by a column list that excludes the new columns. (Client already selects explicit columns.)
revoke select on public.profiles from authenticated, anon;
grant  select (id, display_name, avatar_path, locale, adult_confirmed_at, created_at, updated_at, deleted_at)
  on public.profiles to authenticated;

-- 2. Config ---------------------------------------------------------------------------------------------
insert into public.app_config (key, value, description, is_public) values
  ('driver.declaration_version',           '"d1-draft"', 'US-19: current version of the licence self-declaration text; register_driver rejects any other version (legal review = release gate)', true),
  ('throttle.driver_registration_per_hour', '10',        'per-user register_driver / unregister_driver calls per hour', false),
  ('throttle.role_switch_per_min',          '20',        'per-user set_active_role calls per minute', false)
on conflict (key) do nothing;

-- 3. Internal: role state as jsonb ------------------------------------------------------------------------
create or replace function public._role_state(p_uid uuid) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object(
    'driver_registered',           p.driver_registered,
    'driver_registered_at',        p.driver_registered_at,
    'licence_declared_at',         p.licence_declared_at,
    'licence_declaration_version', p.licence_declaration_version,
    'active_role',                 p.active_role,
    'roles',                       case when p.driver_registered then jsonb_build_array('rider', 'driver') else jsonb_build_array('rider') end,
    'has_vehicle',                 exists (select 1 from public.vehicles v where v.user_id = p.id),
    'current_declaration_version', public.cfg('driver.declaration_version') #>> '{}')
  from public.profiles p where p.id = p_uid and p.deleted_at is null
$$;

-- 4. RPCs ----------------------------------------------------------------------------------------------------
create or replace function public.get_my_role_state() returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid(); v jsonb;
begin
  if v_uid is null then raise exception 'GWM_UNAUTHENTICATED' using errcode = '42501'; end if;
  v := public._role_state(v_uid);
  if v is null then raise exception 'GWM_PROFILE_UNAVAILABLE' using errcode = 'P0001'; end if;
  return v;
end $$;

-- US-19: atomic + idempotent. Vehicle upsert + flags in ONE transaction (function body); any error rolls everything back.
-- Re-registering while registered updates the vehicle only: registered_at / licence_declared_at / version are never rewritten.
create or replace function public.register_driver(p_plate text, p_model text, p_colour text, p_declaration_version text)
returns jsonb language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid(); v_plate text; v_model text; v_colour text; v_decl text; v_reg timestamptz; v_changed boolean;
begin
  if v_uid is null then raise exception 'GWM_UNAUTHENTICATED' using errcode = '42501'; end if;
  perform public._throttle('driver_reg', public.cfg_num('throttle.driver_registration_per_hour')::int, 3600);

  select p.driver_registered_at into v_reg from public.profiles p
   where p.id = v_uid and p.deleted_at is null for update;                 -- serialises with trips_role_guard / unregister
  if not found then raise exception 'GWM_PROFILE_UNAVAILABLE' using errcode = 'P0001'; end if;

  v_decl := btrim(coalesce(p_declaration_version, ''));
  if v_decl = '' then raise exception 'GWM_DECLARATION_REQUIRED' using errcode = 'P0001'; end if;
  if v_decl is distinct from (public.cfg('driver.declaration_version') #>> '{}') then
    raise exception 'GWM_DECLARATION_VERSION_STALE' using errcode = 'P0001';
  end if;

  v_plate  := upper(regexp_replace(btrim(coalesce(p_plate,  '')), '\s+', ' ', 'g'));   -- same normalisation as upsert_my_vehicle
  v_model  := regexp_replace(btrim(coalesce(p_model,  '')), '\s+', ' ', 'g');
  v_colour := regexp_replace(btrim(coalesce(p_colour, '')), '\s+', ' ', 'g');
  if char_length(v_plate) not between 1 and 25 or char_length(v_model) not between 1 and 60 or char_length(v_colour) not between 1 and 30
     or (v_plate || v_model || v_colour) ~ '[[:cntrl:]]' then
    raise exception 'GWM_VEHICLE_INVALID' using errcode = 'P0001';
  end if;

  insert into public.vehicles as v (user_id, plate, model, color)
  values (v_uid, v_plate, v_model, v_colour)
  on conflict (user_id) do update
     set plate = excluded.plate, model = excluded.model, color = excluded.color, verified_at = null
   where (v.plate, v.model, v.color) is distinct from (excluded.plate, excluded.model, excluded.color);
  v_changed := found;                                                        -- true only if a row was inserted/changed
  if v_changed and v_reg is not null then                                    -- edit while registered: same neutral message as upsert_my_vehicle
    insert into public.chat_messages (match_id, sender_id, kind, body)
    select m.id, null, 'system', 'system.vehicle_updated'
      from public.matches m join public.trips td on td.id = m.driver_trip_id
     where m.status = 'accepted' and td.user_id = v_uid;
  end if;

  if v_reg is null then
    update public.profiles
       set driver_registered_at = now(), licence_declared_at = now(), licence_declaration_version = v_decl
     where id = v_uid;                                                       -- active_role deliberately NOT changed
  end if;
  return public._role_state(v_uid);
end $$;

-- US-19: unregister. Vehicle row is RETAINED (owner-only); declaration ends (timestamps/version cleared); active_role -> rider;
-- vehicle share consent is switched off (data is no longer used for share/SOS). Idempotent (not registered = no-op success).
create or replace function public.unregister_driver() returns jsonb
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid(); v_reg timestamptz;
begin
  if v_uid is null then raise exception 'GWM_UNAUTHENTICATED' using errcode = '42501'; end if;
  perform public._throttle('driver_reg', public.cfg_num('throttle.driver_registration_per_hour')::int, 3600);

  select p.driver_registered_at into v_reg from public.profiles p
   where p.id = v_uid and p.deleted_at is null for update;                 -- lock BEFORE looking at trips (same order as trips_guard)
  if not found then raise exception 'GWM_PROFILE_UNAVAILABLE' using errcode = 'P0001'; end if;
  if v_reg is null then return public._role_state(v_uid); end if;

  if exists (select 1 from public.trips t
              where t.user_id = v_uid and t.role = 'driver' and t.status in ('scheduled','in_progress') and t.deleted_at is null) then
    raise exception 'GWM_DRIVER_ACTIVE_TRIP' using errcode = 'P0001';
  end if;
  -- accepted match whose Driver trip is still scheduled/in_progress (also catches a soft-deleted-but-active trip the check above skips)
  if exists (select 1 from public.matches m join public.trips td on td.id = m.driver_trip_id
              where m.status = 'accepted' and td.user_id = v_uid and td.status in ('scheduled','in_progress')) then
    raise exception 'GWM_DRIVER_ACTIVE_MATCH' using errcode = 'P0001';
  end if;

  update public.profiles
     set driver_registered_at = null, licence_declared_at = null, licence_declaration_version = null, active_role = 'rider'
   where id = v_uid;
  update public.vehicles set share_consent_at = null where user_id = v_uid;   -- data retained, consent ended
  return public._role_state(v_uid);
end $$;

-- US-20: active role (default rider). Driver only if registered. Idempotent. Never touches existing trips.
create or replace function public.set_active_role(p_role public.trip_role) returns jsonb
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid(); v_reg timestamptz;
begin
  if v_uid is null then raise exception 'GWM_UNAUTHENTICATED' using errcode = '42501'; end if;
  if p_role is null then raise exception 'GWM_INVALID_ROLE' using errcode = 'P0001'; end if;
  perform public._throttle('role_switch', public.cfg_num('throttle.role_switch_per_min')::int, 60);

  select p.driver_registered_at into v_reg from public.profiles p
   where p.id = v_uid and p.deleted_at is null for update;
  if not found then raise exception 'GWM_PROFILE_UNAVAILABLE' using errcode = 'P0001'; end if;
  if p_role = 'driver' and v_reg is null then raise exception 'GWM_NOT_A_DRIVER' using errcode = 'P0001'; end if;

  update public.profiles set active_role = p_role where id = v_uid and active_role is distinct from p_role;
  return public._role_state(v_uid);
end $$;

-- 5. trips_role_guard: 0006 body + "driver role requires a registered driver" ----------------------------------------
-- Ordering: trg_trips_guard (0002) already holds FOR UPDATE on the profile row on INSERT; the FOR SHARE below re-asserts the
-- lock so this guard stays race-safe against unregister_driver even if trips_guard changes. unregister_driver locks the same row
-- FOR UPDATE first and only then looks at trips, so a concurrent create either commits before (unregister sees the trip and
-- refuses) or after (guard sees registered=false and refuses).
create or replace function public.trips_role_guard() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_reg timestamptz;
begin
  if tg_op = 'INSERT' then
    if new.mode = 'car' then
      if new.role is null then raise exception 'GWM_ROLE_REQUIRED' using errcode = 'P0001'; end if;
      if new.role = 'driver' then
        select p.driver_registered_at into v_reg from public.profiles p
         where p.id = new.user_id and p.deleted_at is null for share;
        if v_reg is null then raise exception 'GWM_NOT_A_DRIVER' using errcode = 'P0001'; end if;
        if not exists (select 1 from public.vehicles v where v.user_id = new.user_id) then
          raise exception 'GWM_VEHICLE_REQUIRED' using errcode = 'P0001';
        end if;
      end if;
    elsif new.role is not null then
      raise exception 'GWM_ROLE_NOT_ALLOWED' using errcode = 'P0001';
    end if;
    return new;
  end if;
  -- UPDATE by a client: role never changes; mode cannot move into or out of car (role is bound to the car mode)
  if auth.uid() is not null then
    if new.role is distinct from old.role
       or (new.mode is distinct from old.mode and (old.mode = 'car' or new.mode = 'car')) then
      raise exception 'GWM_ROLE_IMMUTABLE' using errcode = 'P0001';
    end if;
    -- Q-1: a Driver cannot cancel the trip once the Rider of the accepted match boarded (finish with "arrived" instead)
    if new.status = 'cancelled' and old.status is distinct from 'cancelled' and old.role = 'driver'
       and exists (select 1 from public.matches m
                    where m.driver_trip_id = new.id and m.status = 'accepted' and m.boarded_at is not null) then
      raise exception 'GWM_ALREADY_BOARDED' using errcode = 'P0001';
    end if;
  end if;
  return new;
end $$;
-- trigger trg_trips_role_guard already exists (0006) and keeps pointing at this function.

-- 6. vehicles -------------------------------------------------------------------------------------------------------
-- 6a. delete guard: 0006 rule + registered drivers cannot delete (unregister first). Account deletion clears registration in the
-- same UPDATE that sets deleted_at (section 7), so trg_profiles_delete_vehicle passes.
create or replace function public.vehicles_delete_guard() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is not null then
    if exists (select 1 from public.trips t
                where t.user_id = old.user_id and t.role = 'driver' and t.status in ('scheduled','in_progress') and t.deleted_at is null) then
      raise exception 'GWM_VEHICLE_IN_USE' using errcode = 'P0001';
    end if;
    if exists (select 1 from public.profiles p where p.id = old.user_id and p.driver_registered_at is not null) then
      raise exception 'GWM_DRIVER_REGISTERED' using errcode = 'P0001';
    end if;
  end if;
  return old;
end $$;

-- 6b. share consent only while registered (0006 body + check). Switching OFF is always allowed.
create or replace function public.set_vehicle_share_consent(p_on boolean) returns timestamptz
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid(); v_at timestamptz;
begin
  if v_uid is null then raise exception 'GWM_UNAUTHENTICATED' using errcode = '42501'; end if;
  if p_on is null then raise exception 'GWM_VEHICLE_INVALID' using errcode = 'P0001'; end if;
  perform public._throttle('vehicle', public.cfg_num('throttle.vehicle_write_per_hour')::int, 3600);
  if p_on and not exists (select 1 from public.profiles p where p.id = v_uid and p.driver_registered_at is not null) then
    raise exception 'GWM_NOT_A_DRIVER' using errcode = 'P0001';
  end if;
  update public.vehicles set share_consent_at = case when p_on then now() end
   where user_id = v_uid returning share_consent_at into v_at;
  if not found then raise exception 'GWM_VEHICLE_REQUIRED' using errcode = 'P0001'; end if;
  return v_at;
end $$;

-- 6c. can_view_vehicle: 0006 body + owner must be a registered driver unless the Rider boarded (Q-2 kept)
create or replace function public.can_view_vehicle(p_owner uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1
    from public.matches m
    join public.trips td on td.id = case when m.requester_id = p_owner then m.requester_trip_id else m.target_trip_id end
    join public.trips tr on tr.id = case when m.requester_id = p_owner then m.target_trip_id else m.requester_trip_id end
    where (m.status = 'accepted' or (m.status = 'cancelled' and m.boarded_at is not null))
      and ((m.requester_id = p_owner and m.target_id = auth.uid()) or (m.target_id = p_owner and m.requester_id = auth.uid()))
      and td.user_id = p_owner and td.role = 'driver'
      and tr.user_id = auth.uid() and tr.role = 'rider'
      and (td.status in ('scheduled','in_progress') or td.ended_at > now() - interval '24 hours' or m.boarded_at is not null)
      and (tr.status in ('scheduled','in_progress') or tr.ended_at > now() - interval '24 hours')
      -- NEW (0008): a retained vehicle of an unregistered owner is owner-only, EXCEPT for a Rider who already boarded (Q-2)
      and (m.boarded_at is not null
           or exists (select 1 from public.profiles op where op.id = p_owner and op.driver_registered_at is not null))
      and not exists (select 1 from public.blocks b
                       where (b.blocker_id = p_owner and b.blocked_id = auth.uid())
                          or (b.blocker_id = auth.uid() and b.blocked_id = p_owner)))
$$;

-- 7. Account deletion (0003 body) + registration/declaration/active_role cleared in the SAME update as deleted_at -------------
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
  update public.profiles set deleted_at = now(), display_name = 'ผู้ใช้ที่ลบบัญชีแล้ว', avatar_path = null,
         driver_registered_at = null, licence_declared_at = null, licence_declaration_version = null, active_role = 'rider'
   where id = v_uid;                                                       -- after-trigger (0006) then deletes the vehicle row

  update auth.users set banned_until = now() + interval '100 years' where id = v_uid;
  delete from auth.sessions where user_id = v_uid;
end $$;

-- 8. Export (0006 body): registration state + declaration time/version in an explicit section ---------------------------------
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
    'vehicle', (select to_jsonb(v) from public.vehicles v where v.user_id = auth.uid()))
$$;

-- 9. Legacy dev data (round 3): nobody is registered at this point, so driver trips/vehicles created under 0006 do not count.
--  * live driver trips of NON-registered users are cancelled (system update: auth.uid() is null => trigger cascades close their
--    accepted matches with outcome cancelled_by_driver) so they stop appearing in matching;
--  * their vehicle rows stay (owner-only) but share consent is switched off.
-- Re-running after real registrations exist only touches users that are still unregistered.
update public.trips t set status = 'cancelled'
 where t.role = 'driver' and t.status in ('scheduled','in_progress')
   and not exists (select 1 from public.profiles p where p.id = t.user_id and p.driver_registered_at is not null);
update public.vehicles v set share_consent_at = null
 where v.share_consent_at is not null
   and not exists (select 1 from public.profiles p where p.id = v.user_id and p.driver_registered_at is not null);

-- 10. Grants ---------------------------------------------------------------------------------------------------------------
revoke execute on function public.register_driver(text, text, text, text), public.unregister_driver(),
                           public.set_active_role(public.trip_role), public.get_my_role_state(), public._role_state(uuid)
  from public, anon, authenticated;
grant execute on function public.register_driver(text, text, text, text), public.unregister_driver(),
                          public.set_active_role(public.trip_role), public.get_my_role_state() to authenticated;
-- _role_state is internal (definer callers only). Re-assert ACL of redefined functions (create or replace keeps ACLs, belt and braces).
revoke execute on function public.trips_role_guard(), public.vehicles_delete_guard() from public, anon, authenticated;
revoke execute on function public.set_vehicle_share_consent(boolean), public.can_view_vehicle(uuid),
                           public.export_my_data(), public.request_account_deletion() from public, anon;
grant execute on function public.set_vehicle_share_consent(boolean), public.can_view_vehicle(uuid),
                          public.export_my_data(), public.request_account_deletion() to authenticated;

-- 13. Plate limit 15 -> 25 characters (so the hint "1กก 1234 กรุงเทพมหานคร" fits). Client VehicleLimits.plateMax = 25.
--     0006 is already applied, so the CHECK is relaxed here (idempotent drop/re-add) and upsert_my_vehicle is re-declared (grants kept).
alter table public.vehicles drop constraint if exists vehicles_plate_check;
alter table public.vehicles add constraint vehicles_plate_check
  check (char_length(plate) between 1 and 25 and plate !~ '[[:cntrl:]]');

create or replace function public.upsert_my_vehicle(p_plate text, p_model text, p_color text)
returns uuid language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid(); v_plate text; v_model text; v_color text; v_id uuid;
begin
  if v_uid is null then raise exception 'GWM_UNAUTHENTICATED' using errcode = '42501'; end if;
  perform public._throttle('vehicle', public.cfg_num('throttle.vehicle_write_per_hour')::int, 3600);
  if not exists (select 1 from public.profiles p where p.id = v_uid and p.deleted_at is null) then
    raise exception 'GWM_PROFILE_UNAVAILABLE' using errcode = 'P0001';
  end if;
  v_plate := upper(regexp_replace(btrim(coalesce(p_plate, '')), '\s+', ' ', 'g'));
  v_model := regexp_replace(btrim(coalesce(p_model, '')), '\s+', ' ', 'g');
  v_color := regexp_replace(btrim(coalesce(p_color, '')), '\s+', ' ', 'g');
  if char_length(v_plate) not between 1 and 25 or char_length(v_model) not between 1 and 60 or char_length(v_color) not between 1 and 30
     or (v_plate || v_model || v_color) ~ '[[:cntrl:]]' then
    raise exception 'GWM_VEHICLE_INVALID' using errcode = 'P0001';
  end if;
  insert into public.vehicles as v (user_id, plate, model, color)
  values (v_uid, v_plate, v_model, v_color)
  on conflict (user_id) do update
     set plate = excluded.plate, model = excluded.model, color = excluded.color, verified_at = null   -- edited => self-declared again
  returning v.id into v_id;
  -- neutral system message to a matched Rider: "vehicle info changed"
  insert into public.chat_messages (match_id, sender_id, kind, body)
  select m.id, null, 'system', 'system.vehicle_updated'
    from public.matches m join public.trips td on td.id = m.driver_trip_id
   where m.status = 'accepted' and td.user_id = v_uid;
  return v_id;
end $$;

notify pgrst, 'reload schema';
