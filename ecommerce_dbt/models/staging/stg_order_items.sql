-- Warstwa staging: standaryzacja pozycji zamówień z Bronze.
-- Materializacja: view. Cast typów, filtry na PK i FK do orders, quantity > 0.

with source as (

    select * from {{ source('ecommerce_bronze', 'order_items') }}

),

cleaned as (

    select
        cast(order_item_id  as bigint)                         as order_item_id,
        cast(order_id       as bigint)                         as order_id,
        cast(product_id     as bigint)                         as product_id,
        cast(quantity       as int)                            as quantity,
        cast(unit_price     as decimal(12,2))                  as unit_price,
        cast(ingested_at    as timestamp)                      as ingested_at
    from source
    where order_item_id is not null
      and order_id is not null
      and cast(quantity as int) > 0

)

select * from cleaned
