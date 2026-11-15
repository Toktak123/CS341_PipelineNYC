-- FHV: source file uses dropOff_datetime / PUlocationID (mixed case) and location IDs are BIGINT
CREATE EXTERNAL TABLE IF NOT EXISTS {{DB}}.raw_fhv (
  dispatching_base_num   string,
  pickup_datetime        timestamp,
  dropoff_datetime       timestamp,
  pulocationid           bigint,
  dolocationid           bigint
)
PARTITIONED BY (year_month string)
STORED AS PARQUET
LOCATION 's3://{{BUCKET}}/raw/fhv/'
TBLPROPERTIES (
  'projection.enabled'             = 'true',
  'projection.year_month.type'     = 'date',
  'projection.year_month.format'   = 'yyyy-MM',
  'projection.year_month.range'    = '2019-01,NOW',
  'projection.year_month.interval' = '1',
  'projection.year_month.interval.unit' = 'MONTHS',
  'storage.location.template'      = 's3://{{BUCKET}}/raw/fhv/year_month=${year_month}/'
)
