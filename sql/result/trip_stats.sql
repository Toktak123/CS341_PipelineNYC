-- Per-type metrics: distance, fare, trip duration (fhv has no distance/fare -> NULL)
SELECT
  taxi_type,
  COUNT(*)                                             AS trips,
  ROUND(AVG(trip_distance), 2)                         AS avg_distance_mi,
  ROUND(approx_percentile(trip_distance, 0.5), 2)      AS median_distance_mi,
  ROUND(AVG(fare_amount), 2)                           AS avg_fare_usd,
  ROUND(approx_percentile(fare_amount, 0.5), 2)        AS median_fare_usd,
  ROUND(AVG(trip_duration_min), 1)                     AS avg_duration_min,
  ROUND(approx_percentile(trip_duration_min, 0.5), 1)  AS median_duration_min,
  ROUND(100.0 * COUNT_IF(is_imputed) / COUNT(*), 2)    AS imputed_pct
FROM {{DB}}.trips_curated
GROUP BY taxi_type
ORDER BY trips DESC
