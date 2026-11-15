-- STAGING VIEW #2: apply quality (validation) rules -> reject_reason
-- reject_reason IS NULL  = passed -> goes to curated
-- reject_reason NOT NULL = failed -> goes to quarantine
-- CASE order = priority order (each row gets exactly one reason)
CREATE OR REPLACE VIEW {{DB}}.v_stage_checked AS
SELECT
  s.*,
  date_diff('second', s.pickup_datetime, s.dropoff_datetime) / 60.0 AS trip_duration_min,
  CASE
    WHEN s.provider_id IS NULL OR s.pickup_datetime IS NULL OR s.dropoff_datetime IS NULL
      THEN 'missing_key'                       -- no provider/time, trip cannot be identified
    WHEN s.dropoff_datetime < s.pickup_datetime
      THEN 'dropoff_before_pickup'             -- timestamps out of order
    WHEN date_format(s.pickup_datetime, '%Y-%m') <> s.year_month
      THEN 'pickup_outside_month'              -- time outside the file's month (e.g. stray 2002/2009 rows)
    WHEN date_diff('hour', s.pickup_datetime, s.dropoff_datetime) > 24
      THEN 'duration_over_24h'                 -- a single trip longer than 24 hours
    WHEN s.trip_distance > 500
      THEN 'distance_outlier'                  -- distance > 500 miles
    WHEN s.fare_amount > 1000
      THEN 'fare_outlier'                      -- fare > $1,000
    ELSE NULL
  END AS reject_reason
FROM {{DB}}.v_stage_all s
