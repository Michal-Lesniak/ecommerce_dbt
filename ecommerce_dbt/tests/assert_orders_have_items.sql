-- Singular test: każde zamówienie o statusie 'completed' musi mieć przynajmniej 1 pozycję.
-- FAILS jeśli zwróci > 0 wierszy — completed bez pozycji to błąd biznesowy (nie można sprzedać "powietrza").

select
    o.order_id,
    o.customer_id,
    o.order_status,
    count(oi.order_item_id) as items_count
from {{ ref('stg_orders') }} o
left join {{ ref('stg_order_items') }} oi on oi.order_id = o.order_id
where o.order_status = 'completed'
group by o.order_id, o.customer_id, o.order_status
having count(oi.order_item_id) = 0
