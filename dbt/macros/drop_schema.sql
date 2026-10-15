{% macro drop_schema(schema_name) %}
    {#-
        Utilisée par la CI pour cleanup des schémas éphémères.
        Appel : dbt run-operation drop_schema --args "{schema_name: CI_42}"
    -#}
    {% set sql = "drop schema if exists " ~ target.database ~ "." ~ schema_name ~ " cascade" %}
    {{ log("Dropping schema: " ~ sql, info=True) }}
    {% do run_query(sql) %}
{% endmacro %}
