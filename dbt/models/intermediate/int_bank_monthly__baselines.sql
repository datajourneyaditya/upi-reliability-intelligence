-- Month-over-month deltas, trailing 3-month baseline (excluding the current month), 6-month
-- volatility and the degradation flag, per bank x role.
-- If two published spellings map to one bank in the same month (rare), they are combined
-- volume-weighted first so the grain stays bank x month x role.
with combined as (
    select
        bank_id, period_month, role,
        min(source_rank)                                                         as source_rank,
        sum(volume_mn)                                                           as volume_mn,
        round(sum(volume_mn * approved_pct) / nullif(sum(case when approved_pct is not null then volume_mn end), 0), 4) as approved_pct,
        round(sum(volume_mn * bd_pct) / nullif(sum(case when bd_pct is not null then volume_mn end), 0), 4)             as bd_pct,
        round(sum(volume_mn * td_pct) / nullif(sum(case when td_pct is not null then volume_mn end), 0), 4)             as td_pct,
        round(sum(volume_mn * deemed_approved_pct) / nullif(sum(case when deemed_approved_pct is not null then volume_mn end), 0), 4) as deemed_approved_pct,
        sum(debit_reversal_count_mn)                                             as debit_reversal_count_mn,
        round(sum(debit_reversal_count_mn * debit_reversal_success_pct) / nullif(sum(case when debit_reversal_success_pct is not null then debit_reversal_count_mn end), 0), 4) as debit_reversal_success_pct,
        avg(udir_auto_update_sr_pct)                                             as udir_auto_update_sr_pct,
        avg(udir_refund_sr_pct)                                                  as udir_refund_sr_pct,
        max(bank_name_published)                                                 as bank_name_published,
        max(source_url)                                                          as source_url,
        max(_loaded_at)                                                          as _loaded_at
    from {{ ref('int_bank_monthly__unioned') }}
    group by bank_id, period_month, role
),
windowed as (
    select
        *,
        lag(td_pct)    over w                                                    as td_pct_prev_month,
        lag(volume_mn) over w                                                    as volume_mn_prev_month,
        lag(period_month) over w                                                 as prev_period_month,
        -- volume-weighted TD over the 3 months before this one
        sum(volume_mn * td_pct) over w3 / nullif(sum(volume_mn) over w3, 0)      as td_pct_baseline_3m,
        count(td_pct) over w3                                                    as baseline_months,
        stddev_samp(td_pct) over w6                                              as td_pct_volatility_6m,
        sum(volume_mn * td_pct) over w3cur / nullif(sum(volume_mn) over w3cur, 0) as td_pct_trailing_3m,
        sum(volume_mn * td_pct) over wprev3 / nullif(sum(volume_mn) over wprev3, 0) as td_pct_prior_3m
    from combined
    window
        w     as (partition by bank_id, role order by period_month),
        w3    as (partition by bank_id, role order by period_month rows between 3 preceding and 1 preceding),
        w3cur as (partition by bank_id, role order by period_month rows between 2 preceding and current row),
        wprev3 as (partition by bank_id, role order by period_month rows between 5 preceding and 3 preceding),
        w6    as (partition by bank_id, role order by period_month rows between 5 preceding and current row)
)
select
    *,
    -- lag() may skip a gap month if the bank fell out of the top 50; only trust adjacent months
    case when months_between(period_month, prev_period_month) = 1 then td_pct - td_pct_prev_month end as td_pct_mom_change,
    case when months_between(period_month, prev_period_month) = 1 then volume_mn / nullif(volume_mn_prev_month, 0) - 1 end as volume_mom_growth,
    -- last 3 months vs the 3 before them (positive = getting worse)
    td_pct_trailing_3m - td_pct_prior_3m                                         as td_pct_trend_3m,
    volume_mn * 1e6 * td_pct / 100                                               as est_technical_failures,
    volume_mn * 1e6 * bd_pct / 100                                               as est_business_failures,
    coalesce(
        baseline_months = 3
        and td_pct - td_pct_baseline_3m >= {{ var('degradation_abs_pp') }}
        and td_pct >= td_pct_baseline_3m * {{ var('degradation_rel_multiple') }},
        false)                                                                   as is_degraded
from windowed
