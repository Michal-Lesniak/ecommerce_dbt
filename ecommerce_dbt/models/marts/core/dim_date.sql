-- Wymiar daty — pełen kalendarz dat od var('start_date') do dziś + 5 lat.
-- Materializacja: table, schema: gold. Wykorzystuje dbt_utils.date_spine.
-- is_pl_holiday obsługuje stałe święta państwowe PL (bez świąt ruchomych typu Wielkanoc).

{{ config(materialized='table', schema='gold') }}

with date_spine as (

    {{ dbt_utils.date_spine(
        datepart='day',
        start_date="cast('" ~ var('start_date') ~ "' as date)",
        end_date="cast(dateadd(year, 5, current_date()) as date)"
    ) }}

),

enriched as (

    select
        cast(date_day as date)                                              as date_id,
        extract(year    from date_day)                                      as year,
        extract(quarter from date_day)                                      as quarter,
        extract(month   from date_day)                                      as month,
        extract(week    from date_day)                                      as week,
        extract(day     from date_day)                                      as day_of_month,
        extract(dayofweek from date_day)                                    as day_of_week,
        case when extract(dayofweek from date_day) in (1, 7)
             then true else false end                                       as is_weekend,
        {{ is_pl_holiday('date_day') }}                                     as is_pl_holiday,
        date_format(date_day, 'yyyy-MM')                                    as year_month,
        date_format(date_day, 'EEEE')                                       as day_name_en
    from date_spine

)

select * from enriched
