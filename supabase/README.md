# GOWITHME backend (Supabase / Postgres + PostGIS)

```
supabase/
  migrations/0001_init.sql                     schema, RLS, RPCs, cron
  migrations/0002_safety_privacy_hardening.sql P0 hardening (T3.17-T3.22)
  migrations/0003_qa_round1.sql                QA round 1: signup validation, deletion ban, expiry filter (T5.11/12/14)
  seed.sql                                     dev-only sample users/trips (run by `supabase db reset`)
  tests/rls_checklist.sql                      design-security s.8 checks + 0002 checks (rolled back)
  tests/qa_round1.sql                          0003 checks + matching formula, blur, organisation domain (rolled back)
```

## Prerequisites
- Docker Desktop running
- Supabase CLI (`npm i -g supabase`, or prefix commands with `npx`)

## Start a local stack
```bash
cd <project root>            # the folder that contains supabase/
supabase init                # only once, if supabase/config.toml does not exist (keeps existing migrations/seed)
supabase start               # prints API URL, anon key, DB URL (default postgresql://postgres:postgres@127.0.0.1:54322/postgres)
```

## Apply migrations
```bash
supabase db reset            # drops local DB, applies migrations/*.sql in order, then runs seed.sql  (recommended)
# or, keep data and apply only new migrations:
supabase migration up
```
Migrations are written to be re-runnable, but 0001-0003 have never been executed on a real Postgres before T3.23:
expect to fix small syntax/permission issues on the first run and note them in `docs/dev-notes.md`.

## Seed data (dev only)
`seed.sql` creates 5 confirmed users (password `Passw0rd!`) each with one scheduled trip in Bangkok:

| user | trip | eligible with alice? |
|---|---|---|
| alice@example.test | walk, Siam -> Ari, +60 min | - |
| bob@example.test | walk, ~100 m from alice, +70 min | yes (a pending request alice -> bob is pre-seeded) |
| carol@example.test | car, same corridor | no (mode) |
| dave@example.test | walk, Bang Na -> Ari | no (origin too far) |
| eve@chula.ac.th | walk, near alice, +80 min | yes, has organization badge |

Trip times are relative to seed time (`now() + ...`); re-run `supabase db reset` when they expire (trips expire 120 min after departure).
Never run `seed.sql` against production.

## Run the RLS / privacy checklist
```bash
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f supabase/tests/rls_checklist.sql
```
- One transaction, rolled back at the end; uses its own users (Chiang Mai / Phuket) so it is safe next to the seed data.
- Prints a PASS/FAIL table and exits non-zero on any FAIL. `WARN` rows are production gates (see below).
- Without `psql`: `docker exec -i supabase_db_<project> psql -U postgres -v ON_ERROR_STOP=1 < supabase/tests/rls_checklist.sql`.

## Run the QA round 1 tests (T5.15)
```bash
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f supabase/tests/qa_round1.sql
```
Same conventions as the checklist (one transaction, rolled back, PASS/FAIL table, non-zero exit on FAIL). Covers: signup rejected without
18+/current policy, server-set timestamps, client grants; account deletion ban + session revoke; `match_candidates` formula,
filters, determinism and expiry edge cases; `blur_point`; organisation domain (suffix, subdomain, look-alike, case, inactive).

CI (`.github/workflows/ci.yml`): job `flutter` runs `flutter analyze` + `flutter test`; job `sql-tests` runs `supabase start`
(applies migrations + seed) then both SQL files. The SQL has not been executed on a real Postgres yet (no Postgres/Supabase CLI in the
dev environment): the first CI run is the first real run, expect small fixes.

## 0003 notes (QA round 1)
- `policy.current_version` (app_config, public) must equal `AppConstants.policyVersion` in the app ('0.1-draft'). Bump both together.
- `handle_new_user` RAISES for every insert into `auth.users` lacking `adult_confirmed=true` + current `policy_version` (GoTrue answers
  "Database error saving new user"; the app maps it to a Thai message). Dashboard/admin-created users need that metadata too (`seed.sql` updated).
- Clients lost `UPDATE (adult_confirmed_at)` on profiles and `INSERT` on consents (use the `record_consent` RPC).
- `request_account_deletion` sets `auth.users.banned_until` (+100 years) and deletes `auth.sessions` (cascades refresh tokens) in the same
  transaction; any failure rolls the deletion back. If a Supabase version forbids writing `auth.*` from SQL, replace those two statements with an
  Edge Function calling `auth.admin.updateUserById(id, {ban_duration})` and a global sign-out (verify on a real project). Already issued access
  tokens live until expiry (default 1 h).
- `match_candidates` drops trips older than `trip.expire_after_min` itself; an already expired requester trip gets no candidates.
- DB rate guard for live location stays 5 s; the client pushes every 15 s (`AppConstants.livePushInterval`, range 15-30 s).

## Config that lives outside SQL
| Item | Where | Value |
|---|---|---|
| PostgREST max rows (design-api s.13 #7) | `supabase/config.toml` `[api] max_rows`, hosted: Dashboard > API settings | 1000 (0002 also tries `pgrst.db_max_rows`; env/config wins) |
| statement_timeout | set by 0002 on roles `authenticated` (8s) / `anon` (3s) | verify with `select rolname, rolconfig from pg_roles where rolname in ('authenticated','anon')` |
| Email confirmation (F-9 / P-4) | `config.toml` `[auth.email] enable_confirmations = true` (local dev may keep `false`); hosted: Auth > Providers > Email | ON in production |
| Cron | 0001 schedules `purge_expired_data()` every 15 min if `pg_cron` exists | otherwise schedule externally with the service_role key |

## Production release gates (T5.10)
```sql
update public.app_config set value = 'false' where key = 'phone.mock_enabled';   -- F-16
select key, value from public.app_config where key in ('phone.mock_enabled','auth.require_verified_email','client.min_version');
```
Also: email confirmations ON, service_role key absent from the app binary, Realtime publication = `chat_messages`, `matches` only.

## Error codes added in 0002 (`message` of a 400; map in the client ErrorMapper)
`GWM_ADULT_REQUIRED`, `GWM_CONSENT_REQUIRED`, `GWM_TRIP_HAS_MATCHES`, `GWM_PENDING_LIMIT`, `GWM_EMAIL_NOT_VERIFIED`,
`GWM_RATE_LIMITED` (now also from find_matches/request_match/meeting RPCs), `GWM_INVALID_POINT`, `GWM_NO_PROPOSAL`,
`GWM_OWN_PROPOSAL`, `GWM_MATCH_CLOSED`.

## Client contract notes (0002)
- `sos_events` and `trips`: send your own `id`. SOS: `POST /sos_events?on_conflict=id` with `Prefer: resolution=ignore-duplicates`.
  Trips: a retry with the same id is a silent no-op (201, empty body with `return=representation`) - re-read the trip.
- `request_match` returns the same id when retried. Meeting point: `propose_meeting_point` / `confirm_meeting_point`
  (the old `set_meeting_point` is no longer executable by clients); `matches.meeting_proposed_*` shows a pending proposal.
- `chat_state(match_id)` -> `open | blocked | trip_ended | match_closed | not_found`.
- Block = chat read-only for both sides, match stays `accepted` until the blocker cancels, live location stops.
