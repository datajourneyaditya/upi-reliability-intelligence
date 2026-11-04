-- Grain: one row per month. NPCI ecosystem totals plus how much of them the top-50 bank tables
-- cover, and the volume-weighted decline rates across those banks.
with eco as (
    select * from {{ ref('stg_npci__ecosystem_monthly') }}
),
rem as (
    select period_month,
           sum(volume_mn) as top50_remitter_volume_mn,
           sum(volume_mn * approved_pct / 100) as top50_remitter_approved_volume_mn,
           sum(volume_mn * td_pct) / nullif(sum(volume_mn), 0) as remitter_td_pct_vw,
           sum(volume_mn * bd_pct) / nullif(sum(volume_mn), 0) as remitter_bd_pct_vw,
           sum(est_technical_failures) as est_technical_failures,
           sum(est_business_failures) as est_business_failures,
           count_if(is_degraded) as degraded_remitter_banks
    from {{ ref('int_bank_monthly__baselines') }} where role = 'remitter' group by period_month
),
ben as (
    select period_month,
           sum(volume_mn) as top50_beneficiary_volume_mn,
           sum(volume_mn * td_pct) / nullif(sum(volume_mn), 0) as beneficiary_td_pct_vw,
           sum(volume_mn * deemed_approved_pct) / nullif(sum(volume_mn), 0) as beneficiary_deemed_approved_pct_vw,
           count_if(is_degraded) as degraded_beneficiary_banks
    from {{ ref('int_bank_monthly__baselines') }} where role = 'beneficiary' group by period_month
)
select
    e.period_month,
    e.banks_live,
    e.volume_mn,
    e.value_cr,
    e.value_cr * 1e7 / nullif(e.volume_mn * 1e6, 0)          as avg_ticket_inr,
    e.volume_mn / nullif(lag(e.volume_mn, 12) over (order by e.period_month), 0) - 1 as volume_yoy_growth,
    r.top50_remitter_volume_mn,
    r.top50_remitter_approved_volume_mn,
    -- bank tables count attempted transactions, ecosystem totals count successful ones, so
    -- coverage compares approved volume
    r.top50_remitter_approved_volume_mn / nullif(e.volume_mn, 0) as top50_remitter_coverage,
    r.remitter_td_pct_vw,
    r.remitter_bd_pct_vw,
    r.est_technical_failures,
    r.est_business_failures,
    r.degraded_remitter_banks,
    b.top50_beneficiary_volume_mn,
    b.beneficiary_td_pct_vw,
    b.beneficiary_deemed_approved_pct_vw,
    b.degraded_beneficiary_banks,
    e.source_url,
    e._loaded_at
from eco e
left join rem r using (period_month)
left join ben b using (period_month)
