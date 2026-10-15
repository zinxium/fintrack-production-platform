{% macro set_query_tag() %}
    {% if target.type == 'snowflake' %}
        {% set tag = 'team=data-eng|project=fintrack-production-platform|target=' ~ target.name ~ '|invocation=' ~ invocation_id %}
        {% do run_query("alter session set query_tag = '" ~ tag ~ "'") %}
        {% do log("Query tag: " ~ tag, info=True) %}
    {% endif %}
{% endmacro %}

{% macro unset_query_tag() %}
    {% if target.type == 'snowflake' %}
        {% do run_query("alter session unset query_tag") %}
    {% endif %}
{% endmacro %}
