{# NPCI publishes rates as strings like '90.34%', '0.38 %', '-', '', 'NaN'. Return a DOUBLE or null. #}
{% macro parse_pct(expr) -%}
    nanvl(try_cast(nullif(nullif(trim(regexp_replace({{ expr }}, '[%,\\s]', '')), '-'), '') as double), cast(null as double))
{%- endmacro %}

{# Volumes are published in millions as strings, sometimes with Indian thousands separators. #}
{% macro parse_num(expr) -%}
    nanvl(try_cast(nullif(nullif(trim(regexp_replace({{ expr }}, '[,\\s]', '')), '-'), '') as double), cast(null as double))
{%- endmacro %}
