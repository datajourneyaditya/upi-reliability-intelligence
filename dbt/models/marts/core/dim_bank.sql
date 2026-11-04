-- SCD Type 2 bank dimension.
-- Versions come from two real sources of change:
--   * the name NPCI published for the bank (e.g. 'National Payments Corporation of India (BHIM)'
--     -> 'NPCI BHIM Services (NBSL)', 'AU Small Finance Bank' -> '... (Erstwhile Fincare)')
--   * reference-data changes captured by the snap_bank_master snapshot (category, mergers)
-- A version is valid from the first month it was published until the month before the next one.
with monthly_name as (
    -- the dominant published spelling per bank per month
    select bank_id, period_month, bank_name_published
    from (
        select bank_id, period_month, bank_name_published,
               row_number() over (partition by bank_id, period_month order by volume_mn desc) as rn
        from (
            select bank_id, period_month, bank_name_published, volume_mn from {{ ref('int_bank_monthly__unioned') }}
            union all
            select r.bank_id, p.period_month, p.psp_name_published, p.volume_mn
            from {{ ref('stg_npci__psp_performance') }} p
            join {{ ref('int_bank_name_resolution') }} r on r.name_published = p.psp_name_published
        )
    ) where rn = 1
),
name_runs as (
    -- collapse consecutive months with the same spelling (ignoring case / punctuation) into one version
    select *, sum(is_change) over (partition by bank_id order by period_month) as version_no
    from (
        select *, case when {{ name_key('bank_name_published') }}
                        = {{ name_key("lag(bank_name_published) over (partition by bank_id order by period_month)") }}
                       then 0 else 1 end as is_change
        from monthly_name
    )
),
versions as (
    select bank_id, version_no,
           first(bank_name_published) as published_name,
           min(period_month) as valid_from
    from name_runs group by bank_id, version_no
),
ref_current as (
    select * from {{ ref('snap_bank_master') }} where dbt_valid_to is null
)
select
    md5(concat_ws('|', v.bank_id, cast(v.valid_from as string)))            as bank_sk,
    v.bank_id,
    coalesce(m.bank_name, v.published_name)                                 as bank_name,
    v.published_name,
    coalesce(m.bank_type, 'Unclassified')                                   as bank_type,
    m.parent_bank_id,
    m.merged_into_bank_id,
    v.version_no,
    v.valid_from,
    coalesce(date_sub(lead(v.valid_from) over (partition by v.bank_id order by v.valid_from), 1),
             cast('9999-12-31' as date))                                    as valid_to,
    lead(v.valid_from) over (partition by v.bank_id order by v.valid_from) is null as is_current,
    m.dbt_valid_from                                                        as reference_valid_from,
    r.resolution_method
from versions v
left join ref_current m on m.bank_id = v.bank_id
left join (select bank_id, min(resolution_method) as resolution_method
           from {{ ref('int_bank_name_resolution') }} group by bank_id) r on r.bank_id = v.bank_id
