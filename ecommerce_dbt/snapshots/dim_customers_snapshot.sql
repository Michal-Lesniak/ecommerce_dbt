{% snapshot dim_customers_snapshot %}

{{
    config(
      target_schema='snapshots',
      target_database='ecommerce_dev',
      unique_key='customer_id',
      strategy='timestamp',
      updated_at='updated_at',
      invalidate_hard_deletes=True
    )
}}

-- Snapshot SCD2 dla klientów.
-- Śledzimy tylko atrybuty o wartości historycznej (email, country). Timestampy created_at / updated_at
-- są tu też, bo updated_at jest kluczem strategii i created_at pomaga audytować.

select
    customer_id,
    email,
    country,
    created_at,
    updated_at
from {{ ref('stg_customers') }}

{% endsnapshot %}
