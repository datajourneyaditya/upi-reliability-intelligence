-- One row per UPI app seen in NPCI's app table, enriched with parent company and sponsor PSP
-- banks where known (seeds/psp_apps.csv).
with observed as (
    select app_key,
           max_by(app_name, period_month) as app_name,      -- latest published spelling
           max(is_third_party_app)        as is_third_party_app,
           min(period_month)              as first_seen_month,
           max(period_month)              as last_seen_month,
           count(distinct period_month)   as months_seen
    from {{ ref('stg_npci__upi_apps') }}
    group by app_key
)
select
    md5(o.app_key)                                       as app_sk,
    o.app_key,
    o.app_name,
    s.parent_company,
    coalesce(s.app_category, case when o.is_third_party_app then 'Third-party app' else 'Bank app' end) as app_category,
    o.is_third_party_app,
    split(s.sponsor_bank_ids, '\\|')                     as sponsor_bank_ids,
    split(s.vpa_handles, '\\|')                          as vpa_handles,
    o.first_seen_month,
    o.last_seen_month,
    o.months_seen
from observed o
left join {{ ref('psp_apps') }} s on regexp_replace(lower(s.app_name), '[^a-z0-9]', '') = o.app_key
