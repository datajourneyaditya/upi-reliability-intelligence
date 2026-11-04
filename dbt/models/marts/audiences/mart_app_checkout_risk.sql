-- Audience: consumer-app PMs. Grain: one row per UPI app x month.
-- NPCI publishes app volume but not app decline rates, so failure exposure is *indicative*: the
-- app's volume times the volume-weighted payer-side TD of its sponsor PSP banks (from public VPA
-- handles, seeds/psp_apps.csv). Apps without known sponsors get no estimate.
with apps as (
    select f.*, d.parent_company, d.app_category, d.sponsor_bank_ids
    from {{ ref('fct_app_monthly_volume') }} f
    left join {{ ref('dim_psp_app') }} d on d.app_sk = f.app_sk
),
sponsor as (
    select a.period_month, a.app_sk,
           sum(p.volume_mn * p.td_pct) / nullif(sum(p.volume_mn), 0) as sponsor_payer_td_pct,
           sum(p.volume_mn * p.bd_pct) / nullif(sum(p.volume_mn), 0) as sponsor_payer_bd_pct,
           max(case when p.is_degraded then 1 else 0 end) = 1        as any_sponsor_degraded,
           count(p.bank_id)                                         as sponsors_with_data,
           concat_ws(', ', collect_list(p.bank_id))                 as sponsors_reported
    from (select period_month, app_sk, explode(sponsor_bank_ids) as sponsor_bank_id from apps) a
    join {{ ref('fct_psp_monthly_performance') }} p
      on p.bank_id = a.sponsor_bank_id and p.period_month = a.period_month and p.role = 'payer'
    group by a.period_month, a.app_sk
),
market as (
    select period_month, sum(volume_mn * td_pct) / sum(volume_mn) as market_payer_td_pct
    from {{ ref('fct_bank_monthly_performance') }} where role = 'remitter' group by period_month
)
select
    a.period_month,
    a.app_sk,
    a.app_name,
    a.parent_company,
    a.app_category,
    a.is_third_party_app,
    a.source_rank                                         as npci_volume_rank,
    a.total_volume_mn,
    a.total_value_cr,
    a.volume_share,
    a.avg_ticket_inr,
    s.sponsors_reported,
    s.sponsor_payer_td_pct,
    s.sponsor_payer_bd_pct,
    s.any_sponsor_degraded,
    m.market_payer_td_pct,
    a.total_volume_mn * 1e6 * s.sponsor_payer_td_pct / 100 as indicative_technical_failures,
    case when s.sponsor_payer_td_pct is null then 'No sponsor data'
         when s.any_sponsor_degraded then 'Sponsor PSP degraded'
         when s.sponsor_payer_td_pct > m.market_payer_td_pct then 'Above market TD'
         else 'At or below market TD' end                 as psp_risk_status
from apps a
left join sponsor s on s.period_month = a.period_month and s.app_sk = a.app_sk
left join market m on m.period_month = a.period_month
