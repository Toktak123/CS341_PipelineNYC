-- Main question: which vehicle type is used the most (most used = number of trips, 1 row = 1 trip)
SELECT
  taxi_type,
  COUNT(*)                                                    AS total_trips,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)          AS share_pct,
  RANK() OVER (ORDER BY COUNT(*) DESC)                        AS usage_rank,
  MIN(year_month)                                             AS first_month,
  MAX(year_month)                                             AS last_month
FROM {{DB}}.trips_curated
GROUP BY taxi_type
ORDER BY usage_rank
