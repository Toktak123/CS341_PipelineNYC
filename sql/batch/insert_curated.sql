-- PublishIceberg: staging (already verified) -> Iceberg table trips_curated
INSERT INTO {{DB}}.trips_curated
SELECT
  taxi_type, provider_id,
  CAST(pickup_datetime AS timestamp(6)), CAST(dropoff_datetime AS timestamp(6)),
  pickup_hour, trip_duration_min,
  pu_location_id, do_location_id,
  passenger_count, trip_distance, fare_amount, is_imputed,
  run_id, year_month
FROM {{DB}}.staging_curated
WHERE run_id = '{{run_id}}' AND year_month = '{{year_month}}'
