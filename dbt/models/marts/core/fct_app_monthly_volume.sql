-- Grain: one row per UPI app x month. Volume / value only: NPCI does not publish app-level declines.
with apps as (
    select period_month, app_key, max_by(app_name, total_volume_mn) as app_name, max(is_third_party_app) as is_third_party_app,
           min(source_rank) as source_rank,
           sum(customer_initiated_volume_mn) as customer_initiated_volume_mn,
           sum(total_volume_mn) as total_volume_mn, sum(total_value_cr) as total_value_cr,
           max(source_url) as source_url, max(_loaded_at) as _loaded_at
    from {{ ref('stg_npci__upi_apps') }}
    group by period_month, app_key
)
select
    a.period_month,
    md5(a.app_key)                                                          as app_sk,
    a.app_name,
    a.source_rank,
    a.is_third_party_app,
    a.customer_initiated_volume_mn,
    a.total_volume_mn,
    a.total_value_cr,
    a.total_volume_mn / nullif(sum(a.total_volume_mn) over (partition by a.period_month), 0) as volume_share,
    a.total_value_cr * 1e7 / nullif(a.total_volume_mn * 1e6, 0)             as avg_ticket_inr,
    a.source_url,
    a._loaded_at
from apps a
