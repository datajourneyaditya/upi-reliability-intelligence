with src as (
    select * from {{ source('npci_raw', 'npci_stat_rows') }}
    where dataset = 'remitter_banks'
)
select
    cast(period_month as date)                                          as period_month,
    row_num as source_row,
    try_cast(coalesce(fields['sr_no'], fields['srno']) as int)           as source_rank,
    trim(fields['upi_remitter_banks'])                                  as bank_name_published,
    {{ parse_num("fields['total_volume_in_mn']") }}                     as volume_mn,
    {{ parse_pct("fields['approved_percent']") }}                       as approved_pct,
    {{ parse_pct("fields['bd_percent']") }}                             as bd_pct,
    {{ parse_pct("fields['td_percent']") }}                             as td_pct,
    {{ parse_num("fields['total_debit_reversal_count_in_mn']") }}       as debit_reversal_count_mn,
    -- Aug 2022 was published x100 ('9123.00%' = 91.23%); rescale values above 100 and flag them.
    case when {{ parse_pct("fields['debit_reversal_success_percent']") }} > 100
         then {{ parse_pct("fields['debit_reversal_success_percent']") }} / 100
         else {{ parse_pct("fields['debit_reversal_success_percent']") }} end as debit_reversal_success_pct,
    coalesce({{ parse_pct("fields['debit_reversal_success_percent']") }} > 100, false) as is_debit_reversal_rescaled,
    {{ parse_pct("fields['udir_auto_update_sr_percent']") }}            as udir_auto_update_sr_pct,
    {{ parse_pct("fields['udir_refund_sr_percent']") }}                 as udir_refund_sr_pct,
    source_url,
    _loaded_at
from src
where nullif(trim(fields['upi_remitter_banks']), '') is not null
