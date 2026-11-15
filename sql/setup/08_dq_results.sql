-- DATA QUALITY RESULTS: quality results of every run (append-only history), used as evidence and as gate input
CREATE TABLE IF NOT EXISTS {{DB}}.dq_results (
  run_id                  string,
  run_ts                  string,
  year_month              string,
  taxi_type               string,
  total_rows              bigint,
  missing_key             bigint,
  dropoff_before_pickup   bigint,
  pickup_outside_month    bigint,
  duration_over_24h       bigint,
  distance_outlier        bigint,
  fare_outlier            bigint,
  passenger_imputed       bigint,
  distance_imputed        bigint,
  fare_imputed            bigint,
  pu_location_missing     bigint,
  rejected_rows           bigint,
  rejected_pct            double
)
LOCATION 's3://{{BUCKET}}/iceberg/dq_results/'
TBLPROPERTIES (
  'table_type' = 'ICEBERG',
  'format'     = 'parquet'
)
