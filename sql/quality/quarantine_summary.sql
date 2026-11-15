-- Quarantined rows grouped by reject reason
SELECT year_month, taxi_type, reject_reason, COUNT(*) AS row_count
FROM {{DB}}.trips_quarantine
GROUP BY 1, 2, 3
ORDER BY 1, 2, 4 DESC
