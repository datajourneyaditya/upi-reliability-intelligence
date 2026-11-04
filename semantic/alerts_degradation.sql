-- Alert query: partner banks / PSPs that are degraded in the latest NPCI month.
-- Used by a Databricks SQL alert (trigger when row count > 0) and the job's alert task.
SELECT period_month, bank_name, partner_side, td_pct, td_pct_baseline_3m,
       consecutive_degraded_months, est_excess_failures_vs_baseline, health_status
FROM upi_reliability.marts.mart_fintech_partner_health
WHERE period_month = (SELECT max(period_month) FROM upi_reliability.marts.mart_fintech_partner_health)
  AND degradation_alert
ORDER BY est_excess_failures_vs_baseline DESC;
