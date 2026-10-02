-- =============================================================================
-- DEV SEED (never run in production). Applied by `supabase db reset` after migrations.
-- 5 users (password for all: Passw0rd!), each with 1 scheduled trip in Bangkok (Siam -> Ari corridor).
--   alice@example.test  walk, departs +60 min
--   bob@example.test    walk, +70 min, ~100 m from alice   -> ELIGIBLE with alice (pending request alice -> bob seeded)
--   carol@example.test  car,  +65 min, same corridor       -> NOT eligible (mode mismatch)
--   dave@example.test   walk, +60 min, Bang Na -> Ari      -> NOT eligible (origin too far)
--   eve@chula.ac.th     walk, +80 min, near alice          -> ELIGIBLE, has organization badge (ac.th)
-- alice/bob also have location consent (live location allowed once a trip is started).
-- Idempotent: fixed UUIDs + ON CONFLICT DO NOTHING.
-- Note: auth.users rows are written directly; if your GoTrue version rejects a column, create users via
-- the Auth admin API / Studio instead and keep the trips section.
-- =============================================================================

create extension if not exists pgcrypto with schema extensions;

do $seed$
declare
  r record;
  v_pw text := extensions.crypt('Passw0rd!', extensions.gen_salt('bf'));
begin
  for r in
    select * from (values
      ('10000000-0000-4000-8000-00000000000a'::uuid, 'alice@example.test', 'Alice'),
      ('10000000-0000-4000-8000-00000000000b'::uuid, 'bob@example.test',   'Bob'),
      ('10000000-0000-4000-8000-00000000000c'::uuid, 'carol@example.test', 'Carol'),
      ('10000000-0000-4000-8000-00000000000d'::uuid, 'dave@example.test',  'Dave'),
      ('10000000-0000-4000-8000-00000000000e'::uuid, 'eve@chula.ac.th',    'Eve')
    ) as t(id, email, name)
  loop
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change_token_new, email_change)
    values (
      '00000000-0000-0000-0000-000000000000', r.id, 'authenticated', 'authenticated', r.email, v_pw, now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('display_name', r.name, 'adult_confirmed', true, 'policy_version', '0.1-draft'),
      now(), now(), '', '', '', '')
    on conflict (id) do nothing;      -- on_auth_user_created trigger creates profile + consents + verifications

    insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), r.id, r.id::text, 'email',
            jsonb_build_object('sub', r.id::text, 'email', r.email, 'email_verified', true),
            now(), now(), now())
    on conflict do nothing;
  end loop;
end $seed$;

insert into public.consents (user_id, kind, granted, policy_version)
select u, 'location', true, '1.0'
  from (values ('10000000-0000-4000-8000-00000000000a'::uuid), ('10000000-0000-4000-8000-00000000000b'::uuid)) v(u)
 where not exists (select 1 from public.consents c where c.user_id = v.u and c.kind = 'location');

insert into public.emergency_contacts (user_id, name, phone)
values ('10000000-0000-4000-8000-00000000000a', 'แม่ของ Alice', '+66812345678')
on conflict do nothing;

-- Trips (origin/dest are lng,lat). Straight 2-point routes are enough for overlap tests.
insert into public.trips (id, user_id, mode, origin, origin_label, dest, dest_label, route, route_distance_m, route_duration_s, depart_at)
select v.id, v.uid, v.mode::public.travel_mode,
       ST_SetSRID(ST_MakePoint(v.olng, v.olat), 4326)::geography, v.olabel,
       ST_SetSRID(ST_MakePoint(v.dlng, v.dlat), 4326)::geography, v.dlabel,
       ST_MakeLine(ST_SetSRID(ST_MakePoint(v.olng, v.olat), 4326), ST_SetSRID(ST_MakePoint(v.dlng, v.dlat), 4326))::geography,
       v.dist, v.dur, now() + v.dep
  from (values
    ('20000000-0000-4000-8000-00000000000a'::uuid, '10000000-0000-4000-8000-00000000000a'::uuid, 'walk', 100.5320, 13.7460, 'สยาม',      100.5440, 13.7790, 'อารีย์', 3800, 2900, interval '60 minutes'),
    ('20000000-0000-4000-8000-00000000000b'::uuid, '10000000-0000-4000-8000-00000000000b'::uuid, 'walk', 100.5330, 13.7465, 'สยามสแควร์', 100.5445, 13.7795, 'อารีย์', 3800, 2900, interval '70 minutes'),
    ('20000000-0000-4000-8000-00000000000c'::uuid, '10000000-0000-4000-8000-00000000000c'::uuid, 'car',  100.5325, 13.7462, 'สยาม',      100.5442, 13.7792, 'อารีย์', 3800, 900,  interval '65 minutes'),
    ('20000000-0000-4000-8000-00000000000d'::uuid, '10000000-0000-4000-8000-00000000000d'::uuid, 'walk', 100.6050, 13.6690, 'บางนา',     100.5440, 13.7790, 'อารีย์', 12000, 9000, interval '60 minutes'),
    ('20000000-0000-4000-8000-00000000000e'::uuid, '10000000-0000-4000-8000-00000000000e'::uuid, 'walk', 100.5315, 13.7455, 'สามย่าน',   100.5438, 13.7788, 'อารีย์', 3800, 2900, interval '80 minutes')
  ) as v(id, uid, mode, olng, olat, olabel, dlng, dlat, dlabel, dist, dur, dep)
on conflict (id) do nothing;

-- One pending request alice -> bob so the inbox has data (bucketed values like request_match writes).
insert into public.matches (id, requester_trip_id, target_trip_id, requester_id, target_id, score, overlap_pct, origin_distance_m, dest_distance_m, time_diff_min)
values ('30000000-0000-4000-8000-000000000001',
        '20000000-0000-4000-8000-00000000000a', '20000000-0000-4000-8000-00000000000b',
        '10000000-0000-4000-8000-00000000000a', '10000000-0000-4000-8000-00000000000b', 90, 100, 500, 500, 10.0)
on conflict do nothing;
