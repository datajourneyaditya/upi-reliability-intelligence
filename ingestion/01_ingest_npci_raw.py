# Databricks notebook source
# MAGIC %md
# MAGIC # 01 · Ingest NPCI raw API responses → `upi_reliability.raw`
# MAGIC
# MAGIC **Source:** NPCI UPI Ecosystem Statistics and Product Statistics (npci.org.in). NPCI exposes the
# MAGIC tables through the JSON API behind its website, but blocks non-browser clients (HTTP 403), so the
# MAGIC monthly files are captured through a browser and landed **unchanged** in the Unity Catalog volume
# MAGIC `/Volumes/upi_reliability/raw/npci_landing/<dataset>/<year>/<year>_<mm>.json`.
# MAGIC
# MAGIC Each landing file holds `{source_url, fetched_at, dataset, year, month, body}` where `body` is the
# MAGIC verbatim API response.
# MAGIC
# MAGIC This notebook:
# MAGIC 1. Lists every landing file and loads new or changed ones into `raw.npci_api_responses`
# MAGIC    (one row per file, verbatim body, content hash, load timestamp) — **idempotent MERGE**.
# MAGIC 2. Explodes the response rows into `raw.npci_stat_rows` (one row per source table row, every
# MAGIC    field kept as a string in a `MAP`) — again MERGE on (dataset, period, row number).
# MAGIC
# MAGIC Nothing here cleans or casts data; that is dbt staging's job.

# COMMAND ----------

dbutils.widgets.text("catalog", "upi_reliability")
CATALOG = dbutils.widgets.get("catalog")
LANDING = f"/Volumes/{CATALOG}/raw/npci_landing"

# COMMAND ----------

import json, hashlib
from datetime import datetime, timezone
from pyspark.sql import Row, functions as F, types as T

def list_json(path):
    out = []
    for f in dbutils.fs.ls(path):
        if f.isDir():
            out.extend(list_json(f.path))
        elif f.name.endswith(".json"):
            out.append(f.path)
    return out

files = list_json(LANDING)
print(f"{len(files)} landing files found")

MONTHS = {m: i + 1 for i, m in enumerate(
    ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"])}

resp_rows, stat_rows = [], []
load_ts = datetime.now(timezone.utc)
for path in files:
    local = path.replace("dbfs:", "")
    with open(local, "r", encoding="utf-8") as fh:
        text = fh.read()
    doc = json.loads(text)
    body = doc["body"]
    body_txt = json.dumps(body, sort_keys=True, ensure_ascii=False)
    content_hash = hashlib.sha256(body_txt.encode("utf-8")).hexdigest()
    dataset = doc["dataset"]
    year, month = int(doc["year"]), doc["month"]
    month_num = MONTHS[month] if isinstance(month, str) else int(month)
    period = f"{year:04d}-{month_num:02d}-01"
    data = (body or {}).get("data") or {}
    results = data.get("results") or []
    title = (data.get("table_headers") or {}).get("main_header_title")
    resp_rows.append(Row(
        dataset=dataset, period_month=period, source_url=doc["source_url"],
        fetched_at=doc["fetched_at"], file_path=path, content_hash=content_hash,
        api_status=(body or {}).get("status"), table_title=title, row_count=len(results),
        body_json=body_txt, _loaded_at=load_ts))
    for i, r in enumerate(results):
        stat_rows.append(Row(
            dataset=dataset, period_month=period, row_num=i + 1, table_title=title,
            fields={k: (None if v is None else str(v)) for k, v in r.items()},
            source_url=doc["source_url"], content_hash=content_hash, _loaded_at=load_ts))

print(f"{len(resp_rows)} responses, {len(stat_rows)} table rows parsed")

# COMMAND ----------

spark.sql(f"""
CREATE TABLE IF NOT EXISTS {CATALOG}.raw.npci_api_responses (
  dataset STRING NOT NULL COMMENT 'NPCI table: remitter_banks, beneficiary_banks, payer_psp, payee_psp, upi_apps, ecosystem_monthly',
  period_month STRING NOT NULL COMMENT 'First day of the reporting month (yyyy-MM-01)',
  source_url STRING COMMENT 'NPCI API URL the response came from',
  fetched_at STRING COMMENT 'When the response was captured (UTC)',
  file_path STRING COMMENT 'Landing file in the raw volume',
  content_hash STRING COMMENT 'sha256 of the response body; drives idempotent reloads',
  api_status INT,
  table_title STRING COMMENT 'NPCI table title, e.g. UPI Remitter Banks - Top 50 Banks(Sep''26)',
  row_count INT,
  body_json STRING COMMENT 'Verbatim API response body',
  _loaded_at TIMESTAMP
) COMMENT 'Immutable landing log: one row per NPCI monthly API response'
""")

spark.sql(f"""
CREATE TABLE IF NOT EXISTS {CATALOG}.raw.npci_stat_rows (
  dataset STRING NOT NULL,
  period_month STRING NOT NULL,
  row_num INT NOT NULL,
  table_title STRING,
  fields MAP<STRING, STRING> COMMENT 'Every source column as published, unparsed',
  source_url STRING,
  content_hash STRING,
  _loaded_at TIMESTAMP
) COMMENT 'NPCI table rows exploded from raw responses, values untouched'
""")

# COMMAND ----------

resp_schema = spark.table(f"{CATALOG}.raw.npci_api_responses").schema
stat_schema = spark.table(f"{CATALOG}.raw.npci_stat_rows").schema

spark.createDataFrame(resp_rows, resp_schema).createOrReplaceTempView("new_responses")
spark.createDataFrame(stat_rows, stat_schema).createOrReplaceTempView("new_stat_rows")

# A response is (re)loaded only when its content hash changes, so reruns are no-ops and NPCI
# restatements of an earlier month are picked up.
spark.sql(f"""
CREATE OR REPLACE TEMP VIEW changed AS
SELECT s.dataset, s.period_month
FROM new_responses s
LEFT JOIN {CATALOG}.raw.npci_api_responses t
  ON t.dataset = s.dataset AND t.period_month = s.period_month AND t.content_hash = s.content_hash
WHERE t.dataset IS NULL
""")
n_changed = spark.table("changed").count()
print(f"{n_changed} new or restated (dataset, month) responses")

# Rows first, response log last: if the run dies midway, the log still lacks the new hash and the
# retry reloads that month. Rows of a changed month are replaced wholesale (a restated table can
# have fewer rows).
spark.sql(f"""
MERGE INTO {CATALOG}.raw.npci_stat_rows t
USING changed c
ON t.dataset = c.dataset AND t.period_month = c.period_month
WHEN MATCHED THEN DELETE
""")
spark.sql(f"""
INSERT INTO {CATALOG}.raw.npci_stat_rows
SELECT s.* FROM new_stat_rows s JOIN changed c USING (dataset, period_month)
""")

spark.sql(f"""
MERGE INTO {CATALOG}.raw.npci_api_responses t
USING (SELECT s.* FROM new_responses s JOIN changed c USING (dataset, period_month)) s
ON t.dataset = s.dataset AND t.period_month = s.period_month
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *
""")

# COMMAND ----------

display(spark.sql(f"""
SELECT dataset, count(*) months, min(period_month) first_month, max(period_month) last_month,
       sum(row_count) rows, max(_loaded_at) last_load
FROM {CATALOG}.raw.npci_api_responses GROUP BY dataset ORDER BY dataset
"""))
