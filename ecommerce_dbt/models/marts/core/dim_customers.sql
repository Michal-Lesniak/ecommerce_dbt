-- Wymiar klientów — aktualna wersja klienta (jeden wiersz na customer_id).
-- Materializacja: table, schema: gold. Historia zmian obsłużona w dim_customers_snapshot (SCD2).

{{ config(
    materialized='table',
    schema='gold'
) }}

with source as (

    select * from {{ ref('stg_customers') }}

),

ranked as (

    select
        *,
        row_number() over (partition by customer_id order by updated_at desc) as rn
    from source

),

current_only as (

    select * from ranked where rn = 1

)

select
    {{ dbt_utils.generate_surrogate_key(['customer_id']) }}    as customer_sk,
    customer_id,
    email,
    country,
    case country
        when 'PL' then 'Polska'
        when 'DE' then 'Niemcy'
        when 'CZ' then 'Czechy'
        when 'SK' then 'Słowacja'
        when 'HU' then 'Węgry'
        when 'RO' then 'Rumunia'
        when 'UA' then 'Ukraina'
        when 'AT' then 'Austria'
        else 'Inne'
    end                                                        as country_name,
    created_at,
    updated_at,
    current_timestamp()                                        as dbt_loaded_at
from current_only
