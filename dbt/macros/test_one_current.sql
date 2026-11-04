{% test one_current_version_per_bank(model) %}
select bank_id from {{ model }} group by bank_id having count_if(is_current) <> 1
{% endtest %}
