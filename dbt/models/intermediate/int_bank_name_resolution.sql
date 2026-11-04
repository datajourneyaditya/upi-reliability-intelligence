-- Resolves every published spelling to one canonical bank_id.
-- 1) exact alias override from seeds/bank_aliases.csv (for spellings the key can't reconcile)
-- 2) otherwise the normalised name key matched to seeds/bank_master.csv
with published as (
    select * from {{ ref('int_bank_names__published') }}
),
aliases as (
    select {{ name_key('alias_name') }} as name_key, bank_id from {{ ref('bank_aliases') }}
),
master as (
    select bank_id, {{ name_key('bank_name') }} as name_key from {{ ref('bank_master') }}
)
select
    p.name_published,
    p.name_key,
    coalesce(a.bank_id, m.bank_id, concat('unmapped:', p.name_key)) as bank_id,
    case when a.bank_id is not null then 'alias'
         when m.bank_id is not null then 'name_key'
         else 'unmapped' end                                        as resolution_method,
    p.first_seen_month,
    p.last_seen_month,
    p.months_seen
from published p
left join aliases a on a.name_key = p.name_key
left join master  m on m.name_key = p.name_key
