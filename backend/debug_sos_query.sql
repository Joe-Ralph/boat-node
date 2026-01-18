-- DEBUG SOS BROADCAST QUERY
-- Run this in your Supabase SQL Editor to see if any boats match your criteria.

WITH vars AS (
  SELECT 
    -- REPLACE THESE VALUES WITH YOUR TEST DATA
    '7e5e816b-157f-4baa-a0bc-ef3fcab5f57d'::uuid as sender_uid,  -- Put your AUTH ID here
    12.94 as p_lat,                                              -- Put your TEST LATITUDE here
    80.24 as p_long,                                             -- Put your TEST LONGITUDE here
    
    -- Simulation of app_settings defaults
    COALESCE((SELECT replace(value, '"', '')::int FROM app_settings WHERE key = 'sos_broadcast_count'), 5) as broadcast_count,
    COALESCE((SELECT replace(value, '"', '')::int FROM app_settings WHERE key = 'sos_search_radius_meters'), 5000) as search_radius
)
SELECT 
    v.sender_uid as sender_id,
    b.owner_id as receiver_id,
    b.id as boat_id,
    v.p_lat as input_lat,
    v.p_long as input_long,
    bll.lat as target_lat,
    bll.lon as target_long,
    -- Distance calculation for verification
    (
      6371000 * acos(
        least(1.0, greatest(-1.0,
          cos(radians(v.p_lat)) * cos(radians(bll.lat)) *
          cos(radians(bll.lon) - radians(v.p_long)) +
          sin(radians(v.p_lat)) * sin(radians(bll.lat))
        ))
      )
    ) as distance_meters
FROM boat_live_locations bll
JOIN boats b ON b.id = bll.boat_id
CROSS JOIN vars v
WHERE 
    b.owner_id != v.sender_uid  -- Filter out self
    AND (
      6371000 * acos(
        least(1.0, greatest(-1.0,
          cos(radians(v.p_lat)) * cos(radians(bll.lat)) *
          cos(radians(bll.lon) - radians(v.p_long)) +
          sin(radians(v.p_lat)) * sin(radians(bll.lat))
        ))
      )
    ) <= v.search_radius
ORDER BY distance_meters ASC
LIMIT v.broadcast_count;
