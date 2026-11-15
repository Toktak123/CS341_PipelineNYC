CREATE EXTERNAL TABLE IF NOT EXISTS {{DB}}.raw_fhvhv (
  hvfhs_license_num      string,
  pickup_datetime        timestamp,
  dropoff_datetime       timestamp,
  pulocationid           int,
  dolocationid           int,
  trip_miles             double,
  base_passenger_fare    double
)
PARTITIONED BY (year_month string)
STORED AS PARQUET
LOCATION 's3://{{BUCKET}}/raw/fhvhv/'
TBLPROPERTIES (
  'projection.enabled'             = 'true',
  'projection.year_month.type'     = 'date',
  'projection.year_month.format'   = 'yyyy-MM',
  'projection.year_month.range'    = '2019-01,NOW',
  'projection.year_month.interval' = '1',
  'projection.year_month.interval.unit' = 'MONTHS',
  'storage.location.template'      = 's3://{{BUCKET}}/raw/fhvhv/year_month=${year_month}/'
)
