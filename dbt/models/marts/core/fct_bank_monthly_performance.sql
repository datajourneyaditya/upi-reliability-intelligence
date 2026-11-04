{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['bank_id', 'period_month', 'role'],
    partition_by=['role'],
    on_schema_change='append_new_columns'
) }}
-- Grain: one row per bank x month x role (remitter = payer side, beneficiary = payee side).
-- Incremental: each run re-merges the latest 6 months so NPCI restatements and the rolling
-- baselines that depend on them stay correct.
select
    b.bank_id,
    d.bank_sk,
    b.period_month,
    b.role,
    b.source_rank,
    b.volume_mn,
    b.approved_pct,
    b.bd_pct,
    b.td_pct,
    b.deemed_approved_pct,
    b.debit_reversal_count_mn,
    b.debit_reversal_success_pct,
    b.udir_auto_update_sr_pct,
    b.udir_refund_sr_pct,
    b.td_pct_prev_month,
    b.td_pct_mom_change,
    b.volume_mom_growth,
    b.td_pct_baseline_3m,
    b.td_pct_trailing_3m,
    b.td_pct_prior_3m,
    b.td_pct_trend_3m,
    b.td_pct_volatility_6m,
    b.est_technical_failures,
    b.est_business_failures,
    b.is_degraded,
    {{ reliability_score('b.td_pct_trailing_3m', 'b.td_pct_trend_3m', 'b.td_pct_volatility_6m', 'b.period_month, b.role') }} as reliability_score,
    b.bank_name_published,
    b.source_url,
    b._loaded_at,
    current_timestamp() as _dbt_updated_at
from {{ ref('int_bank_monthly__baselines') }} b
left join {{ ref('dim_bank') }} d
  on d.bank_id = b.bank_id and b.period_month between d.valid_from and d.valid_to
{% if is_incremental() %}
where b.period_month >= (select add_months(max(period_month), -5) from {{ this }})
{% endif %}
