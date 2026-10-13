-- Fakt dziennych przychodów. Grain: 1 wiersz = 1 data × 1 kraj.
-- Materializacja: table, schema: gold. Liczymy TYLKO zamówienia 'completed' — pending / cancelled nie generują przychodu.

{{ config(
    materialized='table',
    schema='gold'
) }}

with orders as (

    select *
    from {{ ref('fct_orders') }}
    where order_status = 'completed'

),

daily as (

    select
        order_date                                                          as date_id,
        customer_country                                                    as country,
        cast(sum(total_amount_pln) as decimal(14,2))                        as revenue_pln,
        count(distinct order_id)                                            as orders_count,
        count(distinct customer_id)                                         as unique_customers
    from orders
    group by order_date, customer_country

)

select
    date_id,
    country,
    revenue_pln,
    orders_count,
    unique_customers,
    cast(revenue_pln / nullif(orders_count, 0) as decimal(14,2))            as aov_pln,
    current_timestamp()                                                     as dbt_loaded_at
from daily
