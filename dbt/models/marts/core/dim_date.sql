-- Month-level calendar covering every month NPCI data exists for, plus Indian fiscal year.
with bounds as (
    select min(period_month) as lo, max(period_month) as hi from {{ ref('stg_npci__ecosystem_monthly') }}
)
select
    m                                                       as period_month,
    cast(date_format(m, 'yyyyMM') as int)                   as month_key,
    year(m)                                                 as calendar_year,
    month(m)                                                as month_of_year,
    date_format(m, 'MMM yyyy')                              as month_label,
    concat('FY', case when month(m) >= 4 then year(m) + 1 else year(m) end % 100) as fiscal_year,
    concat('Q', floor(((month(m) + 8) % 12) / 3) + 1)       as fiscal_quarter,
    last_day(m)                                             as month_end,
    day(last_day(m))                                        as days_in_month
from bounds
lateral view explode(sequence(lo, hi, interval 1 month)) as m
