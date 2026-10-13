-- Warstwa staging: czyszczenie i standaryzacja tabeli orders z Bronze.
-- Materializacja: view. Cast typów, normalizacja statusu, wyliczenie order_date, filtry na PK i sensowność kwot.

with source as (

    select * from {{ source('ecommerce_bronze', 'orders') }}

),

cleaned as (

    select
        cast(order_id       as bigint)                     as order_id,
        cast(customer_id    as bigint)                     as customer_id,
        lower(trim(cast(status as string)))                as order_status,
        cast(total_amount   as decimal(12,2))              as total_amount_pln,
        cast(ordered_at     as timestamp)                  as ordered_at,
        cast(ordered_at     as date)                       as order_date,
        cast(ingested_at    as timestamp)                  as ingested_at
    from source
    where order_id is not null
      and customer_id is not null
      and cast(total_amount as decimal(12,2)) >= 0

)

select * from cleaned
