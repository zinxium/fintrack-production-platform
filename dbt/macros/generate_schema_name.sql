{% macro generate_schema_name(custom_schema_name, node) -%}
    {#-
        Convention multi-environnement :
          - target.name = 'prod'  → <custom>_<SUFFIX?>
                                    (SUFFIX vient de env DBT_SCHEMA_SUFFIX,
                                    utilisé pour blue/green ex : _BLUE)
          - target.name = 'ci'    → CI_<custom>_<PR_ID>
          - target.name = 'dev'   → <default>_<custom>

        Exemple prod avec DBT_SCHEMA_SUFFIX=_BLUE et +schema: marts_core :
            → MARTS_CORE_BLUE
        Exemple prod normal :
            → MARTS_CORE
    -#}
    {%- set default_schema = target.schema -%}
    {%- set suffix = env_var('DBT_SCHEMA_SUFFIX', '') -%}

    {%- if target.name == 'prod' -%}
        {%- if custom_schema_name is none -%}
            {{ default_schema }}{{ suffix }}
        {%- else -%}
            {{ custom_schema_name | trim | upper }}{{ suffix }}
        {%- endif -%}

    {%- elif target.name == 'ci' -%}
        {%- set pr_id = env_var('DBT_CI_PR_ID', 'unknown') -%}
        {%- if custom_schema_name is none -%}
            CI_{{ default_schema }}_{{ pr_id }}
        {%- else -%}
            CI_{{ custom_schema_name | trim }}_{{ pr_id }}
        {%- endif -%}

    {%- else -%}
        {%- if custom_schema_name is none -%}
            {{ default_schema }}
        {%- else -%}
            {{ default_schema }}_{{ custom_schema_name | trim }}
        {%- endif -%}
    {%- endif -%}
{%- endmacro %}
