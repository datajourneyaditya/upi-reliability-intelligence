{# Uniqueness at the declared grain. #}
{% test unique_combination(model, columns) %}
select {{ columns | join(', ') }}, count(*) as n
from {{ model }}
group by {{ columns | join(', ') }}
having count(*) > 1
{% endtest %}

{# Percentages must sit in [0, 100]. Nulls are allowed (NPCI leaves some cells blank). #}
{% test pct_range(model, column_name, min_value=0, max_value=100) %}
select * from {{ model }}
where {{ column_name }} < {{ min_value }} or {{ column_name }} > {{ max_value }}
{% endtest %}

{# approved + BD + TD (+ deemed approved) should reconcile to ~100%. Rows missing any part are
   skipped. Severity warn: NPCI rounding occasionally lands just outside the tolerance. #}
{% test rates_reconcile(model, parts, tolerance=var('reconciliation_tolerance_pp')) %}
{{ config(severity='warn', warn_if='>0') }}
select *, ({{ parts | join(' + ') }}) as rate_total
from {{ model }}
where {% for p in parts %}{{ p }} is not null{% if not loop.last %} and {% endif %}{% endfor %}
  and abs(({{ parts | join(' + ') }}) - 100) > {{ tolerance }}
{% endtest %}
