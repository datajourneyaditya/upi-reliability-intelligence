-- Remitter (payer side) and beneficiary (payee side) rows on one grain: bank x month x role.
with remitter as (
    select period_month, 'remitter' as role, source_rank, bank_name_published, volume_mn,
           approved_pct, bd_pct, td_pct, cast(null as double) as deemed_approved_pct,
           debit_reversal_count_mn, debit_reversal_success_pct,
           udir_auto_update_sr_pct, udir_refund_sr_pct, source_url, _loaded_at
    from {{ ref('stg_npci__remitter_banks') }}
),
beneficiary as (
    select period_month, 'beneficiary', source_rank, bank_name_published, volume_mn,
           approved_pct, bd_pct, td_pct, deemed_approved_pct,
           null, null, udir_auto_update_sr_pct, null, source_url, _loaded_at
    from {{ ref('stg_npci__beneficiary_banks') }}
)
select u.*, r.bank_id
from (select * from remitter union all select * from beneficiary) u
join {{ ref('int_bank_name_resolution') }} r on r.name_published = u.bank_name_published
