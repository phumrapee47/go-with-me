// Scheduled Edge Function: drains public.storage_purge_queue (US-22 avatar cleanup).
// NOT DEPLOYED. Secrets come from function env (SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY are injected by
// Supabase; PURGE_CRON_SECRET is set by you). Never commit keys.
import { createClient } from "npm:@supabase/supabase-js@2";

Deno.serve(async (req) => {
  const secret = Deno.env.get("PURGE_CRON_SECRET");
  if (!secret || req.headers.get("x-cron-secret") !== secret) {
    return new Response("forbidden", { status: 403 });
  }
  const sb = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  const { data: rows, error } = await sb.rpc("claim_storage_purge", { p_limit: 100 });
  if (error) return new Response(error.message, { status: 500 });
  if (!rows?.length) return Response.json({ claimed: 0, removed: 0 });

  const byBucket = new Map<string, { ids: string[]; paths: string[] }>();
  for (const r of rows as { id: string; bucket: string; path: string }[]) {
    const g = byBucket.get(r.bucket) ?? { ids: [], paths: [] };
    g.ids.push(r.id);
    g.paths.push(r.path);
    byBucket.set(r.bucket, g);
  }

  const done: string[] = [];
  for (const [bucket, g] of byBucket) {
    const { error: rmErr } = await sb.storage.from(bucket).remove(g.paths); // missing objects are not an error
    if (rmErr) { console.error("remove failed", bucket, rmErr.message); continue; } // stays claimed; retried after 15 min
    done.push(...g.ids);
  }
  if (done.length) {
    const { error: cErr } = await sb.rpc("complete_storage_purge", { p_ids: done });
    if (cErr) return new Response(cErr.message, { status: 500 });
  }
  return Response.json({ claimed: rows.length, removed: done.length });
});
