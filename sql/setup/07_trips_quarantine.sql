-- QUARANTINE: rows that failed quality rules, kept with a reason (reject_reason) instead of being deleted
-- Makes it traceable why rows are missing from curated
CREATE TABLE IF NOT EXISTS {{DB}}.trips_quarantine (
  taxi_type          string,
  provider_id        string,
  pickup_datetime    timestamp,
  dropoff_datetime   timestamp,
  trip_duration_min  double,
  pu_location_id     bigint,
  do_location_id     bigint,
  passenger_count    double,
  trip_distance      double,
  fare_amount        double,
  reject_reason      string,
  run_id             string,
  year_month         string
)
PARTITIONED BY (year_month, taxi_type)
LOCATION 's3://{{BUCKET}}/iceberg/trips_quarantine/'
TBLPROPERTIES (
  'table_type'        = 'ICEBERG',
  'format'            = 'parquet',
  'write_compression' = 'snappy'
)
