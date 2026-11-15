CREATE EXTERNAL TABLE IF NOT EXISTS {{DB}}.raw_green (
  vendorid               int,
  lpep_pickup_datetime   timestamp,
  lpep_dropoff_datetime  timestamp,
  passenger_count        bigint,
  trip_distance          double,
  pulocationid           int,
  dolocationid           int,
  fare_amount            double
)
PARTITIONED BY (year_month string)
STORED AS PARQUET
LOCATION 's3://{{BUCKET}}/raw/green/'
TBLPROPERTIES (
  'projection.enabled'             = 'true',
  'projection.year_month.type'     = 'date',
  'projection.year_month.format'   = 'yyyy-MM',
  'projection.year_month.range'    = '2019-01,NOW',
  'projection.year_month.interval' = '1',
  'projection.year_month.interval.unit' = 'MONTHS',
  'storage.location.template'      = 's3://{{BUCKET}}/raw/green/year_month=${year_month}/'
)
