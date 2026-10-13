-- Warstwa intermediate: łączy zamówienia z pozycjami (agregat) i klientami.
-- Materializacja: ephemeral — model nie tworzy obiektu w warehouse, jest inline'owany do modeli marts.
-- Cel: raz zdefiniować kanoniczny join order + customer + agregaty pozycji, żeby fct_orders i fct_customer_clv miały spójne źródło.

with orders as (

    select * from {{ ref('stg_orders') }}

),

order_items as (

    select * from {{ ref('stg_order_items') }}

),

customers as (

    select * from {{ ref('stg_customers') }}

),

order_aggregates as (

    select
        order_id,
        count(distinct product_id)                                  as items_count,
        sum(quantity)                                               as total_quantity,
        cast(sum(quantity * unit_price) as decimal(14,2))           as items_value_pln
    from order_items
    group by order_id

)

select
    o.order_id,
    o.customer_id,
    c.country                                                       as customer_country,
    c.email                                                         as customer_email,
    o.order_status,
    o.total_amount_pln,
    coalesce(oa.items_count, 0)                                     as items_count,
    coalesce(oa.total_quantity, 0)                                  as total_quantity,
    coalesce(oa.items_value_pln, cast(0 as decimal(14,2)))          as items_value_pln,
    o.ordered_at,
    o.order_date
from orders o
left join customers c           on c.customer_id = o.customer_id
left join order_aggregates oa   on oa.order_id   = o.order_id
