-- CURATED ZONE: one table for all taxi types (1 row = 1 trip), ready for analysis
-- Apache Iceberg -> atomic per-partition DELETE + INSERT, so re-running a month never duplicates data
CREATE TABLE IF NOT EXISTS {{DB}}.trips_curated (
  taxi_type          string,
  provider_id        string,
  pickup_datetime    timestamp,
  dropoff_datetime   timestamp,
  pickup_hour        int,
  trip_duration_min  double,
  pu_location_id     bigint,
  do_location_id     bigint,
  passenger_count    double,
  trip_distance      double,
  fare_amount        double,
  is_imputed         boolean,
  run_id             string,
  year_month         string
)
PARTITIONED BY (year_month, taxi_type)
LOCATION 's3://{{BUCKET}}/iceberg/trips_curated/'
TBLPROPERTIES (
  'table_type'        = 'ICEBERG',
  'format'            = 'parquet',
  'write_compression' = 'snappy'
)
