-- =====================================================================================================================
-- GOWITHME migration 0017 (round 7 traceability fixes - DRAFT, NOT applied anywhere; review before applying)
--   G-6  (US-44 AC5, Medium): vibe tags must also expire 24h after they are set. Until now only mood_text carried a
--        timestamp (mood_set_at), so a trip with tags but no mood never expired. Adds trips.vibe_set_at, stamped by a
--        small BEFORE trigger, and a separate purge function + cron job.
--        (A separate function, not a redefinition of purge_expired_data(): that function is large and its latest
--         definition is spread over several migrations, so copying it here would risk silently reverting later edits.)
--   G-14 (US-45 AC6, Medium): trips.same_org_only was cut from the requirements (BA round 7) but authenticated users
--        could still write it through the API. Revokes the column-level write grants added in 0012. The column and its
--        read paths stay (intentionally kept as a dead column), so nothing that already reads it breaks.
-- Idempotent: safe to re-run.
-- Test impact: supabase/tests/round7d.sql check D3 asserted "no independent expiry"; it is replaced in this change.
-- =====================================================================================================================

-- G-6 --------------------------------------------------------------------------------------------------------------
alter table public.trips add column if not exists vibe_set_at timestamptz;

create or replace function public.trips_vibe_stamp() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if new.vibe_tags is null or cardinality(new.vibe_tags) = 0 then
    new.vibe_set_at := null;
  elsif tg_op = 'INSERT' or old.vibe_tags is distinct from new.vibe_tags or new.vibe_set_at is null then
    new.vibe_set_at := now();
  end if;
  return new;
end $$;
drop trigger if exists trg_trips_vibe_stamp on public.trips;
create trigger trg_trips_vibe_stamp before insert or update of vibe_tags on public.trips
  for each row execute function public.trips_vibe_stamp();
revoke execute on function public.trips_vibe_stamp() from public, anon, authenticated;

-- Backfill: tags that already exist get a stamp now (they were set at an unknown time; this gives them a fresh 24h
-- instead of deleting them silently on first run).
update public.trips set vibe_set_at = now() where vibe_tags is not null and vibe_set_at is null;

-- The trip-end half of the rule (trips_vibe_clear_on_end) already nulls vibe_tags; also clear the stamp so the two
-- columns can never disagree.
create or replace function public.trips_vibe_clear_on_end() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if new.status in ('completed','cancelled','expired') and old.status not in ('completed','cancelled','expired') then
    new.vibe_tags := null; new.mood_text := null; new.mood_set_at := null; new.vibe_set_at := null;
  end if;
  return new;
end $$;
revoke execute on function public.trips_vibe_clear_on_end() from public, anon, authenticated;

create or replace function public.purge_stale_vibe_tags() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_n int;
begin
  update public.trips set vibe_tags = null, vibe_set_at = null
   where vibe_set_at is not null and vibe_set_at < now() - interval '24 hours';
  get diagnostics v_n = row_count;
  return v_n;
end $$;
revoke execute on function public.purge_stale_vibe_tags() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron with schema pg_catalog;
    perform cron.schedule('gwm-purge-stale-vibe-tags', '*/15 * * * *', 'select public.purge_stale_vibe_tags()');
  else
    raise notice 'pg_cron not available: schedule public.purge_stale_vibe_tags() externally';
  end if;
exception when others then
  raise notice 'pg_cron setup skipped: %', sqlerrm;
end $$;

-- G-14 -------------------------------------------------------------------------------------------------------------
-- 0012 granted insert/update on (vibe_tags, mood_text, same_org_only, women_only). Column-level revoke leaves the
-- other three columns untouched.
revoke insert (same_org_only), update (same_org_only) on public.trips from authenticated;
