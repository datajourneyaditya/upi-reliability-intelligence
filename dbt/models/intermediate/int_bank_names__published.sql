-- Every bank / PSP-bank name as NPCI published it, in any table, with first/last month seen.
with names as (
    select bank_name_published as name_published, period_month, 'remitter' as seen_in from {{ ref('stg_npci__remitter_banks') }}
    union all
    select bank_name_published, period_month, 'beneficiary' from {{ ref('stg_npci__beneficiary_banks') }}
    union all
    select psp_name_published, period_month, concat(psp_role, '_psp') from {{ ref('stg_npci__psp_performance') }}
)
select
    name_published,
    {{ name_key('name_published') }}  as name_key,
    min(period_month)                 as first_seen_month,
    max(period_month)                 as last_seen_month,
    count(distinct period_month)      as months_seen,
    array_sort(collect_set(seen_in))  as seen_in
from names
group by name_published
