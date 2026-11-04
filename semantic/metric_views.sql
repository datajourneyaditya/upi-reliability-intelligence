-- Semantic layer: Unity Catalog metric views. One governed definition of each metric, queryable
-- from AI/BI dashboards, Genie and SQL with MEASURE(`Technical Decline Rate`).

CREATE OR REPLACE VIEW upi_reliability.metrics.bank_reliability
WITH METRICS LANGUAGE YAML
COMMENT 'Bank reliability metrics on NPCI remitter and beneficiary data (bank x month x role)'
AS $$
version: 0.1
source: upi_reliability.marts.fct_bank_monthly_performance
joins:
  - name: dim_bank
    source: upi_reliability.marts.dim_bank
    on: source.bank_sk = dim_bank.bank_sk
dimensions:
  - name: Month
    expr: period_month
  - name: Role
    expr: role  # remitter = payer side, beneficiary = payee side
  - name: Bank
    expr: dim_bank.bank_name
  - name: Bank Type
    expr: dim_bank.bank_type
  - name: Is Degraded
    expr: is_degraded
measures:
  - name: Volume (Mn)
    expr: SUM(volume_mn)
  - name: Technical Decline Rate
    expr: SUM(volume_mn * td_pct) / SUM(volume_mn)  # Volume-weighted TD %, bank / network side failures
  - name: Business Decline Rate
    expr: SUM(volume_mn * bd_pct) / SUM(volume_mn)  # Volume-weighted BD %, customer side failures (wrong PIN, low balance, limits)
  - name: Approval Rate
    expr: SUM(volume_mn * approved_pct) / SUM(volume_mn)
  - name: Deemed Approved Rate
    expr: SUM(CASE WHEN deemed_approved_pct IS NOT NULL THEN volume_mn * deemed_approved_pct END) / SUM(CASE WHEN deemed_approved_pct IS NOT NULL THEN volume_mn END)
  - name: Estimated Failed Transactions
    expr: SUM(est_technical_failures)  # volume x TD %
  - name: Debit Reversal Success Rate
    expr: SUM(debit_reversal_count_mn * debit_reversal_success_pct) / SUM(CASE WHEN debit_reversal_success_pct IS NOT NULL THEN debit_reversal_count_mn END)
  - name: Average Reliability Score
    expr: AVG(reliability_score)
  - name: Degraded Banks
    expr: COUNT(DISTINCT CASE WHEN is_degraded THEN bank_id END)
$$;

CREATE OR REPLACE VIEW upi_reliability.metrics.psp_reliability
WITH METRICS LANGUAGE YAML
COMMENT 'PSP-bank reliability metrics on NPCI payer / payee PSP data'
AS $$
version: 0.1
source: upi_reliability.marts.fct_psp_monthly_performance
joins:
  - name: dim_bank
    source: upi_reliability.marts.dim_bank
    on: source.bank_sk = dim_bank.bank_sk
dimensions:
  - name: Month
    expr: period_month
  - name: Role
    expr: role
  - name: PSP Bank
    expr: dim_bank.bank_name
measures:
  - name: Volume (Mn)
    expr: SUM(volume_mn)
  - name: Technical Decline Rate
    expr: SUM(volume_mn * td_pct) / SUM(volume_mn)
  - name: Business Decline Rate
    expr: SUM(volume_mn * bd_pct) / SUM(volume_mn)
  - name: Estimated Failed Transactions
    expr: SUM(est_technical_failures)
  - name: Degraded PSPs
    expr: COUNT(DISTINCT CASE WHEN is_degraded THEN bank_id END)
$$;

CREATE OR REPLACE VIEW upi_reliability.metrics.ecosystem
WITH METRICS LANGUAGE YAML
COMMENT 'UPI ecosystem totals from NPCI product statistics'
AS $$
version: 0.1
source: upi_reliability.marts.fct_ecosystem_monthly
dimensions:
  - name: Month
    expr: period_month
measures:
  - name: UPI Volume (Mn)
    expr: SUM(volume_mn)
  - name: UPI Value (Cr)
    expr: SUM(value_cr)
  - name: Banks Live
    expr: MAX(banks_live)
  - name: Top 50 Remitter Coverage
    expr: SUM(top50_remitter_approved_volume_mn) / SUM(volume_mn)  # Share of successful UPI volume sent by the top-50 remitter banks
$$;
