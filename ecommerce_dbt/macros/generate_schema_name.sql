{# Override domyślnego generate_schema_name.
   W dev: łączy target.schema (dbt_dev_<user>) z custom_schema_name (staging, gold, snapshots).
   W prod: używa surowej nazwy custom_schema — modele trafiają do gold, snapshots.
   Efekt (dev):  dbt_dev_michal_gold, dbt_dev_michal_staging
   Efekt (prod): gold, snapshots (w katalogu ecommerce_prod)
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- set default_schema = target.schema -%}
    {%- if target.name == 'prod' and custom_schema_name is not none -%}
        {{ custom_schema_name | trim }}
    {%- elif custom_schema_name is none -%}
        {{ default_schema }}
    {%- else -%}
        {{ default_schema }}_{{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
