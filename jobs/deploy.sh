#!/usr/bin/env bash
# Sync code to the workspace and create/update the Lakeflow Job. Usage: jobs/deploy.sh [--run]
set -euo pipefail
cd "$(dirname "$0")/.."
D=${DATABRICKS_CLI:-$HOME/.local/bin/databricks}
P=${DATABRICKS_PROFILE:-DEFAULT}
W=/Workspace/Users/adityasawant2205@gmail.com/upi_reliability
rm -rf dbt/target dbt/logs
$D workspace import-dir dbt "$W/dbt" --overwrite -p "$P" >/dev/null
$D workspace import-dir semantic "$W/semantic" --overwrite -p "$P" >/dev/null
$D workspace import "$W/ingestion/01_ingest_npci_raw" --file ingestion/01_ingest_npci_raw.py --language PYTHON --format SOURCE --overwrite -p "$P"
JOB_ID=$($D jobs list -p "$P" -o json | python3 -c "import json,sys;print(next((str(j['job_id']) for j in json.load(sys.stdin) if j['settings']['name']=='upi_reliability_monthly'),''))")
if [ -z "$JOB_ID" ]; then
  JOB_ID=$($D jobs create --json @jobs/upi_reliability_job.json -p "$P" -o json | python3 -c "import json,sys;print(json.load(sys.stdin)['job_id'])")
  echo "created job $JOB_ID"
else
  $D jobs reset --json "{\"job_id\": $JOB_ID, \"new_settings\": $(cat jobs/upi_reliability_job.json)}" -p "$P"
  echo "updated job $JOB_ID"
fi
if [ "${1:-}" = "--run" ]; then
  $D jobs run-now "$JOB_ID" -p "$P" --timeout 60m -o json | python3 -c "import json,sys;r=json.load(sys.stdin);print(r['state'].get('result_state'), r['run_page_url'])"
fi
