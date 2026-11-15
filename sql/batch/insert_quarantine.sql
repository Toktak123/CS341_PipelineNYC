-- PublishIceberg: staging rejected -> Iceberg table trips_quarantine
INSERT INTO {{DB}}.trips_quarantine
SELECT
  taxi_type, provider_id,
  CAST(pickup_datetime AS timestamp(6)), CAST(dropoff_datetime AS timestamp(6)),
  trip_duration_min, pu_location_id, do_location_id,
  passenger_count, trip_distance, fare_amount,
  reject_reason, run_id, year_month
FROM {{DB}}.staging_rejected
WHERE run_id = '{{run_id}}' AND year_month = '{{year_month}}'
