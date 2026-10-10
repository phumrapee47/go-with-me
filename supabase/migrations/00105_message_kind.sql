-- FILE NAME: formerly 0011a_message_kind.sql. The Supabase CLI only accepts <digits>_<name>.sql and sorts by file name, so
--   '0011a_' was skipped and 'driver_arrived' did not exist when 0011 ran (CI: invalid input value for enum message_kind).
--   '00105_' matches the pattern and sorts before 0010_/0011_. The SQL is unchanged (idempotent ADD VALUE IF NOT EXISTS).
-- =====================================================================================================
-- 0011a (DRAFT - NOT APPLIED): Round 7 Stage A prerequisite for 0011_push_pindrop.sql. Orchestrator decision
-- 14.8-1: ADD VALUE on an existing enum cannot safely be used later in the SAME transaction/migration on some
-- poolers (PG12+ allows ADD VALUE IF NOT EXISTS, but a value added earlier in the same transaction may still be
-- unusable to that same transaction) - split out defensively rather than waiting to find out it breaks under
-- apply_migration. This file MUST run and commit before 0011_push_pindrop.sql.
-- Idempotent (IF NOT EXISTS). Tests: supabase/tests/round7.sql.
-- =====================================================================================================

-- message_kind gains a THIRD value distinct from 'user' so US-42 push payloads can stay opaque (kind-only, no
-- body text inspection) for "driver arrived at pickup" (US-33, round 6) - sender_id stays present, unlike 'system'.
alter type public.message_kind add value if not exists 'driver_arrived';
