-- GOWITHME 0004: advisor fixes (applied on real Supabase project). Re-runnable.
-- 0002 created new functions AFTER 0001's blanket REVOKE, so they inherited Supabase's default EXECUTE for anon/authenticated.

-- 1. Re-assert least privilege on every function in public.
revoke execute on all functions in schema public from public, anon;
revoke execute on function public._throttle(text, int, int), public.sos_events_guard() from authenticated;
grant execute on function public.get_shared_trip(text) to anon;          -- token-gated public page (only intended anon RPC)

-- 2. Future functions created by the migration role must not be open by default.
alter default privileges in schema public revoke execute on functions from public, anon;

-- 3. Pin search_path on the three plain helper functions.
alter function public.update_updated_at() set search_path = public, pg_temp;
alter function public.safe_uuid(text)     set search_path = public, pg_temp;
alter function public._valid_point(double precision, double precision) set search_path = public, pg_temp;

-- 4. Covering index for the meeting-proposal FK.
create index if not exists matches_meeting_proposed_by_idx on public.matches (meeting_proposed_by) where meeting_proposed_by is not null;

notify pgrst, 'reload schema';
