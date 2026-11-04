{# Drop every schema created for this CI run (ci_<suffix>_*). Refuses to run outside the ci target. #}
{% macro drop_ci_schemas() %}
  {% if target.name != 'ci' %}{{ exceptions.raise_compiler_error('drop_ci_schemas only runs on the ci target') }}{% endif %}
  {% set schemas = run_query("show schemas in " ~ target.database ~ " like '" ~ target.schema ~ "*'") %}
  {% for row in schemas %}
    {% do run_query("drop schema if exists " ~ target.database ~ "." ~ row[0] ~ " cascade") %}
    {% do log("dropped " ~ row[0], info=True) %}
  {% endfor %}
{% endmacro %}
