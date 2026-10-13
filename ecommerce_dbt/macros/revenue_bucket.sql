{# Makro revenue_bucket — segmentuje klientów po sumie przychodu.
   Rozwiązuje realną powtarzalność: taka sama logika koszyków jest potrzebna w fct_customer_clv
   oraz w ad-hoc analizach segmentacji (Power BI / ML feature engineering).
   Parametry:
     revenue_column — nazwa kolumny SQL z sumaryczną wartością (np. 'total_revenue_pln')
   Zwraca: wyrażenie CASE WHEN jako fragment SQL.
   Kubełki:
     none       — 0 PLN (klient bez completed)
     low        — < 500 PLN
     medium     — 500–1999.99 PLN
     high       — 2000–9999.99 PLN
     vip        — >= 10000 PLN
#}
{% macro revenue_bucket(revenue_column) %}
    case
        when {{ revenue_column }} is null              then 'none'
        when {{ revenue_column }} =  0                 then 'none'
        when {{ revenue_column }} <  500               then 'low'
        when {{ revenue_column }} <  2000              then 'medium'
        when {{ revenue_column }} <  10000             then 'high'
        else                                                'vip'
    end
{% endmacro %}
