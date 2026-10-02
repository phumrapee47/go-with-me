-- 0015_advisor_fixes: drop duplicate index introduced by 0014.
-- trip_locations_trip_time_idx (trip_id, recorded_at desc) already existed pre-0014 and covers the exact same
-- (trip_id, recorded_at desc) shape that 0014's trip_locations_trip_recorded_idx duplicated. get_advisors flagged
-- this as a NEW "duplicate_index" WARN immediately after 0014 applied. Drop the redundant one added by 0014;
-- _match_overdue's query is still served by the pre-existing trip_locations_trip_time_idx.
drop index if exists public.trip_locations_trip_recorded_idx;
