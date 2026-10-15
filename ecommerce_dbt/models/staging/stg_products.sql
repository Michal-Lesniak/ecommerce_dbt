-- Warstwa staging: standaryzacja katalogu produktów z Bronze.
-- Materializacja: view. Trim nazw, cast typów, filtr na PK.

with source as (

    select * from {{ source('ecommerce_bronze', 'products') }}

),

cleaned as (

    select
        cast(product_id      as bigint)                        as product_id,
        trim(cast(name as string))                     as product_name,
        lower(trim(cast(category as string)))                  as category,
        lower(trim(cast(subcategory as string)))               as subcategory,
        cast(price      as decimal(12,2))                 as unit_price_pln,
        cast(is_active       as boolean)                       as is_active,
        cast(updated_at      as timestamp)                     as updated_at
    from source
    where product_id is not null

)

select * from cleaned
