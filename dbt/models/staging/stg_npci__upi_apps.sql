with src as (
    select *, trim(coalesce(fields['application_name'], fields['upi_application_name'])) as app_raw
    from {{ source('npci_raw', 'npci_stat_rows') }}
    where dataset = 'upi_apps'
)
select
    cast(period_month as date)                                                       as period_month,
    row_num as source_row,
    try_cast(coalesce(fields['srno'], fields['sr_no']) as int)                        as source_rank,
    app_raw                                                                          as app_name_published,
    trim(regexp_replace(app_raw, '[#*]+', ''))                                       as app_name,
    -- case / spacing-insensitive key: 'Mobikwik' and 'MobiKwik' are one app
    regexp_replace(lower(regexp_replace(app_raw, '[#*]+', '')), '[^a-z0-9]', '')         as app_key,
    app_raw like '%#%'                                                               as is_third_party_app,
    {{ parse_num("fields['customer_initiated_transactions_volume_mn']") }}           as customer_initiated_volume_mn,
    {{ parse_num("fields['customer_initiated_transactions_value_cr']") }}            as customer_initiated_value_cr,
    {{ parse_num("fields['b_2_c_transactions_volume_mn']") }}                        as b2c_volume_mn,
    {{ parse_num("fields['b_2_b_transactions_volume_mn']") }}                        as b2b_volume_mn,
    coalesce({{ parse_num("fields['total_volume_mn']") }}, {{ parse_num("fields['upi_volume_mn']") }}) as total_volume_mn,
    coalesce({{ parse_num("fields['total_value_cr']") }}, {{ parse_num("fields['upi_value_cr']") }})   as total_value_cr,
    source_url,
    _loaded_at
from src
where nullif(app_raw, '') is not null
