with src as (
    select * from {{ source('npci_raw', 'npci_stat_rows') }}
    where dataset in ('payer_psp', 'payee_psp')
),
parsed as (
    select
        cast(period_month as date)                                          as period_month,
        case dataset when 'payer_psp' then 'payer' else 'payee' end         as psp_role,
        row_num                                                             as source_row,
        try_cast(coalesce(fields['sr_no'], fields['srno']) as int)           as source_rank,
        trim(coalesce(fields['payer_psp'], fields['payee_psp']))            as psp_name_published,
        {{ parse_num("fields['total_volume_in_mn']") }}                     as volume_mn,
        {{ parse_pct("fields['approved_percent']") }}                       as approved_pct,
        {{ parse_pct("fields['bd_percent']") }}                             as bd_pct,
        {{ parse_pct("fields['td_percent']") }}                             as td_pct,
        source_url,
        _loaded_at
    from src
    where nullif(trim(coalesce(fields['payer_psp'], fields['payee_psp'])), '') is not null
),
scaled as (
    -- May and Jun 2026 were published as fractions (0.99 rather than 99%). A row whose parts sum
    -- to ~1 instead of ~100 is rescaled x100 and flagged.
    select *, coalesce(approved_pct + bd_pct + td_pct between 0.9 and 1.1, false) as is_fraction_rescaled
    from parsed
)
select
    period_month, psp_role, source_row, source_rank, psp_name_published, volume_mn,
    round(case when is_fraction_rescaled then approved_pct * 100 else approved_pct end, 4) as approved_pct,
    round(case when is_fraction_rescaled then bd_pct * 100 else bd_pct end, 4)             as bd_pct,
    round(case when is_fraction_rescaled then td_pct * 100 else td_pct end, 4)             as td_pct,
    is_fraction_rescaled,
    source_url,
    _loaded_at
from scaled
