-- Latest data quality result for each month / source
SELECT * FROM (
  SELECT d.*, ROW_NUMBER() OVER (PARTITION BY year_month, taxi_type ORDER BY run_ts DESC) AS rn
  FROM {{DB}}.dq_results d
) WHERE rn = 1
ORDER BY year_month, taxi_type
