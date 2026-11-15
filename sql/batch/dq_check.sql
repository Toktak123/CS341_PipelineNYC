-- STEP 1: data quality checks for month {{year_month}} across all sources -> append to dq_results
INSERT INTO {{DB}}.dq_results
SELECT
  '{{run_id}}'                                        AS run_id,
  CAST(current_timestamp AS varchar)                  AS run_ts,
  year_month,
  taxi_type,
  COUNT(*)                                            AS total_rows,
  COUNT_IF(reject_reason = 'missing_key')             AS missing_key,
  COUNT_IF(reject_reason = 'dropoff_before_pickup')   AS dropoff_before_pickup,
  COUNT_IF(reject_reason = 'pickup_outside_month')    AS pickup_outside_month,
  COUNT_IF(reject_reason = 'duration_over_24h')       AS duration_over_24h,
  COUNT_IF(reject_reason = 'distance_outlier')        AS distance_outlier,
  COUNT_IF(reject_reason = 'fare_outlier')            AS fare_outlier,
  -- null/invalid values that will be replaced with the median (rows are kept, not rejected)
  COUNT_IF(taxi_type IN ('yellow', 'green')
           AND (passenger_count IS NULL OR passenger_count <= 0))  AS passenger_imputed,
  COUNT_IF(taxi_type <> 'fhv'
           AND (trip_distance IS NULL OR trip_distance < 0))       AS distance_imputed,
  COUNT_IF(taxi_type <> 'fhv'
           AND (fare_amount IS NULL OR fare_amount < 0))           AS fare_imputed,
  COUNT_IF(pu_location_id IS NULL)                    AS pu_location_missing,
  COUNT_IF(reject_reason IS NOT NULL)                 AS rejected_rows,
  ROUND(100.0 * COUNT_IF(reject_reason IS NOT NULL) / COUNT(*), 4) AS rejected_pct
FROM {{DB}}.v_stage_checked
WHERE year_month = '{{year_month}}'
GROUP BY year_month, taxi_type
