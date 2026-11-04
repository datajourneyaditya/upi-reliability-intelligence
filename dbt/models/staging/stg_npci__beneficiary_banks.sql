with src as (
    select * from {{ source('npci_raw', 'npci_stat_rows') }}
    where dataset = 'beneficiary_banks'
),
parsed as (
select
    cast(period_month as date)                                          as period_month,
    row_num as source_row,
    try_cast(coalesce(fields['sr_no'], fields['srno']) as int)           as source_rank,
    trim(fields['upi_beneficiary_banks'])                               as bank_name_published,
    {{ parse_num("fields['total_volume_in_mn']") }}                     as volume_mn,
    {{ parse_pct("fields['approved_percent']") }}                       as approved_pct,
    {{ parse_pct("fields['bd_percent']") }}                             as bd_pct,
    {{ parse_pct("fields['td_percent']") }}                             as td_pct,
    {{ parse_pct("fields['deemed_approved_percent']") }}                as deemed_approved_pct,
    {{ parse_pct("fields['udir_auto_update_sr_percent']") }}            as udir_auto_update_sr_pct,
    source_url,
    _loaded_at
from src
where nullif(trim(fields['upi_beneficiary_banks']), '') is not null
)
-- An approved % above 100 is a publishing typo (e.g. Tamilnad Mercantile Bank, Sep 2024: 124.22%);
-- rebuild it from the other published parts and flag the row.
select
    period_month, source_row, source_rank, bank_name_published, volume_mn,
    case when approved_pct > 100 then 100 - bd_pct - td_pct - coalesce(deemed_approved_pct, 0) else approved_pct end as approved_pct,
    bd_pct, td_pct, deemed_approved_pct, udir_auto_update_sr_pct,
    coalesce(approved_pct > 100, false) as is_approved_pct_rebuilt,
    source_url, _loaded_at
from parsed
