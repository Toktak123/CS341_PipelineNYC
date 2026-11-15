-- Transform_batch: rows that failed the rules, with reasons -> staging
UNLOAD (
  SELECT
    taxi_type, provider_id,
    pickup_datetime, dropoff_datetime, trip_duration_min,
    pu_location_id, do_location_id,
    passenger_count, trip_distance, fare_amount,
    reject_reason
  FROM {{DB}}.v_stage_checked
  WHERE year_month = '{{year_month}}' AND reject_reason IS NOT NULL
)
TO 's3://{{BUCKET}}/staging/rejected/run_id={{run_id}}/year_month={{year_month}}/'
WITH (format = 'PARQUET', compression = 'SNAPPY')
