-- PublishIceberg: delete this month from curated before rewriting (re-runs never duplicate data)
DELETE FROM {{DB}}.trips_curated
WHERE year_month = '{{year_month}}'
