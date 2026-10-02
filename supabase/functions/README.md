# Edge Functions

## purge-storage-queue (not deployed)
Drains `storage_purge_queue` (claim_storage_purge -> Storage remove -> complete_storage_purge). Uses the
service_role key that Supabase injects as `SUPABASE_SERVICE_ROLE_KEY`; never put it in the repo.

Deploy (needs owner approval): `supabase functions deploy purge-storage-queue --project-ref citzutjfivstryuquxnf --no-verify-jwt`
then `supabase secrets set PURGE_CRON_SECRET=<random>`.

Schedule (e.g. every 15 min) with pg_cron + pg_net, sending header `x-cron-secret`:
`select cron.schedule('gwm-purge-storage', '*/15 * * * *', $$select net.http_post(url:='https://citzutjfivstryuquxnf.supabase.co/functions/v1/purge-storage-queue', headers:='{"x-cron-secret":"<secret>"}'::jsonb)$$);`
(keep the secret in Supabase Vault rather than inline if possible).
