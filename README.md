# ecommerce_dbt — Projekt zaliczeniowy Miesiąc 07 (dbt Core na Databricks)

## Opis projektu

Projekt dbt transformuje surowe dane e-commerce z warstwy **Bronze** (`ecommerce_dev.bronze` w Unity Catalog na Databricks) do warstwy **Gold** (`ecommerce_dev.gold` / `ecommerce_prod.gold`). Warstwa Gold jest źródłem dla dashboardów Power BI (przychody dzienne, segmentacja klientów) oraz modelu ML predykcji churnu. Projekt zastępuje ręczne notebooki PySpark tworzące warstwę Gold — całość jest przetestowana (24+ testy), udokumentowana po polsku, podłączona do CI/CD (GitHub Actions) i uruchamiana codziennie o 05:00 CET jako Databricks Job.

## Architektura

Szczegółowy opis decyzji projektowych w [ARCHITEKTURA.md](ARCHITEKTURA.md).

| Warstwa | Liczba modeli | Materializacja | Katalog / schemat (dev) |
|---------|---------------|----------------|-------------------------|
| staging | 4 | view | `ecommerce_dev.dbt_dev_<user>_staging` |
| intermediate | 1 | ephemeral | (inline'owany) |
| marts/core | 4 | table + incremental | `ecommerce_dev.dbt_dev_<user>_gold` |
| marts/analytics | 2 | table | `ecommerce_dev.dbt_dev_<user>_gold` |
| snapshots | 1 | snapshot (SCD2) | `ecommerce_dev.dbt_dev_<user>_snapshots` |

## Jak uruchomić lokalnie

### Wymagania

- Python 3.11+
- Dostęp do Databricks workspace (Unity Catalog + SQL Warehouse)
- Personal Access Token Databricks
- Git

### Instalacja

```bash
# 1. Klonuj repozytorium
git clone https://github.com/<login>/ecommerce_dbt.git
cd ecommerce_dbt

# 2. Środowisko wirtualne
python -m venv .venv
source .venv/bin/activate      # Linux / macOS
# .venv\Scripts\activate         # Windows

# 3. Instalacja dbt
pip install dbt-databricks==1.8.7

# 4. Skopiuj i skonfiguruj profiles.yml
cp ecommerce_dbt/profiles.yml.template ~/.dbt/profiles.yml
# Edytuj ~/.dbt/profiles.yml lub ustaw zmienne środowiskowe (patrz niżej)
```

### Wymagane zmienne środowiskowe

| Zmienna | Do czego | Przykład |
|---------|----------|----------|
| `DATABRICKS_HOST` | Host workspace | `adb-1234567890123456.7.azuredatabricks.net` |
| `DATABRICKS_HTTP_PATH` | HTTP path SQL Warehouse (dev) | `/sql/1.0/warehouses/abc123def456` |
| `DATABRICKS_HTTP_PATH_PROD` | HTTP path SQL Warehouse (prod) | `/sql/1.0/warehouses/prod789ghi012` |
| `DATABRICKS_HTTP_PATH_CI` | HTTP path SQL Warehouse (CI) | `/sql/1.0/warehouses/ci345jkl678` |
| `DATABRICKS_TOKEN` | Personal Access Token | `dapiXXXXXXXX` |
| `USER` | Nazwa użytkownika (do schematu dev) | `michal` |

**Uwaga bezpieczeństwa:** `profiles.yml` odczytuje wszystkie sekrety przez `env_var()` — nigdy nie commituj tokena do repo.

### Uruchomienie krok po kroku

```bash
cd ecommerce_dbt

# 1. Instalacja paczek dbt (dbt_utils, dbt_expectations, codegen)
dbt deps

# 2. Weryfikacja połączenia i konfiguracji
dbt debug

# 3. Snapshot SCD2 — PRZED build (żeby dim_customers widziało najnowszą wersję)
dbt snapshot

# 4. Pełny build z testami (staging + intermediate + marts + snapshot testy)
dbt build

# 5. Dokumentacja + lineage graph
dbt docs generate
dbt docs serve --port 8080
```

### Selektywne uruchamianie

```bash
# Tylko staging
dbt run --select staging

# Tylko fct_orders + wszystko co od niego zależy
dbt run --select fct_orders+

# Full refresh incremental (po zmianie logiki fct_orders)
dbt run --select fct_orders --full-refresh
```

## Struktura katalogów

```
ecommerce_dbt/                             # repo root
|── ecommerce_dbt/                         # projekt dbt (dbt_project.yml)
│   ├── dbt_project.yml
│   ├── packages.yml
│   ├── profiles.yml.template
│   ├── databricks_job_dbt_task.json       # konfiguracja Databricks Job (2 taski: snapshot + build)
│   ├── models/
│   │   ├── staging/                       # 4 view — czyszczenie danych Bronze
│   │   │   ├── _sources.yml
│   │   │   ├── _staging__models.yml
│   │   │   ├── stg_orders.sql
│   │   │   ├── stg_customers.sql
│   │   │   ├── stg_products.sql
│   │   │   └── stg_order_items.sql
│   │   ├── intermediate/                  # 1 ephemeral
│   │   │   ├── _int__models.yml
│   │   │   └── int_orders_enriched.sql
│   │   ├── marts/
│   │   │   ├── core/                      # 3 dim + 1 fct (incremental merge)
│   │   │   │   ├── _core__models.yml
│   │   │   │   ├── dim_customers.sql
│   │   │   │   ├── dim_products.sql
│   │   │   │   ├── dim_date.sql
│   │   │   │   └── fct_orders.sql
│   │   │   └── analytics/                 # 2 fct analityczne
│   │   │       ├── _analytics__models.yml
│   │   │       ├── fct_daily_revenue.sql
│   │   │       └── fct_customer_clv.sql
│   │   └── exposures.yml                  # 2 exposures: dashboard + ml
│   ├── macros/
│   │   ├── generate_schema_name.sql       # override dev/prod
│   │   ├── price_tier.sql                 # użyte w dim_products + fct_orders
│   │   ├── revenue_bucket.sql             # użyte w fct_customer_clv
│   │   └── is_pl_holiday.sql              # użyte w dim_date
│   ├── snapshots/
│   │   └── dim_customers_snapshot.sql     # SCD2, timestamp, invalidate_hard_deletes
│   ├── tests/                             # 3 singular tests
│   │   ├── assert_no_negative_revenue.sql
│   │   ├── assert_orders_have_items.sql
│   │   └── assert_clv_revenue_matches_completed_orders.sql
│   └── analyses/
│       └── audit_data_quality.sql
└── .github/workflows/
    ├── dbt_ci.yml                         # PR: Slim CI (state:modified+) + fallback
    └── dbt_deploy_prod.yml                # main: snapshot + build + upload manifest
```

## Testy

Projekt zawiera **24+ testów**:

| Typ | Ile | Gdzie |
|-----|-----|-------|
| Generyczne (`not_null`, `unique`, `accepted_values`, `relationships`) | 20+ | `_*.yml` w staging, core, analytics |
| `dbt_expectations` (regex email, expect_column_values_to_be_between) | 3 | `_staging__models.yml`, `_analytics__models.yml` |
| Singular (własny SQL) | 3 | `tests/*.sql` |
| `dbt_utils.expression_is_true` / `unique_combination_of_columns` | 6 | głównie marts |

Uruchomienie:

```bash
dbt test                              # wszystkie testy
dbt test --select staging             # tylko staging
dbt test --select test_type:singular  # tylko singular
dbt build --fail-fast                 # build + testy, zatrzymaj przy pierwszym błędzie
```

Nierozwiązane WARN (świadomie):
- `stg_customers.country` `accepted_values` z `severity: warn` — chcemy widzieć nowe kraje, ale nie blokować pipeline'a
- `stg_customers.email` regex `severity: warn` — źle sformatowane emaile logujemy, ale nie odrzucamy klienta
- `expect_column_values_to_be_between` dla kwot — górna granica jest heurystyczna

## CI/CD

**Workflow: `.github/workflows/dbt_ci.yml`**

- **Trigger:** `pull_request` na `main`, path filter na `ecommerce_dbt/**`
- **Strategia:** Slim CI (`--select state:modified+ --defer --state ./prod-artifacts`) z fallbackiem do pełnego buildu jeśli brak manifestu z prod
- **Sekrety:** wszystkie credentiale w `${{ secrets.* }}` (`DATABRICKS_HOST`, `DATABRICKS_HTTP_PATH_CI`, `DATABRICKS_TOKEN`)
- **Artefakty:** dokumentacja dbt uploadowana jako artifact PR (retention 7 dni)

**Workflow: `.github/workflows/dbt_deploy_prod.yml`**

- **Trigger:** `push` do `main` z path filter na `ecommerce_dbt/**`
- **Kolejność:** `dbt deps` -> `dbt snapshot --target prod` -> `dbt build --target prod`
- **Manifest:** po deployu uploadowany jako artifact `prod-manifest`, żeby Slim CI w kolejnych PR-ach miał punkt odniesienia

## Databricks Job

Plik `ecommerce_dbt/databricks_job_dbt_task.json` — 2 taski (snapshot -> build), harmonogram cron `0 0 5 * * ?` (05:00 CET codziennie), email alert na failure, git source z main.

Import:

```bash
databricks jobs create --json-file ecommerce_dbt/databricks_job_dbt_task.json
```

Przed importem podmień:
- `REPLACE_WITH_SQL_WAREHOUSE_ID` — ID SQL Warehouse
- `REPLACE_WITH_USERNAME` — Twój GitHub username

## Decyzje projektowe

Zobacz [ARCHITEKTURA.md](ARCHITEKTURA.md) — pełny opis materializacji, incremental merge, SCD2, surrogate keys, dev/prod, makr, testów i lineage.

## Autor

Michał Leśniak — kurs Data Engineering, miesiąc 07 (dbt).
