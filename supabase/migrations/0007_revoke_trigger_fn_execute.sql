-- 0007: advisor fix after applying 0006. Trigger functions added by 0006 kept the default PUBLIC EXECUTE, so they showed up as
-- callable RPCs (anon/authenticated SECURITY DEFINER lint 0028/0029). Triggers do not need EXECUTE for the invoking role.
revoke execute on function public.matches_set_car_roles(), public.profiles_delete_vehicle(), public.sos_vehicle_snapshot(),
                           public.trips_after_status_roles(), public.trips_role_guard(), public.vehicles_delete_guard()
  from public, anon, authenticated;
