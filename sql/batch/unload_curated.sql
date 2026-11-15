-- Transform_batch: rows that passed + MEDIAN imputation (per source) -> staging
-- (Used the median for distance/fare for outliers)
UNLOAD (
  SELECT
    b.taxi_type,
    b.provider_id,
    b.pickup_datetime,
    b.dropoff_datetime,
    CAST(hour(b.pickup_datetime) AS integer)                                    AS pickup_hour,
    b.trip_duration_min,
    b.pu_location_id,
    b.do_location_id,
    CASE WHEN b.imp_passenger THEN s.med_passenger ELSE b.passenger_count END   AS passenger_count,
    CASE WHEN b.imp_distance  THEN s.med_distance  ELSE b.trip_distance  END    AS trip_distance,
    CASE WHEN b.imp_fare      THEN s.med_fare      ELSE b.fare_amount    END    AS fare_amount,
    (b.imp_passenger OR b.imp_distance OR b.imp_fare)                           AS is_imputed
  FROM (
    SELECT c.*,
      (c.taxi_type IN ('yellow', 'green') AND (c.passenger_count IS NULL OR c.passenger_count <= 0)) AS imp_passenger,
      (c.taxi_type <> 'fhv' AND (c.trip_distance IS NULL OR c.trip_distance < 0))                   AS imp_distance,
      (c.taxi_type <> 'fhv' AND (c.fare_amount IS NULL OR c.fare_amount < 0))                       AS imp_fare
    FROM {{DB}}.v_stage_checked c
    WHERE c.year_month = '{{year_month}}' AND c.reject_reason IS NULL
  ) b
  JOIN (
    SELECT
      taxi_type,
      approx_percentile(CASE WHEN passenger_count > 0  THEN passenger_count END, 0.5) AS med_passenger,
      approx_percentile(CASE WHEN trip_distance  >= 0 THEN trip_distance  END, 0.5) AS med_distance,
      approx_percentile(CASE WHEN fare_amount    >= 0 THEN fare_amount    END, 0.5) AS med_fare
    FROM {{DB}}.v_stage_checked
    WHERE year_month = '{{year_month}}' AND reject_reason IS NULL
    GROUP BY taxi_type
  ) s ON b.taxi_type = s.taxi_type
)
TO 's3://{{BUCKET}}/staging/curated/run_id={{run_id}}/year_month={{year_month}}/'
WITH (format = 'PARQUET', compression = 'SNAPPY')
