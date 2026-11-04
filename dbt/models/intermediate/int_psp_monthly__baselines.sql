-- PSP banks (payer / payee side): same baseline + degradation logic as banks, per psp x role.
with resolved as (
    select p.*, r.bank_id
    from {{ ref('stg_npci__psp_performance') }} p
    join {{ ref('int_bank_name_resolution') }} r on r.name_published = p.psp_name_published
),
combined as (
    select
        bank_id, period_month, psp_role as role,
        min(source_rank)                                                         as source_rank,
        sum(volume_mn)                                                           as volume_mn,
        round(sum(volume_mn * approved_pct) / nullif(sum(volume_mn), 0), 4)                as approved_pct,
        round(sum(volume_mn * bd_pct) / nullif(sum(volume_mn), 0), 4)                      as bd_pct,
        round(sum(volume_mn * td_pct) / nullif(sum(volume_mn), 0), 4)                      as td_pct,
        max(psp_name_published)                                                  as psp_name_published,
        max(source_url)                                                          as source_url,
        max(_loaded_at)                                                          as _loaded_at
    from resolved
    group by bank_id, period_month, psp_role
),
windowed as (
    select
        *,
        lag(td_pct) over w                                                       as td_pct_prev_month,
        lag(period_month) over w                                                 as prev_period_month,
        sum(volume_mn * td_pct) over w3 / nullif(sum(volume_mn) over w3, 0)      as td_pct_baseline_3m,
        count(td_pct) over w3                                                    as baseline_months,
        sum(volume_mn * td_pct) over w3cur / nullif(sum(volume_mn) over w3cur, 0) as td_pct_trailing_3m,
        sum(volume_mn * td_pct) over wprev3 / nullif(sum(volume_mn) over wprev3, 0) as td_pct_prior_3m,
        stddev_samp(td_pct) over w6                                              as td_pct_volatility_6m
    from combined
    window
        w      as (partition by bank_id, role order by period_month),
        w3     as (partition by bank_id, role order by period_month rows between 3 preceding and 1 preceding),
        w3cur  as (partition by bank_id, role order by period_month rows between 2 preceding and current row),
        wprev3 as (partition by bank_id, role order by period_month rows between 5 preceding and 3 preceding),
        w6     as (partition by bank_id, role order by period_month rows between 5 preceding and current row)
)
select
    *,
    case when months_between(period_month, prev_period_month) = 1 then td_pct - td_pct_prev_month end as td_pct_mom_change,
    td_pct_trailing_3m - td_pct_prior_3m                                         as td_pct_trend_3m,
    volume_mn * 1e6 * td_pct / 100                                               as est_technical_failures,
    volume_mn * 1e6 * bd_pct / 100                                               as est_business_failures,
    coalesce(
        baseline_months = 3
        and td_pct - td_pct_baseline_3m >= {{ var('degradation_abs_pp') }}
        and td_pct >= td_pct_baseline_3m * {{ var('degradation_rel_multiple') }},
        false)                                                                   as is_degraded
from windowed
