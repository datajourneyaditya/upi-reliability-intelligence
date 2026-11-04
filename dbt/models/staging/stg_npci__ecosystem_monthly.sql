-- NPCI labels months as 'March-2026'.
select
    to_date(concat('01-', trim(fields['month'])), 'dd-MMMM-yyyy')        as period_month,
    try_cast(regexp_replace(fields['no_of_banks_live_on_upi'], '[,\\s]', '') as int) as banks_live,
    {{ parse_num("fields['volume_in_mn']") }}                          as volume_mn,
    {{ parse_num("fields['value_in_cr']") }}                           as value_cr,
    source_url,
    _loaded_at
from {{ source('npci_raw', 'npci_stat_rows') }}
where dataset = 'ecosystem_monthly'
