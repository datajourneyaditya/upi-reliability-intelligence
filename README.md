# UPI Reliability Intelligence — on Databricks

One trusted data model of UPI payment reliability, built only on **real NPCI statistics**
(Jan 2022 – Sep 2026), serving three audiences: merchants, fintech partner teams, and consumer-app PMs.
This is the Databricks implementation of the design doc (Snowflake → Unity Catalog, Airflow → Lakeflow Jobs,
dbt Core → dbt-databricks, semantic layer → Unity Catalog metric views).

## Design doc → Databricks mapping

| Design doc | Built here |
|---|---|
| Snowflake raw files + parsed rows | UC volume `upi_reliability.raw.npci_landing` (immutable JSON) → `raw.npci_api_responses`, `raw.npci_stat_rows` |
| Airflow monthly with retry | Lakeflow Job `upi_reliability_monthly` (ID `62814739004654`), 25th of each month 06:30 IST, task retries |
| dbt Core staging / intermediate / marts | dbt-databricks project in `dbt/`, run by the job's dbt task on the Serverless SQL warehouse |
| dbt snapshots, SCD2 `dim_bank` | `snapshots.snap_bank_master` + `marts.dim_bank` (versions from published-name history) |
| Semantic layer | UC metric views `metrics.bank_reliability`, `metrics.psp_reliability`, `metrics.ecosystem` |
| Alerting | `degradation_alert_check` job task (`semantic/alerts_degradation.sql`) + job failure email |
| Slim CI on PRs | `.github/workflows/dbt_ci.yml` (`state:modified+`, `--defer`, isolated `ci_pr<N>_*` schemas) |
| Cost tracking per model | `semantic/cost_by_model.sql` (system.query.history × system.billing) |

## Architecture

```
npci.org.in statistics API ──(browser capture; NPCI returns 403 to scripts)──► bundle JSON
        │  ingestion/00_split_bundle.py  (one immutable file per dataset × month)
        ▼
/Volumes/upi_reliability/raw/npci_landing/<dataset>/<yyyy>/<yyyy>_<mm>.json
        │  ingestion/01_ingest_npci_raw.py  (hash-based idempotent load)
        ▼
upi_reliability.raw          npci_api_responses (1 row / response), npci_stat_rows (1 row / table row, MAP<string,string>)
        │  dbt
        ▼
upi_reliability.staging      5 contracted views + seeds (bank_master, bank_aliases, psp_apps)
upi_reliability.intermediate name resolution, bank/PSP baselines (MoM, rolling 3m, volatility, degradation)
upi_reliability.snapshots    snap_bank_master (SCD2 reference data)
upi_reliability.marts        dims, facts, audience marts
upi_reliability.metrics      metric views (semantic layer)
```

## Data (all from NPCI)

| Dataset | NPCI table | Grain | Months |
|---|---|---|---|
| `remitter_banks` | Top 50 Member Performance → Remitter | bank × month | 57 |
| `beneficiary_banks` | Top 50 Member Performance → Beneficiary | bank × month | 57 |
| `payer_psp` / `payee_psp` | Top 15 PSPs → Payer / Payee | PSP bank × month | 57 each |
| `upi_apps` | UPI Applications | app × month (volume/value only) | 57 |
| `ecosystem_monthly` | UPI Product Statistics | month | 67 (from Apr 2021) |

**Limitations, stated plainly**
- NPCI publishes the **top 50** banks and **top 15** PSPs only; together they carry ~96–98% of successful volume.
- NPCI's "PSP" tables are the sponsor **banks** (e.g. Yes Bank for PhonePe), not apps. App tables have **no decline rates**,
  so app exposure in `mart_app_checkout_risk` is *indicative*: app volume × its sponsor banks' payer-side TD, with sponsors
  taken from public VPA handles (`seeds/psp_apps.csv`).
- Merchant and consumer-app views use bank- and app-wide rates as risk indicators; they do not measure any merchant's own checkout.
- NPCI blocks non-browser clients, so monthly capture is a browser step (see *Monthly refresh*).

## Data quality findings in NPCI's published data (handled in staging, each row flagged)

| Issue | Where | Handling |
|---|---|---|
| Debit reversal success published ×100 (`9123.00%`) | Remitter, Aug 2022 | ÷100, `is_debit_reversal_rescaled` |
| Rates published as fractions (`0.99`) | Payer & payee PSP, May–Jun 2026 | ×100, `is_fraction_rescaled` |
| Approved % = 124.22 | Tamilnad Mercantile Bank (beneficiary), Sep 2024 | rebuilt as 100 − BD − TD − deemed, `is_approved_pct_rebuilt` |
| `NaN` strings | Remitter debit reversal, 9 months | → null |
| Same bank listed twice in a month | slice SFB, Mar & Jun 2026; several apps | grain is the source row; facts combine volume-weighted |
| ~90 spellings for ~80 entities | all bank tables | normalised key + `seeds/bank_aliases.csv` |
| Approved + BD + TD + deemed approved = 101–111% | ~60 beneficiary bank-months | kept; `rates_reconcile` test warns |
| Bank tables count attempts, ecosystem counts successes | coverage metric | coverage uses approved volume |

## Model

**Facts:** `fct_bank_monthly_performance` (bank × month × role, incremental merge with 6-month restatement window),
`fct_psp_monthly_performance` (PSP bank × month × role), `fct_app_monthly_volume`, `fct_ecosystem_monthly`.

**Dimensions:** `dim_bank` (SCD2: one version per published-name run, e.g. *National Payments Corporation of India (BHIM)* →
*NPCI BHIM Services (NBSL)*, *AU Small Finance Bank* → *(Erstwhile Fincare)*; bank category from the snapshot),
`dim_psp_app`, `dim_date` (with Indian fiscal year).

**Audience marts**
- `mart_merchant_bank_scorecard`: beneficiary bank ranking, risk flags, collection risk tier, recommendation.
- `mart_fintech_partner_health`: every partner across remitter / beneficiary / payer PSP / payee PSP; degradation
  alert, consecutive degraded months, failures in excess of the bank's own baseline, health status.
- `mart_payer_bank_checkout_risk`: payer banks' share of failures, Pareto rank, TD vs market, suggested checkout action.
- `mart_app_checkout_risk`: app volume share with indicative sponsor-PSP TD exposure.

## Dashboard

AI/BI dashboard **UPI Reliability Intelligence**
([published](https://dbc-df33b073-3796.cloud.databricks.com/dashboardsv3/01f1d7ffc3bd1fa5bbd75c1acf36ee67/published)),
generated from code in `dashboards/` (`datasets.py` = SQL, `build_dashboard.py` = layout, `deploy_dashboard.sh` = create/update + publish).

| Page | Audience | Shows |
|---|---|---|
| Overview | everyone | Latest-month KPIs, TD and BD trends, TD by bank type (queried through the metric view), volume and estimated failures |
| Merchants | merchants | Beneficiary-bank scorecard (rank, score, risk tier, recommendation), risk-tier mix over time |
| Fintech partners | fintech teams | Partners not healthy this month, TD vs own baseline with bank / side filters, degraded partners per month |
| Consumer checkout | app PMs | Top-15 payer banks by failure share, payer-bank checkout actions, app exposure via sponsor PSP banks |

"Latest month" always means the latest month with bank-level data, so the dashboard moves forward when the job loads a new month.

## Metrics

| Metric | Definition |
|---|---|
| Technical decline rate | Σ(volume × TD%) / Σ volume |
| Business decline rate | Σ(volume × BD%) / Σ volume |
| Estimated failed transactions | volume × TD% |
| Degradation flag | TD ≥ trailing 3-month volume-weighted baseline + 0.30 pp **and** ≥ 2× baseline (needs 3 baseline months). Calibrated to flag ~11% of bank-months. |
| Reliability score (0–100) | Within month × role: 50% TD level (trailing 3m), 25% TD trend (last 3m vs prior 3m), 25% volatility (6m std dev), each a percent rank |
| Debit reversal success | Σ(reversal count × success%) / Σ reversal count |

Thresholds live in `dbt/dbt_project.yml` vars.

## Tests (91)
Uniqueness at every grain, not-null keys, percentages within 0–100, rate reconciliation (approved + BD + TD (+ deemed) ≈ 100),
relationships fact → dim, one current SCD2 version per bank, accepted values, source freshness (warn 35 days, error 50 days),
and enforced column contracts on all staging models.

## Monthly refresh
1. Around the 20th, open the NPCI ecosystem statistics page in a browser and capture the new month (same API calls as the
   initial load) into a bundle JSON.
2. `python3 -I ingestion/00_split_bundle.py <bundle.json> raw_landing/npci_landing` then
   `databricks fs cp -r raw_landing/npci_landing dbfs:/Volumes/upi_reliability/raw/npci_landing --overwrite`.
3. The job runs on the 25th (or `jobs/deploy.sh --run`). Ingestion only loads responses whose content hash changed, so
   reruns are no-ops and NPCI restatements are picked up. If nothing new lands, source freshness warns.

## Repo layout
```
ingestion/   00_split_bundle.py, 01_ingest_npci_raw.py (Databricks notebook)
dbt/         dbt project (models, seeds, snapshots, macros incl. custom generic tests)
semantic/    metric_views.sql, alerts_degradation.sql, cost_by_model.sql
dashboards/  AI/BI dashboard as code (datasets, layout, deploy script)
jobs/        upi_reliability_job.json, deploy.sh, run_dbt_once.sh
raw_landing/ captured NPCI bundle + split landing files (immutable)
.github/     slim CI workflow
```
