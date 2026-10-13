-- Singular test biznesowy: total_revenue_pln w fct_customer_clv musi zgadzać się z sumą
-- total_amount_pln z fct_orders (tylko completed) dla tego samego klienta.
-- FAILS jeśli różnica > 0.01 PLN — łapiemy sytuację, w której CLV zaczęłoby liczyć np. pending.

with clv as (
    select customer_sk, total_revenue_pln
    from {{ ref('fct_customer_clv') }}
),
orders_completed as (
    select
        customer_sk,
        cast(sum(total_amount_pln) as decimal(14,2)) as expected_revenue_pln
    from {{ ref('fct_orders') }}
    where order_status = 'completed'
    group by customer_sk
),
joined as (
    select
        c.customer_sk,
        c.total_revenue_pln,
        coalesce(o.expected_revenue_pln, 0) as expected_revenue_pln
    from clv c
    left join orders_completed o on o.customer_sk = c.customer_sk
)
select *
from joined
where abs(total_revenue_pln - expected_revenue_pln) > 0.01
