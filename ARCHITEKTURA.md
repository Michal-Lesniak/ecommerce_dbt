# Architektura projektu dbt — Miesiąc 07

Dokument opisuje **dlaczego** projekt jest zbudowany właśnie tak. Nie powiela README (jak uruchomić) — skupia się na trade-offach.

## 1. Warstwowanie modeli

### Dlaczego staging jako `view`?

Staging robi tylko dwie rzeczy: **cast typów** i **normalizację** (lower/trim/upper). To operacje na tyle tanie, że materializacja jako tabela oznaczałaby dodatkowy koszt storage i marnowanie czasu compute na coś, co i tak zostanie skonsumowane raz — przez `intermediate` / `marts`. View w Databricks SQL Warehouse jest inline'owany do zapytania, więc nie ma narzutu.

Dodatkowo: staging jest kontraktem "źródła prawdy" dla warstwy Gold. Jeśli źródło Bronze się zmieni (np. typ kolumny), przebudowa view jest darmowa. Tabela wymagałaby `--full-refresh`.

### Dlaczego intermediate jako `ephemeral`?

`int_orders_enriched` łączy `stg_orders` + `stg_order_items` (agregat) + `stg_customers`. Ta sama definicja jest potrzebna w `fct_orders` i w wielu ad-hoc analizach — chcę mieć **jedno miejsce prawdy**, ale nie chcę tworzyć dodatkowego obiektu w warehouse (kolejny schemat, kolejny grant, kolejny audit target).

Ephemeral rozwiązuje to: dbt wpina CTE w kompilowany SQL modelu-konsumenta. Zero storage, zero maintenance.

**Kiedy ephemeral byłby złym wyborem?** Gdy model jest cytowany przez 10+ innych — plan zapytań rośnie kwadratowo, a Spark musi za każdym razem rebuildować CTE. Wtedy lepiej dać `view` albo `table`. U nas — tylko 1 konsument (`fct_orders`), więc ephemeral pasuje.

### Dlaczego marts jako `table` / `incremental`?

Marts są konsumowane przez Power BI i ML — oba oczekują **niskiej latencji zapytań** i **stabilnego schematu**. View by wymuszał ponowne przeliczenie za każdym razem, gdy analityk otworzy dashboard. Tabela materialized daje predictable performance.

`fct_orders` dodatkowo jako `incremental` — bo tabela zamówień będzie rosnąć (dzisiaj 1M wierszy, za 2 lata 100M). Pełny rebuild codziennie o 5:00 to marnotrawstwo.

`dim_customers` jako `table` (nie incremental) — wymiar jest mały i szybko się rebuilduje; incremental na dim wprowadziłby ryzyko rozjazdu SK po `--full-refresh`.

---

## 2. Strategia incremental dla `fct_orders`

### Dlaczego `merge`, a nie `append`?

Status zamówienia **ewoluuje w czasie**: `pending` -> `completed` (lub `cancelled` / `refunded`). Klient może złożyć zamówienie o 23:45 (status `pending`, ładujemy do fct_orders o 5:00 następnego dnia), zapłacić rano — i teraz w Bronze mamy tego samego `order_id` ze statusem `completed`.

- **`append`**: dołoży drugi wiersz. `fct_orders` miałoby duplikaty per `order_id` z różnymi statusami — dashboard by pokazał "2 zamówienia zamiast 1", CLV byłby zawyżony.
- **`merge`** na `unique_key='order_sk'`: nadpisuje istniejący wiersz nowszą wersją. 1 zamówienie = 1 wiersz, zawsze aktualny status. To jest to, co chcemy.

### Jak działa filtr `is_incremental()`?

```sql
{% if is_incremental() %}
where ordered_at >= (
    select coalesce(dateadd(day, -3, max(ordered_at)), cast('1900-01-01' as timestamp))
    from {{ this }}
)
{% endif %}
```

Trzy właściwości:

1. **Idempotentność**: przy rerun tego samego dnia bez nowych danych filtr zwróci ten sam zestaw wierszy — merge je nadpisze identyczną wartością, brak duplikatów.
2. **3-dniowa zakładka** (`dateadd(day, -3, max(ordered_at))`): łapie zamówienia, których status zmienił się wstecznie (np. `pending` z pn. -> `completed` w śr. — bez zakładki `merge` by je pominął).
3. **Fallback** przez `coalesce(..., '1900-01-01')`: pierwsze uruchomienie (`{{ this }}` puste) traktuje jako pełny build.

### Kiedy `--full-refresh`?

- Zmiana schematu (nowa kolumna niekompatybilna z `on_schema_change='append_new_columns'`)
- Zmiana logiki wyliczania `total_amount_pln` (np. inne stawki VAT)
- Zmiana filtra `is_incremental()`
- Rollback po incydencie (uszkodzony wiersz w prod)

W CI/CD używamy Slim CI z `--defer`, więc `--full-refresh` jest rezerwowany na świadome deploy'e.

---

## 3. SCD2 — historia klientów

### Dlaczego snapshot zamiast ręcznego SQL?

Ręczna logika SCD2 to `INSERT` nowych + `UPDATE dbt_valid_to` starych, obudowane w transakcję. To dużo kodu, który trzeba testować i który łatwo zepsuć (race condition, brak transakcji na Databricks SQL Warehouse itd.).

`dbt snapshot`:
- Generuje kolumny `dbt_scd_id`, `dbt_valid_from`, `dbt_valid_to`, `dbt_updated_at` automatycznie
- Ma wbudowane strategie (`timestamp`, `check`)
- Obsługuje `invalidate_hard_deletes`
- Jest testowalny (`dbt test --select dim_customers_snapshot`)

**Ograniczenia**: snapshot musi być uruchamiany regularnie (jeśli klient zmienił email 3 razy między dwoma runami, w snapshot zapisze się tylko ostatnia wersja — historia się "spłaszcza"). Dlatego snapshot jest **pierwszy taskiem** w Databricks Job (przed `dbt build`).

### `invalidate_hard_deletes=True` — co robi?

Gdy klient znika ze źródła (Bronze), snapshot zamiast go pominąć — ustawia `dbt_valid_to = current_timestamp()`. W efekcie w snapshocie widać, że klient "istniał do dnia X". Bez tego parametru klient by po prostu miał zamrożoną historię, ale nie było by śladu, że go już nie ma.

---

## 4. Surrogate keys

### Dlaczego `customer_sk` zamiast `customer_id` w faktach?

Trzy powody:

1. **SCD2**: ten sam `customer_id` ma wiele wierszy w snapshocie (email się zmienił). Fakt musi wiedzieć, do **której wersji** klienta się odnosi — SK jednoznacznie identyfikuje wersję (choć w tym projekcie `dim_customers` używamy z current-only wariantu, więc SK = 1:1 z customer_id; snapshot jest osobno).
2. **Odporność na zmianę PK** w źródle (np. migracja z int na uuid). SK jest stabilny (hash), nawet jeśli klient dostanie nowe `customer_id`.
3. **Kompozytowe klucze naturalne** (np. `date` + `country` w `fct_daily_revenue`) — SK to hash, jedno pole zamiast dwóch w joinach.

Generacja: `dbt_utils.generate_surrogate_key(['customer_id'])` — deterministyczna, powtarzalna, kompatybilna między silnikami.

---

## 5. Schemat dev vs prod

### Rozdzielenie środowisk

| Środowisko | Katalog | Schemat | Kto pisze |
|------------|---------|---------|-----------|
| dev | `ecommerce_dev` | `dbt_dev_<user>_staging`, `dbt_dev_<user>_gold`, `dbt_dev_<user>_snapshots` | developer lokalnie |
| ci | `ecommerce_dev` | `dbt_ci_<run_id>_staging`, `dbt_ci_<run_id>_gold` | GitHub Actions |
| prod | `ecommerce_prod` | `staging`, `gold`, `snapshots` (bez prefixu) | Databricks Job z main |

### Jak działa `generate_schema_name` override

```jinja
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- set default_schema = target.schema -%}
    {%- if target.name == 'prod' and custom_schema_name is not none -%}
        {{ custom_schema_name | trim }}                          -- prod: 'gold', 'snapshots'
    {%- elif custom_schema_name is none -%}
        {{ default_schema }}
    {%- else -%}
        {{ default_schema }}_{{ custom_schema_name | trim }}     -- dev: 'dbt_dev_michal_gold'
    {%- endif -%}
{%- endmacro %}
```

Efekt: w dev każdy developer ma **własny sandbox** (`dbt_dev_michal_*`), bez ryzyka zderzenia. W prod nazwy są krótkie i eleganckie (`gold.fct_orders`, nie `dbt_prod_gold.fct_orders`).

---

## 6. Makra własne

### `price_tier(amount_column)`

- **Co robi**: klasyfikuje kwotę do koszyka (`budget` < 100, `standard` < 500, `premium` < 2000, `luxury` >= 2000).
- **Gdzie używane**: `dim_products.price_tier` (unit_price_pln) + `fct_orders.price_tier` (total_amount_pln).
- **Powtarzalność**: bez makra ten sam CASE WHEN byłby w 2 miejscach; jeśli zmienią się progi (np. inflacja), musiałbym pamiętać oba. Makro daje **jedno miejsce prawdy**.

### `revenue_bucket(revenue_column)`

- **Co robi**: segmentuje sumę przychodu klienta (`none`, `low`, `medium`, `high`, `vip`).
- **Gdzie używane**: `fct_customer_clv.revenue_bucket`.
- **Powtarzalność**: obecnie 1 użycie, ale w praktyce ta sama logika trafi też do ad-hoc analiz (`analyses/*.sql`) i feature engineering dla ML.

### `is_pl_holiday(date_column)`

- **Co robi**: zwraca `boolean` dla stałych świąt PL (9 dat).
- **Gdzie używane**: `dim_date.is_pl_holiday`.
- **Ograniczenie**: **nie obsługuje** świąt ruchomych (Wielkanoc, Boże Ciało) — te wymagają algorytmu Gaussa. Przyszła iteracja: dołączyć tabelę seed `pl_holidays` z konkretnymi datami na 10 lat do przodu.

### `generate_schema_name(custom_schema_name, node)`

- **Co robi**: override standardowego zachowania dbt (patrz sekcja 5).
- **Powód**: bez tego dev by nadpisywał prod, a każdy developer wchodziłby innym na palce.

---

## 7. Decyzje testowe

### Severity: `error` vs `warn`

**Error** (domyślnie — pipeline fails):
- `not_null` / `unique` na PK i SK (`customer_sk`, `order_sk`, `product_sk`) — złamanie oznacza korupcję modelu wymiarowego, dashboardy pokażą duplikaty.
- `accepted_values` na `order_status` — nieznany status blokuje logikę CLV (nie wiemy, czy jest completed).
- `dbt_utils.expression_is_true: ">= 0"` na kwotach — ujemny przychód to błąd biznesowy, nie zdarza się.
- Singular `assert_no_negative_revenue` — druga linia obrony.
- Singular `assert_clv_revenue_matches_completed_orders` — spójność między faktami, krytyczna dla wiarygodności BI.

**Warn** (log, pipeline continues):
- `accepted_values` na `country` — chcemy widzieć nowe kraje ekspansji, nie blokować deploya.
- `dbt_expectations.expect_column_values_to_match_regex` na email — źle sformatowane emaile logujemy, ale klient wciąż jest liczony w CLV.
- `dbt_expectations.expect_column_values_to_be_between` na kwotach — górna granica jest heurystyką (nie chcemy wywrócić pipeline'a przez jedno legalne, duże zamówienie B2B).
- `relationships` staging -> staging — dane w Bronze mogą być tymczasowo niespójne (opóźnienie CDC), ostrzegamy, nie blokujemy.

---

## 8. Lineage — diagram zależności

```
source(ecommerce_bronze.orders) ────► stg_orders ──┐
                                                   │
source(ecommerce_bronze.order_items) ► stg_order_items ┐
                                                       │
source(ecommerce_bronze.customers) ─► stg_customers ┐  │
                                          │         │  │
                                          ▼         │  │
                                   dim_customers    │  │
                                          │         │  │
                                          │         ▼  ▼
                                          │      int_orders_enriched (ephemeral)
                                          │                 │
                                          └────► fct_orders (incremental merge)
                                                      │
                                                      ├─► fct_daily_revenue (completed only)
                                                      │
                                                      └─► fct_customer_clv (revenue z completed)

source(ecommerce_bronze.products) ──► stg_products ──► dim_products (price_tier)

dim_date ← (dbt_utils.date_spine, join w BI po order_date)

stg_customers ──► dim_customers_snapshot (SCD2)

fct_daily_revenue ┐
fct_customer_clv  ├─► exposure: dashboard_ecommerce_gold (Power BI)
dim_customers     │
dim_products      │
dim_date          ┘

fct_customer_clv  ┐
dim_customers     ├─► exposure: ml_customer_churn_model (scikit-learn)
```

Kluczowe własności grafu:
- **Ephemeral (`int_orders_enriched`) nie jest widoczny jako obiekt w warehouse**, ale w lineage graph dbt jest widoczny — pokazuje przepływ.
- **`dim_customers` jest wcześniej niż `fct_orders`** — `fct_orders` joinuje na `customer_sk`, więc dim musi istnieć.
- **Snapshot jest oddzielnym pipelinem** — nie jest zależnością `dim_customers` (dim czyta z staging, snapshot też z staging). Ale w Databricks Job snapshot jest **pierwszy** (task `dbt_snapshot` -> `dbt_build`), żeby snapshot był "świeży" na dziś.
