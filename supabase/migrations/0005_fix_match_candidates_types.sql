-- 0005: extract(epoch) is numeric on PG14+, so time_diff_min did not match the declared double precision column.
-- Redefines match_candidates (0003 body) with an explicit cast; find_matches raised 42804 before this.
create or replace function public.match_candidates(p_trip_id uuid, p_limit int default 20, p_only_trip uuid default null)
returns table (candidate_trip_id uuid, candidate_user_id uuid, origin_distance_m double precision,
               dest_distance_m double precision, time_diff_min double precision,
               overlap_pct double precision, score double precision)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
#variable_conflict use_column
declare
  v_t      public.trips%rowtype;
  v_r_o    double precision := public.cfg_num('match.origin_radius_m');
  v_r_d    double precision := public.cfg_num('match.dest_radius_m');
  v_win    double precision := public.cfg_num('match.time_window_min');
  v_min_ov double precision := public.cfg_num('match.min_overlap_pct');
  v_max    int              := public.cfg_num('match.max_matches_per_trip')::int;
  v_buf    double precision := public.cfg_num('match.route_buffer_m');
  v_w      jsonb            := public.cfg('match.weights');
  v_compat jsonb            := public.cfg('match.mode_compat');
  v_wd double precision := (v_w ->> 'distance')::double precision;
  v_wt double precision := (v_w ->> 'time')::double precision;
  v_wo double precision := (v_w ->> 'overlap')::double precision;
  v_cutoff timestamptz      := now() - public.cfg_num('trip.expire_after_min') * interval '1 minute';
begin
  select * into v_t from public.trips where id = p_trip_id and deleted_at is null;
  if not found or v_t.status <> 'scheduled' or v_t.depart_at <= v_cutoff then return; end if;
  if (select count(*) from public.matches m where m.status = 'accepted'
        and v_t.id in (m.requester_trip_id, m.target_trip_id)) >= v_max then return; end if;

  return query
  with cand as (
    select o.id as tid, o.user_id as uid, o.route as route,
           ST_Distance(o.origin, v_t.origin) as d_o,
           ST_Distance(o.dest,   v_t.dest)   as d_d,
           (abs(extract(epoch from (o.depart_at - v_t.depart_at))) / 60.0)::double precision as dt
      from public.trips o
      join public.profiles p on p.id = o.user_id and p.deleted_at is null
     where o.status = 'scheduled' and o.deleted_at is null
       and o.depart_at > v_cutoff                                   -- T5.14: expired but not yet swept by cron
       and o.user_id <> v_t.user_id
       and (p_only_trip is null or o.id = p_only_trip)
       and ST_DWithin(o.origin, v_t.origin, v_r_o)
       and ST_DWithin(o.dest,   v_t.dest,   v_r_d)
       and o.depart_at between v_t.depart_at - v_win * interval '1 minute'
                           and v_t.depart_at + v_win * interval '1 minute'
       and (v_compat -> v_t.mode::text) @> to_jsonb(o.mode::text)
       and not exists (select 1 from public.blocks b
                        where (b.blocker_id = v_t.user_id and b.blocked_id = o.user_id)
                           or (b.blocker_id = o.user_id  and b.blocked_id = v_t.user_id))
       and not exists (select 1 from public.matches m              -- only a still-pending pair stays visible
                        where m.status <> 'pending'
                          and ((m.requester_trip_id = v_t.id and m.target_trip_id = o.id)
                            or (m.requester_trip_id = o.id  and m.target_trip_id = v_t.id)))
       and (select count(*) from public.matches m where m.status = 'accepted'
              and o.id in (m.requester_trip_id, m.target_trip_id)) < v_max
  ), scored as (
    select c.tid, c.uid, c.d_o, c.d_d, c.dt,
           public.route_overlap_pct(v_t.route, c.route, v_buf) as ov
      from cand c
  )
  select s.tid, s.uid, s.d_o, s.d_d, s.dt, s.ov,
         100.0 * ( v_wd * (1 - least(1.0, (s.d_o / v_r_o + s.d_d / v_r_d) / 2.0))
                 + v_wt * (1 - s.dt / nullif(v_win, 0))
                 + v_wo * (s.ov / 100.0) ) / nullif(v_wd + v_wt + v_wo, 0)
    from scored s
   where s.ov >= v_min_ov
   order by 7 desc, s.tid asc
   limit p_limit;
end $$;

-- grants: create or replace keeps existing privileges; re-assert the intended surface (idempotent)
revoke execute on function public.match_candidates(uuid, int, uuid) from public, anon, authenticated;
