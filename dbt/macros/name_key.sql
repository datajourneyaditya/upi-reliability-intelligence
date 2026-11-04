{# Spelling-insensitive key for bank / PSP names: 'The Federal Bank Ltd.' -> 'federal bank'. #}
{% macro name_key(expr) -%}
trim(regexp_replace(
    regexp_replace(
        regexp_replace(lower(replace({{ expr }}, '&', ' and ')), '[^a-z0-9 ]', ' '),
        '\\b(the|ltd|limited|pvt|private)\\b', ' '),
    '\\s+', ' '))
{%- endmacro %}
