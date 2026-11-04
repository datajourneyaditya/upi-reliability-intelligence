#!/usr/bin/env bash
# Sync the dbt project and run one ad-hoc dbt task (default: seed + snapshot + build).
# Usage: jobs/run_dbt_once.sh ["dbt build --select ..."]
set -euo pipefail
cd "$(dirname "$0")/.."
D=${DATABRICKS_CLI:-$HOME/.local/bin/databricks}
W=/Workspace/Users/adityasawant2205@gmail.com/upi_reliability
rm -rf dbt/target dbt/logs
$D workspace import-dir dbt "$W/dbt" --overwrite -p DEFAULT >/dev/null
CMDS=${1:-'"dbt seed", "dbt snapshot", "dbt build --exclude resource_type:seed resource_type:snapshot"'}
$D jobs submit -p DEFAULT --timeout 45m -o json --json "{
  \"run_name\": \"upi_dbt_adhoc\",
  \"environments\": [{\"environment_key\": \"dbt_env\", \"spec\": {\"client\": \"2\", \"dependencies\": [\"dbt-databricks>=1.10,<1.11\"]}}],
  \"tasks\": [{\"task_key\": \"dbt\", \"environment_key\": \"dbt_env\", \"dbt_task\": {\"source\": \"WORKSPACE\",
    \"project_directory\": \"$W/dbt\", \"warehouse_id\": \"b36027f0bc1ea75e\", \"catalog\": \"upi_reliability\", \"schema\": \"marts\",
    \"commands\": [$CMDS]}}]}" > /dev/null 2>&1 || true
RUN=$($D jobs list-runs -p DEFAULT --limit 1 --expand-tasks -o json | python3 -c "import json,sys;r=json.load(sys.stdin)[0];print(r['tasks'][0]['run_id'])")
$D jobs get-run-output "$RUN" -p DEFAULT -o json | python3 -c "
import json,sys,re;d=json.load(sys.stdin);log=d.get('logs') or ''
print('ERROR:', (d.get('error') or '')[:300])
lines=log.splitlines()
keep=[l for l in lines if re.search(r'(ERROR|FAIL|WARN|Failure|Warning|Done\.|Got \d+|Database Error|Compilation Error|Runtime Error)', l)]
print('\n'.join(keep[-60:]))
"
