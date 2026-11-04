-- Audience: merchants choosing which bank account to link for UPI collections.
-- Grain: one row per beneficiary (payee) bank x month. Uses the payee side only, because that is
-- the bank a merchant's settlement account sits in.
-- Limitation: these are bank-wide rates, used as a risk indicator; they do not measure any
-- individual merchant's own checkout.
with f as (
    select f.*, d.bank_name, d.bank_type
    from {{ ref('fct_bank_monthly_performance') }} f
    left join {{ ref('dim_bank') }} d on d.bank_sk = f.bank_sk
    where f.role = 'beneficiary'
),
peers as (
    select *,
        percentile_approx(td_pct, 0.5) over (partition by period_month)                 as peer_median_td_pct,
        percentile_approx(deemed_approved_pct, 0.9) over (partition by period_month)    as peer_p90_deemed_approved_pct,
        count(*) over (partition by bank_id order by period_month
                       range between interval 11 months preceding and current row)       as months_in_top50_last_12,
        sum(case when is_degraded then 1 else 0 end) over (partition by bank_id order by period_month
                       range between interval 5 months preceding and current row)        as degraded_months_last_6
    from f
)
select
    period_month,
    bank_id,
    bank_name,
    bank_type,
    source_rank                                                         as npci_volume_rank,
    volume_mn                                                           as credits_received_mn,
    approved_pct,
    td_pct,
    bd_pct,
    deemed_approved_pct,
    td_pct_trailing_3m,
    td_pct_trend_3m,
    td_pct_volatility_6m,
    reliability_score,
    rank() over (partition by period_month order by reliability_score desc, td_pct_trailing_3m) as reliability_rank,
    est_technical_failures                                              as est_failed_credits,
    -- risk flags (absolute floors stop a near-zero peer median from inflating risk)
    is_degraded                                                         as flag_degraded_this_month,
    td_pct > 2 * peer_median_td_pct and td_pct >= 0.25                  as flag_td_above_2x_peer_median,
    deemed_approved_pct > peer_p90_deemed_approved_pct and deemed_approved_pct >= 0.1 as flag_high_pending_credits,
    td_pct_trend_3m > 0.10                                              as flag_rising_td_trend,
    months_in_top50_last_12 < 6                                         as flag_thin_history,
    degraded_months_last_6,
    peer_median_td_pct,
    case
        when is_degraded or degraded_months_last_6 >= 2 or td_pct_trailing_3m >= 1.0 then 'High'
        when reliability_score < 40 or td_pct_trend_3m > 0.10
             or (deemed_approved_pct > peer_p90_deemed_approved_pct and deemed_approved_pct >= 0.1)
             or (td_pct > 2 * peer_median_td_pct and td_pct >= 0.25) then 'Medium'
        else 'Low'
    end                                                                 as collection_risk_tier,
    case
        when is_degraded or degraded_months_last_6 >= 2 or td_pct_trailing_3m >= 1.0
            then 'Avoid as primary; keep a backup bank'
        when reliability_score >= 70 and months_in_top50_last_12 >= 6 and degraded_months_last_6 = 0
             and td_pct_trend_3m <= 0.10 then 'Preferred for collections'
        when reliability_score < 40 or td_pct_trend_3m > 0.10 then 'Acceptable with a backup bank'
        else 'Acceptable'
    end                                                                 as recommendation
from peers
