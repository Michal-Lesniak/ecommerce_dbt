{# Makro price_tier — klasyfikuje kwotę do jednego z 4 koszyków cenowych.
   Parametry:
     amount_column — nazwa kolumny SQL z kwotą (string, np. 'total_amount_pln' lub 'io.total_amount_pln')
   Zwraca: wyrażenie CASE WHEN jako fragment SQL.
   Progi:
     budget    — < 100 PLN
     standard  — 100–499.99 PLN
     premium   — 500–1999.99 PLN
     luxury    — >= 2000 PLN
   Użycie: dim_products (unit_price_pln), fct_orders (total_amount_pln).
#}
{% macro price_tier(amount_column) %}
    case
        when {{ amount_column }} is null              then null
        when {{ amount_column }} <  100               then 'budget'
        when {{ amount_column }} <  500               then 'standard'
        when {{ amount_column }} <  2000              then 'premium'
        else                                               'luxury'
    end
{% endmacro %}
