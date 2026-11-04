{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['bank_id', 'period_month', 'role'],
    on_schema_change='append_new_columns'
) }}
-- Grain: one row per PSP bank x month x role (payer / payee). NPCI publishes the top 15 per side.
select
    p.bank_id,
    d.bank_sk,
    p.period_month,
    p.role,
    p.source_rank,
    p.volume_mn,
    p.approved_pct,
    p.bd_pct,
    p.td_pct,
    p.td_pct_prev_month,
    p.td_pct_mom_change,
    p.td_pct_baseline_3m,
    p.td_pct_trailing_3m,
    p.td_pct_prior_3m,
    p.td_pct_trend_3m,
    p.td_pct_volatility_6m,
    p.est_technical_failures,
    p.est_business_failures,
    p.is_degraded,
    {{ reliability_score('p.td_pct_trailing_3m', 'p.td_pct_trend_3m', 'p.td_pct_volatility_6m', 'p.period_month, p.role') }} as reliability_score,
    p.psp_name_published,
    p.source_url,
    p._loaded_at,
    current_timestamp() as _dbt_updated_at
from {{ ref('int_psp_monthly__baselines') }} p
left join {{ ref('dim_bank') }} d
  on d.bank_id = p.bank_id and p.period_month between d.valid_from and d.valid_to
{% if is_incremental() %}
where p.period_month >= (select add_months(max(period_month), -5) from {{ this }})
{% endif %}
