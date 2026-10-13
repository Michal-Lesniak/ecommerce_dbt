-- Analiza audytowa jakości danych — porównuje warstwy Bronze -> Staging -> Gold.
-- Uruchom przez: dbt compile --select audit_data_quality
-- Skompilowany SQL wklej do Databricks SQL Editor.

with orders_bronze as (
    select count(*) as n from {{ source('ecommerce_bronze', 'orders') }}
),
orders_staging as (
    select count(*) as n from {{ ref('stg_orders') }}
),
orders_gold as (
    select count(*) as n from {{ ref('fct_orders') }}
),
completed_pct as (
    select
        cast(sum(case when order_status = 'completed' then 1 else 0 end) as double)
        / nullif(count(*), 0) * 100 as pct_completed
    from {{ ref('fct_orders') }}
),
orders_with_items as (
    select
        cast(sum(case when items_count > 0 then 1 else 0 end) as double)
        / nullif(count(*), 0) * 100 as pct_with_items
    from {{ ref('int_orders_enriched') }}
)
select 'orders_bronze'         as warstwa, (select n from orders_bronze) as liczba, null as pct
union all
select 'orders_staging',                (select n from orders_staging),      null
union all
select 'orders_gold (fct_orders)',      (select n from orders_gold),         null
union all
select 'pct_completed',                 null, (select pct_completed from completed_pct)
union all
select 'pct_orders_with_items',         null, (select pct_with_items from orders_with_items)
