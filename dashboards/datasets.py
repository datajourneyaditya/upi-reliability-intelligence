"""SQL for each dashboard dataset. Latest month = latest month with bank-level data."""
C = "upi_reliability"
LATEST = f"(SELECT max(period_month) FROM {C}.marts.fct_bank_monthly_performance)"

DATASETS = {
"ds_kpi": ("Latest month KPIs", f"""
SELECT date_format(e.period_month, 'MMM yyyy') AS month_label,
       round(e.volume_mn / 1000, 2) AS upi_volume_bn,
       round(e.remitter_td_pct_vw, 3) AS top50_td_pct,
       round(e.remitter_bd_pct_vw, 2) AS top50_bd_pct,
       round(e.est_technical_failures / 1e6, 1) AS est_tech_failures_mn,
       (SELECT count(*) FROM {C}.marts.mart_fintech_partner_health h
         WHERE h.period_month = e.period_month AND h.degradation_alert) AS degraded_partner_sides,
       round(e.top50_remitter_coverage * 100, 1) AS top50_coverage_pct
FROM {C}.marts.fct_ecosystem_monthly e
WHERE e.period_month = {LATEST}
"""),
"ds_eco_rates": ("Ecosystem decline rates by month", f"""
SELECT period_month, round(remitter_td_pct_vw, 3) AS td_pct, round(remitter_bd_pct_vw, 2) AS bd_pct
FROM {C}.marts.fct_ecosystem_monthly WHERE remitter_td_pct_vw IS NOT NULL
"""),
"ds_eco_volume": ("Ecosystem volume and failures", f"""
SELECT period_month, round(volume_mn / 1000, 2) AS upi_volume_bn,
       round(est_technical_failures / 1e6, 1) AS est_tech_failures_mn,
       degraded_remitter_banks, degraded_beneficiary_banks
FROM {C}.marts.fct_ecosystem_monthly WHERE period_month >= '2022-01-01'
"""),
"ds_td_by_type": ("TD by bank type (metric view)", f"""
SELECT Month AS period_month, `Bank Type` AS bank_type,
       round(MEASURE(`Technical Decline Rate`), 3) AS td_pct
FROM {C}.metrics.bank_reliability
WHERE Role = 'remitter' AND `Bank Type` IN ('Public sector', 'Private sector', 'Small finance bank', 'Payments bank', 'Regional rural bank')
GROUP BY ALL
"""),
"ds_scorecard": ("Merchant scorecard (latest month)", f"""
SELECT reliability_rank, bank_name, bank_type, round(credits_received_mn, 1) AS credits_received_mn,
       td_pct, round(td_pct_trailing_3m, 3) AS td_pct_3m, deemed_approved_pct, reliability_score,
       collection_risk_tier, recommendation,
       CASE collection_risk_tier WHEN 'Low' THEN 1 WHEN 'Medium' THEN 2 ELSE 3 END AS tier_order
FROM {C}.marts.mart_merchant_bank_scorecard
WHERE period_month = {LATEST}
ORDER BY reliability_rank
"""),
"ds_tier_mix": ("Risk tier mix by month", f"""
SELECT period_month, collection_risk_tier, count(*) AS banks
FROM {C}.marts.mart_merchant_bank_scorecard
WHERE period_month >= '2022-07-01'
GROUP BY ALL
"""),
"ds_alerts": ("Partner alerts (latest month)", f"""
SELECT bank_name, partner_side, health_status, td_pct, round(td_pct_baseline_3m, 3) AS td_baseline_3m,
       round(td_pct_trend_3m, 3) AS td_trend_3m, consecutive_degraded_months,
       round(est_excess_failures_vs_baseline / 1e6, 2) AS excess_failures_mn,
       round(volume_mn, 1) AS volume_mn
FROM {C}.marts.mart_fintech_partner_health
WHERE period_month = {LATEST} AND health_status <> 'Healthy'
ORDER BY CASE health_status WHEN 'Critical' THEN 1 WHEN 'Degraded' THEN 2 ELSE 3 END, est_excess_failures_vs_baseline DESC
"""),
"ds_partner_trend": ("Partner TD vs baseline", f"""
SELECT period_month, bank_name, partner_side, 'TD %' AS series, td_pct AS rate_pct
FROM {C}.marts.mart_fintech_partner_health
UNION ALL
SELECT period_month, bank_name, partner_side, '3-month baseline %', round(td_pct_baseline_3m, 3)
FROM {C}.marts.mart_fintech_partner_health WHERE td_pct_baseline_3m IS NOT NULL
"""),
"ds_degraded_trend": ("Degraded partners by side", f"""
SELECT period_month, partner_side, count_if(degradation_alert) AS degraded
FROM {C}.marts.mart_fintech_partner_health WHERE period_month >= '2022-04-01'
GROUP BY ALL
"""),
"ds_pareto": ("Payer bank failure contribution (latest)", f"""
SELECT failure_contribution_rank, bank_name, bank_type,
       round(payer_volume_share * 100, 1) AS volume_share_pct,
       round(technical_failure_share * 100, 1) AS failure_share_pct,
       round(cumulative_failure_share * 100, 1) AS cumulative_failure_pct,
       td_pct, round(td_vs_market, 2) AS td_vs_market,
       round(est_technical_failures / 1e6, 2) AS est_tech_failures_mn,
       checkout_action
FROM {C}.marts.mart_payer_bank_checkout_risk
WHERE period_month = {LATEST}
ORDER BY failure_contribution_rank
"""),
"ds_pareto_top": ("Top 15 payer banks by failure share", f"""
SELECT failure_contribution_rank, bank_name, round(technical_failure_share * 100, 1) AS failure_share_pct,
       round(payer_volume_share * 100, 1) AS volume_share_pct
FROM {C}.marts.mart_payer_bank_checkout_risk
WHERE period_month = {LATEST} AND failure_contribution_rank <= 15
"""),
"ds_apps": ("App checkout exposure (latest)", f"""
SELECT npci_volume_rank, app_name, coalesce(parent_company, '') AS parent_company,
       round(total_volume_mn, 1) AS volume_mn, round(volume_share * 100, 2) AS volume_share_pct,
       coalesce((SELECT concat_ws(', ', array_sort(collect_list(d.bank_name))) FROM {C}.marts.dim_bank d
                 WHERE d.is_current AND array_contains(split(a.sponsors_reported, ', '), d.bank_id)), '') AS sponsors_reported,
       round(sponsor_payer_td_pct, 3) AS sponsor_td_pct,
       round(market_payer_td_pct, 3) AS market_td_pct,
       round(indicative_technical_failures / 1e6, 2) AS indicative_failures_mn,
       psp_risk_status
FROM {C}.marts.mart_app_checkout_risk a
WHERE period_month = {LATEST} AND volume_share >= 0.001
ORDER BY npci_volume_rank
"""),
}
