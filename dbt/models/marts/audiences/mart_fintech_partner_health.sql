-- Audience: fintech product / partnerships teams monitoring partner banks.
-- Grain: one row per partner entity x month x side, across all three NPCI views of a bank:
--   remitter bank, beneficiary bank, and payer / payee PSP bank.
with banks as (
    select bank_id, bank_sk, period_month,
           case role when 'remitter' then 'Remitter bank' else 'Beneficiary bank' end as partner_side,
           volume_mn, approved_pct, bd_pct, td_pct, td_pct_mom_change, td_pct_baseline_3m,
           td_pct_trend_3m, td_pct_volatility_6m, est_technical_failures, is_degraded, reliability_score,
           debit_reversal_success_pct
    from {{ ref('fct_bank_monthly_performance') }}
),
psps as (
    select bank_id, bank_sk, period_month,
           case role when 'payer' then 'Payer PSP' else 'Payee PSP' end,
           volume_mn, approved_pct, bd_pct, td_pct, td_pct_mom_change, td_pct_baseline_3m,
           td_pct_trend_3m, td_pct_volatility_6m, est_technical_failures, is_degraded, reliability_score,
           cast(null as double)
    from {{ ref('fct_psp_monthly_performance') }}
),
u as (select * from banks union all select * from psps),
streaks as (
    select *,
        -- consecutive degraded months ending this month
        sum(case when is_degraded then 0 else 1 end) over (partition by bank_id, partner_side order by period_month) as reset_grp
    from u
)
select
    s.period_month,
    s.bank_id,
    d.bank_name,
    d.bank_type,
    s.partner_side,
    s.volume_mn,
    s.approved_pct,
    s.bd_pct,
    s.td_pct,
    s.td_pct_mom_change,
    s.td_pct_baseline_3m,
    s.td_pct_trend_3m,
    s.td_pct_volatility_6m,
    s.reliability_score,
    s.debit_reversal_success_pct,
    s.est_technical_failures,
    -- failures above what the bank's own 3-month baseline would have produced
    greatest(s.volume_mn * 1e6 * (s.td_pct - s.td_pct_baseline_3m) / 100, 0) as est_excess_failures_vs_baseline,
    s.is_degraded                                                         as degradation_alert,
    sum(case when s.is_degraded then 1 else 0 end)
        over (partition by s.bank_id, s.partner_side, s.reset_grp order by s.period_month) as consecutive_degraded_months,
    case
        when s.is_degraded and s.td_pct >= 1 then 'Critical'
        when s.is_degraded then 'Degraded'
        when s.td_pct_trend_3m > 0.05 then 'Watch'
        else 'Healthy'
    end                                                                   as health_status
from streaks s
left join {{ ref('dim_bank') }} d on d.bank_sk = s.bank_sk
