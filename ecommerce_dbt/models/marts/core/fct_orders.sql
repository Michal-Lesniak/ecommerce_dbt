-- Tabela faktów zamówień — grain: 1 wiersz = 1 zamówienie.
-- Materializacja: incremental, strategy: merge, unique_key: order_sk.
-- Merge (a nie append) — status zamówienia zmienia się w czasie (pending -> completed / cancelled),
-- więc musimy nadpisać istniejący wiersz nowszą wersją, a nie duplikować.

{{ config(
    materialized='incremental',
    unique_key='order_sk',
    incremental_strategy='merge',
    on_schema_change='append_new_columns',
    schema='gold'
) }}

with int_orders as (

    select * from {{ ref('int_orders_enriched') }}

    {% if is_incremental() %}
    -- Idempotentny filtr: bierzemy zamówienia nowsze lub równe najświeższemu w targecie.
    -- Zakładka 3-dniowa łapie też korekty statusów wsteczne (pending -> completed po kilku dniach).
    where ordered_at >= (
        select coalesce(dateadd(day, -3, max(ordered_at)), cast('1900-01-01' as timestamp))
        from {{ this }}
    )
    {% endif %}

),

dim_customers as (

    select customer_sk, customer_id from {{ ref('dim_customers') }}

)

select
    {{ dbt_utils.generate_surrogate_key(['io.order_id']) }}    as order_sk,
    io.order_id,
    dc.customer_sk,
    io.customer_id,
    io.customer_country,
    io.order_status,
    io.total_amount_pln,
    {{ price_tier('io.total_amount_pln') }}                    as price_tier,
    io.items_count,
    io.total_quantity,
    io.ordered_at,
    io.order_date,
    current_timestamp()                                        as dbt_loaded_at
from int_orders io
left join dim_customers dc on dc.customer_id = io.customer_id
