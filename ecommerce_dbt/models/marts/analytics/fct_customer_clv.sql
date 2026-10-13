-- Customer Lifetime Value. Grain: 1 wiersz = 1 klient.
-- Materializacja: table, schema: gold.
-- Konwencja liczenia:
--   total_orders       — WSZYSTKIE statusy (klient złożył N zamówień)
--   completed_orders   — tylko 'completed'
--   total_revenue_pln  — tylko 'completed' (pending / cancelled NIE generują przychodu)

{{ config(
    materialized='table',
    schema='gold'
) }}

with orders as (

    select * from {{ ref('fct_orders') }}

),

customer_stats as (

    select
        customer_sk,
        customer_id,
        customer_country,

        min(order_date)                                                     as first_order_date,
        max(order_date)                                                     as last_order_date,

        count(distinct order_id)                                            as total_orders,
        count(distinct case when order_status = 'completed' then order_id end) as completed_orders,

        cast(
            sum(case when order_status = 'completed' then total_amount_pln else 0 end)
            as decimal(14,2)
        )                                                                   as total_revenue_pln

    from orders
    group by customer_sk, customer_id, customer_country

)

select
    customer_sk,
    customer_id,
    customer_country,
    first_order_date,
    last_order_date,
    total_orders,
    completed_orders,
    total_revenue_pln,
    datediff(last_order_date, first_order_date)                             as days_active,
    case when last_order_date >= date_sub(current_date(), 90)
         then true else false end                                           as is_active_last_90d,
    {{ revenue_bucket('total_revenue_pln') }}                               as revenue_bucket,
    current_timestamp()                                                     as dbt_loaded_at
from customer_stats
