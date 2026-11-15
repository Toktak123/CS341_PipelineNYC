-- Monthly trend + market share within each month
SELECT
  year_month,
  taxi_type,
  COUNT(*)                                                                  AS trips,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY year_month), 2) AS share_pct
FROM {{DB}}.trips_curated
GROUP BY year_month, taxi_type
ORDER BY year_month, trips DESC
