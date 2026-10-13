-- Singular test: zamówienie NIE może mieć ujemnej wartości.
-- FAILS jeśli zwróci > 0 wierszy — to znaczy że któreś zamówienie ma total_amount_pln < 0.
-- Uzupełnia dbt_utils.expression_is_true w YAML: dodatkowa warstwa obrony na przypadek
-- gdyby ktoś zmienił filtr w stg_orders.

select
    order_id,
    customer_id,
    order_status,
    total_amount_pln
from {{ ref('stg_orders') }}
where total_amount_pln < 0
