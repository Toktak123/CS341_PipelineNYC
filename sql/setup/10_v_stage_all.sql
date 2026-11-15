-- STAGING VIEW #1: normalize the schema of the 4 sources into one standard
-- yellow/green: VendorID, tpep_/lpep_ datetime   fhv: dispatching_base_num   fhvhv: hvfhs_license_num, trip_miles, base_passenger_fare
-- Columns a source does not have (e.g. fare for fhv) are set to NULL
-- provider_id keeps the original code from the file (no name mapping): VendorID / dispatching_base_num / hvfhs_license_num
CREATE OR REPLACE VIEW {{DB}}.v_stage_all AS
SELECT
  'yellow'                                   AS taxi_type,
  year_month,
  CAST(vendorid AS varchar)                  AS provider_id,
  tpep_pickup_datetime                       AS pickup_datetime,
  tpep_dropoff_datetime                      AS dropoff_datetime,
  CAST(pulocationid AS bigint)               AS pu_location_id,
  CAST(dolocationid AS bigint)               AS do_location_id,
  CAST(passenger_count AS double)            AS passenger_count,
  trip_distance                              AS trip_distance,
  fare_amount                                AS fare_amount
FROM {{DB}}.raw_yellow

UNION ALL
SELECT
  'green', year_month,
  CAST(vendorid AS varchar),
  lpep_pickup_datetime,
  lpep_dropoff_datetime,
  CAST(pulocationid AS bigint),
  CAST(dolocationid AS bigint),
  CAST(passenger_count AS double),
  trip_distance,
  fare_amount
FROM {{DB}}.raw_green

UNION ALL
SELECT
  'fhv', year_month,
  dispatching_base_num,
  pickup_datetime,
  dropoff_datetime,
  pulocationid,
  dolocationid,
  CAST(NULL AS double),
  CAST(NULL AS double),
  CAST(NULL AS double)
FROM {{DB}}.raw_fhv

UNION ALL
SELECT
  'fhvhv', year_month,
  hvfhs_license_num,
  pickup_datetime,
  dropoff_datetime,
  CAST(pulocationid AS bigint),
  CAST(dolocationid AS bigint),
  CAST(NULL AS double),
  trip_miles,
  base_passenger_fare
FROM {{DB}}.raw_fhvhv
