-- STAGING (curated): Transform_batch output not yet published (written with UNLOAD)
-- Partitioned by run_id + year_month -> runs never overwrite each other / Verify_batch checks counts before publish
-- run_id uses injected projection (run_id must always be given in WHERE)
CREATE EXTERNAL TABLE IF NOT EXISTS {{DB}}.staging_curated (
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
  is_imputed         boolean
)
PARTITIONED BY (run_id string, year_month string)
STORED AS PARQUET
LOCATION 's3://{{BUCKET}}/staging/curated/'
TBLPROPERTIES (
  'projection.enabled'                  = 'true',
  'projection.run_id.type'              = 'injected',
  'projection.year_month.type'          = 'date',
  'projection.year_month.format'        = 'yyyy-MM',
  'projection.year_month.range'         = '2019-01,NOW',
  'projection.year_month.interval'      = '1',
  'projection.year_month.interval.unit' = 'MONTHS',
  'storage.location.template'           = 's3://{{BUCKET}}/staging/curated/run_id=${run_id}/year_month=${year_month}/'
)
