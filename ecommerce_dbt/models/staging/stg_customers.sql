-- Warstwa staging: standaryzacja tabeli customers z Bronze.
-- Materializacja: view. Normalizacja email (lower+trim) i country (upper), filtr na PK.

with source as (

    select * from {{ source('ecommerce_bronze', 'customers') }}

),

cleaned as (

    select
        cast(customer_id    as bigint)                          as customer_id,
        lower(trim(cast(email as string)))                      as email,
        upper(trim(cast(country as string)))                    as country,
        cast(created_at     as timestamp)                       as created_at,
        cast(updated_at     as timestamp)                       as updated_at,
        cast(ingested_at    as timestamp)                       as ingested_at
    from source
    where customer_id is not null

)

select * from cleaned
