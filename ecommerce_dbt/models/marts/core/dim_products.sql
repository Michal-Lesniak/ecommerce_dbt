-- Wymiar produktów — jeden wiersz na product_id.
-- Materializacja: table, schema: gold. Wzbogacony o price_tier (własne makro).

{{ config(
    materialized='table',
    schema='gold'
) }}

with source as (

    select * from {{ ref('stg_products') }}

),

enriched as (

    select
        {{ dbt_utils.generate_surrogate_key(['product_id']) }}    as product_sk,
        product_id,
        product_name,
        category,
        subcategory,
        unit_price_pln,
        {{ price_tier('unit_price_pln') }}                        as price_tier,
        is_active,
        updated_at,
        current_timestamp()                                       as dbt_loaded_at
    from source

)

select * from enriched
