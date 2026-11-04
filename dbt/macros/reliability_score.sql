{#
  Reliability score, 0-100 (higher = more reliable), ranked among peers in the same month and role:
    50%  TD level      - trailing 3-month volume-weighted TD (lower is better)
    25%  TD trend      - last 3 months vs the 3 before (falling is better)
    25%  TD volatility - 6-month std dev of monthly TD (steadier is better)
  Each component is a percent_rank; a missing component (short history) counts as the median.
#}
{% macro reliability_score(level, trend, volatility, partition_by) -%}
round(100 * (
      0.50 * (1 - coalesce(case when {{ level }} is not null then percent_rank() over (partition by {{ partition_by }}, ({{ level }} is null) order by {{ level }}) end, 0.5))
    + 0.25 * (1 - coalesce(case when {{ trend }} is not null then percent_rank() over (partition by {{ partition_by }}, ({{ trend }} is null) order by {{ trend }}) end, 0.5))
    + 0.25 * (1 - coalesce(case when {{ volatility }} is not null then percent_rank() over (partition by {{ partition_by }}, ({{ volatility }} is null) order by {{ volatility }}) end, 0.5))
), 1)
{%- endmacro %}
