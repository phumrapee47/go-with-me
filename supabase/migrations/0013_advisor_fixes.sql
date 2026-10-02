-- 0013: fix auth_rls_initplan perf WARN introduced by 0011's device_tokens_select policy
-- (auth.uid() re-evaluated per row instead of once via subselect). No behavior change.
drop policy if exists device_tokens_select on public.device_tokens;
create policy device_tokens_select on public.device_tokens for select to authenticated
  using (user_id = (select auth.uid()));
