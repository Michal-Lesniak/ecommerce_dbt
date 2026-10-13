{# Makro is_pl_holiday — flaga stałych świąt państwowych w Polsce.
   Ograniczenie: obsługuje TYLKO święta o stałych datach (1.01, 6.01, 1.05, 3.05, 15.08, 1.11, 11.11, 25.12, 26.12).
   Nie obsługuje świąt ruchomych (Wielkanoc, Zielone Świątki, Boże Ciało) — te wymagałyby algorytmu Gaussa.
   Parametry:
     date_column — nazwa kolumny SQL typu date (np. 'date_day' lub 'order_date')
   Zwraca: wyrażenie boolean SQL.
   Użycie: dim_date (flaga is_pl_holiday).
#}
{% macro is_pl_holiday(date_column) %}
    case
        when date_format({{ date_column }}, 'MM-dd') in (
            '01-01',  -- Nowy Rok
            '01-06',  -- Trzech Króli
            '05-01',  -- Święto Pracy
            '05-03',  -- Konstytucja 3 Maja
            '08-15',  -- Wniebowzięcie NMP
            '11-01',  -- Wszystkich Świętych
            '11-11',  -- Święto Niepodległości
            '12-25',  -- Boże Narodzenie
            '12-26'   -- Drugi dzień Bożego Narodzenia
        ) then true
        else false
    end
{% endmacro %}
