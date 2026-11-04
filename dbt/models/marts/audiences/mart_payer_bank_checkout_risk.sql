-- Audience: consumer-app PMs (e.g. a food-delivery checkout) deciding payment-option ordering and
-- nudges. Grain: one row per payer (remitter) bank x month.
-- Shows which payer banks generate the most technical failures, so the app can, for example, nudge
-- users of a degraded bank toward another linked account or card.
with r as (
    select f.*, d.bank_name, d.bank_type
    from {{ ref('fct_bank_monthly_performance') }} f
    left join {{ ref('dim_bank') }} d on d.bank_sk = f.bank_sk
    where f.role = 'remitter'
),
shares as (
    select *,
        volume_mn / sum(volume_mn) over (partition by period_month)                         as payer_volume_share,
        est_technical_failures / sum(est_technical_failures) over (partition by period_month) as technical_failure_share,
        td_pct / nullif(sum(volume_mn * td_pct) over (partition by period_month)
                        / sum(volume_mn) over (partition by period_month), 0)               as td_vs_market
    from r
)
select
    period_month,
    bank_id,
    bank_name,
    bank_type,
    source_rank                                                  as npci_volume_rank,
    volume_mn                                                    as payments_sent_mn,
    payer_volume_share,
    td_pct,
    bd_pct,
    approved_pct,
    td_vs_market,
    est_technical_failures,
    est_business_failures,
    technical_failure_share,
    -- Pareto view: cumulative share of failures from the worst banks down
    sum(technical_failure_share) over (partition by period_month order by est_technical_failures desc
                                       rows between unbounded preceding and current row) as cumulative_failure_share,
    rank() over (partition by period_month order by est_technical_failures desc) as failure_contribution_rank,
    debit_reversal_success_pct,
    udir_refund_sr_pct,
    is_degraded,
    reliability_score,
    case
        when is_degraded or td_vs_market >= 2 then 'Nudge to alternate instrument'
        when td_vs_market >= 1.25 then 'Show with retry guidance'
        else 'No action'
    end                                                          as checkout_action
from shares
