-- Ready-to-use sample dataset: 250 random rows per taxi type from the first month
SELECT taxi_type, provider_id, pickup_datetime, dropoff_datetime, pickup_hour,
       trip_duration_min, pu_location_id, do_location_id,
       passenger_count, trip_distance, fare_amount, is_imputed, run_id, year_month
FROM (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY taxi_type ORDER BY rand()) AS rn
  FROM {{DB}}.trips_curated
  WHERE year_month = (SELECT MIN(year_month) FROM {{DB}}.trips_curated)
)
WHERE rn <= 250
ORDER BY taxi_type, pickup_datetime
