-- STAGING (rejected): rows of this run that failed the rules, waiting to be published to trips_quarantine
CREATE EXTERNAL TABLE IF NOT EXISTS {{DB}}.staging_rejected (
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
  reject_reason      string
)
PARTITIONED BY (run_id string, year_month string)
STORED AS PARQUET
LOCATION 's3://{{BUCKET}}/staging/rejected/'
TBLPROPERTIES (
  'projection.enabled'                  = 'true',
  'projection.run_id.type'              = 'injected',
  'projection.year_month.type'          = 'date',
  'projection.year_month.format'        = 'yyyy-MM',
  'projection.year_month.range'         = '2019-01,NOW',
  'projection.year_month.interval'      = '1',
  'projection.year_month.interval.unit' = 'MONTHS',
  'storage.location.template'           = 's3://{{BUCKET}}/staging/rejected/run_id=${run_id}/year_month=${year_month}/'
)
